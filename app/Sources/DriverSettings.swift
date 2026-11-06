import Foundation
import IOKit
import CoreAudio

/// Operation mode of the PreSonus FireWire audio driver (PaeFireStudio.kext, TC Applied Technologies DICE driver).
///
/// The driver exposes it through its own IOKit user client, independently of the FireWire mixer access:
/// selector 7 reads it (4-byte struct out), selector 8 sets it (4-byte struct in, 0...3).
/// A higher mode enlarges the isochronous safety buffers (about +32 output and +16 input samples per step
/// at 48 kHz) and restarts the audio stream. The PreSonus daemon saves it in
/// /Library/Preferences/PaeFireStudio.startup and restores it at boot. See docs/driver-settings.md.
enum DriverSettings {
    static let modes = 0...3
    static let defaultMode = 1
    private static let selGetOpMode: UInt32 = 7
    private static let selSetOpMode: UInt32 = 8

    private static func withConnection<T>(_ body: (io_connect_t) -> T?) -> T? {
        let svc = IOServiceGetMatchingService(0, IOServiceMatching("PaeFireStudio"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        var conn: io_connect_t = 0
        guard IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return nil }
        defer { IOServiceClose(conn) }
        return body(conn)
    }

    /// Current mode, or nil when the PreSonus driver is not loaded.
    static func opMode() -> Int? {
        withConnection { c in
            var mode: UInt32 = 0
            var size = MemoryLayout<UInt32>.size
            guard IOConnectCallStructMethod(c, selGetOpMode, nil, 0, &mode, &size) == KERN_SUCCESS else { return nil }
            return Int(mode)
        }
    }

    @discardableResult
    static func setOpMode(_ mode: Int) -> Bool {
        guard modes.contains(mode) else { return false }
        return withConnection { c in
            var m = UInt32(mode)
            return IOConnectCallStructMethod(c, selSetOpMode, &m, MemoryLayout<UInt32>.size, nil, nil) == KERN_SUCCESS
        } ?? false
    }

    /// Stream error counters kept by the driver since it loaded or since the last reset (selector 12, 0x20 bytes):
    /// +0x10 receive errors (ReadFirewireBuffers), +0x18 transmit errors (FillFirewireBuffers),
    /// +0x1C late transmit callbacks (SendGroupCallback).
    static func errorCounts() -> ErrorCounts? {
        withConnection { c in
            var b = [UInt32](repeating: 0, count: 8)
            var size = 0x20
            guard IOConnectCallStructMethod(c, 12, nil, 0, &b, &size) == KERN_SUCCESS else { return nil }
            return ErrorCounts(playback: Int(b[6]), recording: Int(b[4]), timing: Int(b[7]))
        }
    }

    /// Selector 13: resets the three counters.
    static func clearErrorCounts() {
        _ = withConnection { c in IOConnectCallStructMethod(c, 13, nil, 0, nil, nil) }
    }

    // MARK: Several units (one aggregated Core Audio device)

    /// Selector 3 (GetConfigInfo, 0xEE8 bytes): clock master and the units the driver aggregates.
    static func busConfig() -> BusConfig? {
        withConnection { c in
            var b = [UInt8](repeating: 0, count: 0xEE8)
            var size = b.count
            guard IOConnectCallStructMethod(c, 3, nil, 0, &b, &size) == KERN_SUCCESS, size == 0xEE8 else { return nil }
            func u32(_ o: Int) -> UInt32 { b[o..<o + 4].reversed().reduce(0) { $0 << 8 | UInt32($1) } }
            func u64(_ o: Int) -> UInt64 { UInt64(u32(o)) | UInt64(u32(o + 4)) << 32 }
            var devices: [BusDevice] = []
            for i in 0..<5 {
                let e = 0xD20 + i * 0x58
                let g = u64(e)
                guard g != ~0, g != 0 else { continue }
                let raw = b[(e + 8)..<(e + 8 + 64)].prefix { $0 != 0 }
                devices.append(BusDevice(guid: g, name: String(decoding: raw, as: UTF8.self),
                                         slot: Int(u32(e + 0x4C)), state: Int(u32(e + 0x48))))
            }
            return BusConfig(master: u64(0), devices: devices)
        }
    }

    /// Selector 6 (SetMaster, 8-byte struct): makes this unit the clock master. The driver restarts streaming.
    @discardableResult
    static func setMaster(_ guid: UInt64) -> Bool {
        withConnection { c in
            var g = guid
            return IOConnectCallStructMethod(c, 6, &g, 8, nil, nil) == KERN_SUCCESS
        } ?? false
    }

    static let maxNameBytes = 63

    /// Selector 17 (SetNickName, 0x200-byte struct in and out): +0 driver slot, +0x1C0 name (64 bytes).
    /// The driver keeps the name in its nickname table, saved by the PreSonus daemon.
    @discardableResult
    static func setNickname(slot: Int, _ name: String) -> Bool {
        withConnection { c in
            var b = [UInt8](repeating: 0, count: 0x200)
            withUnsafeBytes(of: UInt32(slot).littleEndian) { b.replaceSubrange(0..<4, with: $0) }
            let bytes = Array(trimmedName(name).utf8)
            b.replaceSubrange(0x1C0..<(0x1C0 + bytes.count), with: bytes)
            var out = [UInt8](repeating: 0, count: 0x200)
            var size = out.count
            return IOConnectCallStructMethod(c, 17, &b, b.count, &out, &size) == KERN_SUCCESS
        } ?? false
    }

    /// Keeps whole characters within the 63 bytes the driver stores.
    static func trimmedName(_ name: String) -> String {
        var s = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.utf8.count > maxNameBytes { s.removeLast() }
        return s
    }

    // MARK: Clock source (through Core Audio, like Audio MIDI Setup)

    /// Core Audio clock source items published by the driver. Item n selects DICE source n (8 selects the
    /// internal clock, DICE 0x0C). The names the driver publishes do not match the sources: the real ADAT
    /// input is item 5 ("Unused") and the real word clock input is item 7 (the first "Internal"); items 1
    /// and 2 ("ADAT", "Word Clock") are DICE AES receivers the FireStudio does not have. See
    /// docs/driver-settings.md.
    /// Clock choices offered in the app. ADAT 1 and ADAT 2 are both item 5; the optical port is chosen in the
    /// mixer register 0x111C (FireControl's clock map: Internal 12, BNC 7, S/PDIF 0, ADAT 1 and ADAT 2 = 5).
    enum ClockChoice: Hashable {
        case item(UInt32)
        case adat(port: UInt32)
    }
    static let clockChoices: [(choice: ClockChoice, name: String)] = [
        (.item(8), L("Internal")), (.item(0), "S/PDIF"), (.adat(port: 0), "ADAT 1"), (.adat(port: 1), "ADAT 2"),
        (.item(7), "Word Clock")]

    private static func device() -> AudioDeviceID? {
        var uid = "PaeFireStudioAudioEngine:0" as CFString
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let st = withUnsafeMutablePointer(to: &uid) { p in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr,
                                       UInt32(MemoryLayout<CFString>.size), p, &size, &dev)
        }
        return st == noErr && dev != 0 ? dev : nil
    }

