import Foundation
import IOKit

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

/// View state for the driver section of the settings page.
final class DriverModel: ObservableObject {
    @Published private(set) var mode: Int?
    @Published private(set) var offsets: (output: Int, input: Int, rate: Int)?
    @Published private(set) var busy = false

    func refresh() {
        DispatchQueue.global(qos: .userInitiated).async {
            let m = DriverSettings.opMode()
            let o = DriverSettings.safetyOffsets()
            DispatchQueue.main.async { self.mode = m; self.offsets = o }
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