    private static let clockAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyClockSource,
                                                              mScope: kAudioObjectPropertyScopeGlobal,
                                                              mElement: kAudioObjectPropertyElementMain)

    static func clockSource() -> UInt32? {
        guard let dev = device() else { return nil }
        var addr = clockAddr
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr ? v : nil
    }

    @discardableResult
    static func setClockSource(_ item: UInt32) -> Bool {
        guard let dev = device() else { return false }
        var addr = clockAddr
        var v = item
        return AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v) == noErr
    }

    // MARK: Sample rate (through Core Audio, like Audio MIDI Setup)

    /// Rates the driver publishes for the FireStudio (all its stream formats).
    static let sampleRates: [Double] = [44100, 48000, 88200, 96000]

    private static let rateAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                                             mScope: kAudioObjectPropertyScopeGlobal,
                                                             mElement: kAudioObjectPropertyElementMain)

    static func nominalRate() -> Double? {
        guard let dev = device() else { return nil }
        var addr = rateAddr
        var v: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        return AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr && v > 0 ? v : nil
    }

    /// The driver restarts streaming on every unit of the bus: the audio stops briefly.
    @discardableResult
    static func setNominalRate(_ rate: Double) -> Bool {
        guard let dev = device() else { return false }
        var addr = rateAddr
        var v = Float64(rate)
        return AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<Float64>.size), &v) == noErr
    }

    /// IOAudioEngineState of the driver's engine: 0 stopped, 1 running, 2 paused, 3 resumed.
    /// The driver can stay paused when the unit in slot 0 disappears while another unit stays on
    /// (see docs/driver-settings.md); no audio then reaches any unit until the bus is rebuilt.
    static func engineState() -> Int? {
        let svc = IOServiceGetMatchingService(0, IOServiceMatching("PaeFireStudioAudioEngine"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        return IORegistryEntryCreateCFProperty(svc, "IOAudioEngineState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Int
    }

    /// Safety offsets the driver reports to Core Audio, in samples, and the stream sample rate.
    static func safetyOffsets() -> (output: Int, input: Int, rate: Int)? {
        let svc = IOServiceGetMatchingService(0, IOServiceMatching("PaeFireStudioAudioEngine"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        func prop(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(svc, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        guard let out = prop("IOAudioEngineSampleOffset") as? Int,
              let inp = prop("IOAudioEngineInputSampleOffset") as? Int else { return nil }
        let rate = (prop("IOAudioSampleRate") as? [String: Any])?["IOAudioSampleRateWholeNumber"] as? Int ?? 0
        return (out, inp, rate)
    }
}

struct BusDevice: Equatable {
    let guid: UInt64
    let name: String
    let slot: Int
    let state: Int
}

struct BusConfig: Equatable {
    let master: UInt64
    let devices: [BusDevice]
}

struct ErrorCounts: Equatable {
    var playback = 0, recording = 0, timing = 0
    var total: Int { playback + recording + timing }
}

/// View state for the driver section of the settings page.
final class DriverModel: ObservableObject {
    @Published private(set) var mode: Int?
    @Published private(set) var offsets: (output: Int, input: Int, rate: Int)?
    @Published private(set) var busy = false
    @Published private(set) var errors: ErrorCounts?
    @Published private(set) var clock: UInt32?
    @Published private(set) var rate: Double?
    private var timer: Timer?

    func refresh() {
        DispatchQueue.global(qos: .userInitiated).async {
            let m = DriverSettings.opMode()
            let o = DriverSettings.safetyOffsets()
            let e = DriverSettings.errorCounts()
            let c = DriverSettings.clockSource()
            let r = DriverSettings.nominalRate()
            DispatchQueue.main.async { self.mode = m; self.offsets = o; self.errors = e; self.clock = c; self.rate = r }
        }
    }

    /// Polls the counters, the clock source and the sample rate while the settings page is visible.
    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            DispatchQueue.global(qos: .utility).async {
                let e = DriverSettings.errorCounts()
                let c = DriverSettings.clockSource()
                let r = DriverSettings.nominalRate()
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if e != self.errors { self.errors = e }
                    if c != self.clock, !self.busy { self.clock = c }
                    if r != self.rate, !self.busy { self.rate = r }
                }
            }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func resetErrors() {
        DispatchQueue.global(qos: .userInitiated).async {
            DriverSettings.clearErrorCounts()
            let e = DriverSettings.errorCounts()
            DispatchQueue.main.async { self.errors = e }
        }
    }

    func setClock(_ item: UInt32) {
        guard item != clock, !busy else { return }
        busy = true
        clock = item
        DispatchQueue.global(qos: .userInitiated).async {
            DriverSettings.setClockSource(item)
            Thread.sleep(forTimeInterval: 1.5)
            let c = DriverSettings.clockSource()
            let o = DriverSettings.safetyOffsets()
            DispatchQueue.main.async { self.clock = c; self.offsets = o; self.busy = false }
        }
    }

    func setRate(_ newRate: Double) {
        guard newRate != rate, !busy else { return }
        busy = true
        rate = newRate
        DispatchQueue.global(qos: .userInitiated).async {
            DriverSettings.setNominalRate(newRate)
            Thread.sleep(forTimeInterval: 1.5)
            let r = DriverSettings.nominalRate()
            let o = DriverSettings.safetyOffsets()
            DispatchQueue.main.async { self.rate = r; self.offsets = o; self.busy = false }
        }
    }

    func set(_ newMode: Int) {
        guard newMode != mode, !busy else { return }
        busy = true
        mode = newMode
        DispatchQueue.global(qos: .userInitiated).async {
            DriverSettings.setOpMode(newMode)
            // The driver restarts streaming asynchronously; the new offsets appear shortly after.
            Thread.sleep(forTimeInterval: 1.5)
            let m = DriverSettings.opMode()
            let o = DriverSettings.safetyOffsets()
            DispatchQueue.main.async { self.mode = m; self.offsets = o; self.busy = false }
        }
    }
}
