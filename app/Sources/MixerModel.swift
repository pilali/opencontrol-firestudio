import Foundation
import Combine

/// One FireStudio on the bus, as seen by the app.
struct UnitInfo: Identifiable, Equatable {
    let guid: UInt64
    /// Nickname in the PreSonus driver, and the driver slot it is renamed through.
    var name: String?
    var slot: Int?
    /// DICE CLOCK_SELECT source (0x0C internal, 0x08 FireWire stream from the master, 0x00 S/PDIF, 0x05 ADAT, 0x07 word clock).
    var clockSelect: UInt32?
    /// Optical port the unit syncs to when its clock source is ADAT (mixer register 0x111C): 0 = ADAT 1, 1 = ADAT 2.
    var adatPort: UInt32?
    var locked: Bool?
    var id: UInt64 { guid }
}

/// Local image of the mixer area + communication with the device.
final class MixerModel: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var status = L("Searching for the FireStudio…")
    /// Not @Published: changes are announced by hand, and not during a drag (otherwise the whole window redraws).
    private(set) var regs = [UInt32](repeating: 0, count: Reg.quadlets)
    let meterStore = MeterStore.shared
    private var meterBusy = false
    @Published private(set) var sampleRate: Int = 0
    /// GUID of the open unit, and GUIDs of all the FireStudio 26x26 units seen on the bus.
    @Published private(set) var guid: UInt64?
    @Published private(set) var units: [UInt64] = []
    /// Open unit; only touched on the `io` queue.
    private var unit: OpaquePointer?
    /// The other units, kept open to read their clock status; only touched on the `io` queue.
    private var others: [UInt64: OpaquePointer] = [:]
    /// Every unit on the bus, with its driver nickname and clock status (refreshed about once per second).
    @Published private(set) var unitInfo: [UnitInfo] = []
    /// GUID of the unit the driver uses as clock master.
    @Published private(set) var clockMaster: UInt64?
    /// The driver's audio engine has stayed paused for several seconds (driver bug, see DriverSettings.engineState).
    @Published private(set) var engineStuck = false
    private var pausedPolls = 0
    private static let unitKey = "unitGUID"
    /// DICE global STATUS bit 0: the interface is locked to the selected clock source.
    @Published private(set) var clockLocked: Bool?
    private var statusTick = 0
    @Published private(set) var lastBackup: URL?
    @Published var selectedMix = 0

    private let io = DispatchQueue(label: "firestudio.io")
    private var pending: [UInt32: UInt32] = [:]     // pending writes (latest value per address)
    private var flushScheduled = false
    private var meterTimer: Timer?
    private var reconnectTimer: Timer?

    init() {
        connect()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self = self, !self.connected else { return }
            self.connect()
        }
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12, repeats: true) { [weak self] _ in
            self?.pollMeters()
        }
    }

    // MARK: Connection

    func connect() {
        io.async {
            let found = MixerModel.listUnits()
            let preferred = UInt64(UserDefaults.standard.string(forKey: MixerModel.unitKey) ?? "", radix: 16) ?? 0
            let target = found.contains(preferred) ? preferred : (found.first ?? 0)
            var err: Int32 = 0
            // A unit already open for its clock status is reused.
            guard let u = self.others.removeValue(forKey: target) ?? fs_open(target, &err) else {
                let msg = err == -4 ? L("FireStudio in use by another program (exclusive access)")
                                    : L("FireStudio not found (check the cable or adapter)")
                DispatchQueue.main.async { self.status = msg; self.units = found }
                return
            }
            var buf = [UInt32](repeating: 0, count: Reg.quadlets)
            let r = fs_read(u, 0, &buf, UInt32(Reg.quadlets))
            var rate: UInt32 = 0
            _ = fs_read_abs(u, Reg.diceGlobal + 0x5C, &rate)    // DICE global section: sample rate
            if r != 0 { fs_close(u) } else { self.unit = u }
            let g = fs_guid(u)
            DispatchQueue.main.async {
                if r != 0 { self.status = L("Read error (%d)", Int(r)); return }
                self.objectWillChange.send()
                self.regs = buf
                self.sampleRate = Int(rate)
                self.units = found
                Backup.unit = g
                self.guid = g
                self.connected = true
                self.status = L("Connected")
                self.lastBackup = Backup.save(buf)
                self.pollUnits()
            }
        }
    }

    /// GUIDs of the FireStudio units on the bus (fs_list must fill the buffer before it is read).
    private static func listUnits() -> [UInt64] {
        var list = [UInt64](repeating: 0, count: 8)
        let n = Int(min(fs_list(&list, 8), 8))
        return Array(list.prefix(n))
    }

    /// Switches to another unit (remembered for the next launches).
    func select(unit g: UInt64) {
        guard g != guid else { return }
        UserDefaults.standard.set(String(g, radix: 16), forKey: MixerModel.unitKey)
        connected = false
        status = L("Searching for the FireStudio…")
        io.async {
            if let u = self.unit { self.others[fs_guid(u)] = u }
            self.unit = nil
        }
        connect()
    }

    func reloadFromDevice() {
        io.async {
            var buf = [UInt32](repeating: 0, count: Reg.quadlets)
            let r = fs_read(self.unit, 0, &buf, UInt32(Reg.quadlets))
            DispatchQueue.main.async { if r == 0 { self.objectWillChange.send(); self.regs = buf } else { self.lost(r) } }
        }
    }

    private func lost(_ code: Int32) {
        connected = false
        status = L("Connection lost (%d) — retrying…", Int(code))
        io.async { fs_close(self.unit); self.unit = nil }
    }

    private func pollMeters() {
        guard connected, !meterBusy else { return }   // never pile up requests if the bus is slow
        meterBusy = true
        statusTick += 1
        if statusTick >= 12 { statusTick = 0; pollUnits() }
        io.async {
            var q = [UInt32](repeating: 0, count: Int(Reg.meterQuadlets))
            let r = fs_read(self.unit, Reg.metersBase, &q, Reg.meterQuadlets)
            guard r == 0 else { DispatchQueue.main.async { self.meterBusy = false; self.lost(r) }; return }
            var bytes = [UInt8](repeating: 0, count: 60)
            for i in 0..<60 { bytes[i] = UInt8((q[i / 4] >> (8 * UInt32(i % 4))) & 0xFF) }
            DispatchQueue.main.async { self.meterBusy = false; self.meterStore.update(bytes) }
        }
    }

    /// About once per second: lists the units, reads the DICE global CLOCK_SELECT, STATUS and SAMPLE_RATE
    /// registers of each one, and the nicknames and clock master known to the PreSonus driver.
    private func pollUnits() {
        io.async {
            let found = MixerModel.listUnits()
            for (g, h) in self.others where !found.contains(g) { fs_close(h); self.others[g] = nil }
            let current = self.unit.map { fs_guid($0) }
            var infos: [UnitInfo] = []
            var rate: UInt32 = 0
            for g in found {
                var info = UnitInfo(guid: g)
                var h = g == current ? self.unit : self.others[g]
                if h == nil {
                    var err: Int32 = 0
                    h = fs_open(g, &err)
                    if let h = h { self.others[g] = h }
                }
                if let h = h {
                    var sel: UInt32 = 0, st: UInt32 = 0
                    if fs_read_abs(h, Reg.diceGlobal + 0x4C, &sel) == 0, fs_read_abs(h, Reg.diceGlobal + 0x54, &st) == 0 {
                        info.clockSelect = sel & 0xFF
                        info.locked = st & 1 == 1
                        var port: UInt32 = 0
                        if fs_read(h, Reg.clks, &port, 1) == 0 { info.adatPort = port }
                        if g == current { _ = fs_read_abs(h, Reg.diceGlobal + 0x5C, &rate) }
                    } else if g != current {
                        fs_close(h); self.others[g] = nil
                    }
                }
                infos.append(info)
            }
            let cfg = DriverSettings.busConfig()
            let engine = DriverSettings.engineState()
            for i in infos.indices {
                if let d = cfg?.devices.first(where: { $0.guid == infos[i].guid }) {
                    infos[i].name = d.name; infos[i].slot = d.slot
                }
            }
            DispatchQueue.main.async {
                if self.units != found { self.units = found }
                if self.unitInfo != infos { self.unitInfo = infos }
                if self.clockMaster != cfg?.master { self.clockMaster = cfg?.master }
                self.pausedPolls = engine == 2 ? self.pausedPolls + 1 : 0
                let stuck = self.pausedPolls >= 5
                if self.engineStuck != stuck { self.engineStuck = stuck }
                let locked = infos.first { $0.guid == current }?.locked
                if self.clockLocked != locked { self.clockLocked = locked }
                if locked == true, rate > 0, self.sampleRate != Int(rate) { self.sampleRate = Int(rate) }
            }
        }
    }

    /// Name shown for a unit: its driver nickname, followed by the end of its GUID when several units share it.
    func unitName(_ g: UInt64?) -> String {
        func base(_ i: UnitInfo?) -> String {
            let n = i?.name ?? ""
            return n.isEmpty ? "FireStudio" : n
        }
        guard let g = g else { return "FireStudio" }
        let b = base(unitInfo.first { $0.guid == g })
        let shared = unitInfo.filter { base($0) == b }.count > 1
        return shared ? b + String(format: " ·%04llX", g & 0xFFFF) : b
    }

    /// Asks the driver to use this unit as clock master (the audio stream restarts).
    func makeClockMaster(_ g: UInt64) {
        DispatchQueue.global(qos: .userInitiated).async {
            DriverSettings.setMaster(g)
            DispatchQueue.main.async { self.pollUnits() }
        }
    }

    /// The clock master, or the open unit when the driver does not report one.
    var clockMasterInfo: UnitInfo? {
        unitInfo.first { $0.guid == (clockMaster ?? guid) }
    }

    /// Chooses the optical port the clock master syncs to when its clock source is ADAT, as FireControl did
    /// (mixer register 0x111C, stored by the firmware like the other mixer settings).
    func setADATClockPort(_ port: UInt32) {
        guard let g = clockMaster ?? guid else { return }
        if g == guid { set(Reg.clks, port); pollUnits(); return }
        io.async {
            if let h = self.others[g] { _ = fs_write(h, Reg.clks, port) }
            DispatchQueue.main.async { self.pollUnits() }
        }
    }

    func rename(_ g: UInt64, _ name: String) {
        guard let slot = unitInfo.first(where: { $0.guid == g })?.slot else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            DriverSettings.setNickname(slot: slot, name)
            DispatchQueue.main.async { self.pollUnits() }
        }
    }

    // MARK: Register access

    func reg(_ off: UInt32) -> UInt32 { regs[Int(off / 4)] }

    /// `publish: false` during a drag: the device gets the value, the UI is not redrawn.
    func set(_ off: UInt32, _ value: UInt32, publish: Bool = true) {
        guard Reg.writableRange.contains(off), off % 4 == 0 else { return }
        if publish { objectWillChange.send() }
        guard regs[Int(off / 4)] != value else { return }
        regs[Int(off / 4)] = value
        io.async {
            self.pending[off] = value
            guard !self.flushScheduled else { return }
            self.flushScheduled = true
            self.io.asyncAfter(deadline: .now() + 0.04) { self.flush() }   // at most ~25 writes/s
        }
    }

    private func flush() {                         // runs on the io queue
        flushScheduled = false
        let batch = pending; pending.removeAll()
        for (off, v) in batch.sorted(by: { $0.key < $1.key }) {
            let r = fs_write(self.unit, off, v)
            if r != 0 { DispatchQueue.main.async { self.lost(r) }; return }
        }
    }

    // MARK: Names

    func name(_ index: Int) -> String {
        let base = Int(Reg.namesBase / 4) + index * 3
        guard base + 2 < regs.count else { return "?" }
        var bytes: [UInt8] = []
        for q in regs[base..<base + 3] { for k in 0..<4 { bytes.append(UInt8((q >> (8 * UInt32(k))) & 0xFF)) } }
        let s = bytes.prefix { $0 != 0 }
        let text = String(decoding: s, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        // Units never set up by FireControl have empty (or erased, 0xFF) name fields.
        let valid = !s.isEmpty && s.allSatisfy { (0x20...0x7E).contains($0) } && !text.isEmpty
        return valid ? text : MixerModel.defaultName(index)
    }

    /// The names FireControl stores in the device, used when a field is empty.
    static func defaultName(_ index: Int) -> String {
        switch index {
        case 0, 1: return "Mic/Inst \(index + 1)"
        case 2..<8: return "Mic/Line \(index + 1)"
        case 8..<16: return "ADAT \(index - 7)"
        case 16: return "S/PDIF L"
        case 17: return "S/PDIF R"
        case 18..<28: return "Daw \(index - 17)"
        case 28..<36: return "ADAT \(index - 19)"
        case 36..<45: return "Mix \(index - 35)"
        case 45..<53: return "Daw \(index - 34)"
        default: return "?"
        }
    }
    func inputName(_ ch: Int) -> String { name(ch) }
    func playbackName(_ ch: Int) -> String { name(18 + ch) }
    func mixName(_ m: Int) -> String { name(36 + m).isEmpty ? L("Mix %d", m + 1) : name(36 + m) }

    // MARK: Strips

    enum Kind { case input, playback, output }

    func stripBase(_ kind: Kind, _ ch: Int, mix: Int) -> UInt32 {
        switch kind {
        case .input: return Reg.inputStrip(mix: mix, ch: ch)
        case .playback: return Reg.playbackStrip(mix: mix, ch: ch)
        case .output: return Reg.outputStrip(ch)
        }
    }

    func isLinked(_ kind: Kind, pair: Int, mix: Int) -> Bool {
        switch kind {
        case .input: return reg(Reg.linkMask(mix: mix)) & (1 << UInt32(pair)) != 0
        case .playback: return reg(Reg.linkMask(mix: mix)) & (1 << UInt32(16 + pair)) != 0
        case .output: return reg(Reg.outputLinkMask) & (1 << UInt32(pair)) != 0
        }
    }

    func setLinked(_ kind: Kind, pair: Int, mix: Int, _ on: Bool) {
        let off: UInt32, bit: UInt32
        switch kind {
        case .input: off = Reg.linkMask(mix: mix); bit = 1 << UInt32(pair)
        case .playback: off = Reg.linkMask(mix: mix); bit = 1 << UInt32(16 + pair)
        case .output: off = Reg.outputLinkMask; bit = 1 << UInt32(pair)
        }
        let v = reg(off)
        set(off, on ? v | bit : v & ~bit)
        if on {   // align the right channel on the left one
            let l = stripBase(kind, pair * 2, mix: mix), r = stripBase(kind, pair * 2 + 1, mix: mix)
            set(r + Reg.level, reg(l + Reg.level))
            set(r + Reg.flags, reg(l + Reg.flags))
        }
    }

    private func partner(_ kind: Kind, _ ch: Int, mix: Int) -> Int? {
        guard kind != .output || ch < 18 else { return nil }
        return isLinked(kind, pair: ch / 2, mix: mix) ? (ch ^ 1) : nil
    }

    func level(_ kind: Kind, _ ch: Int, mix: Int) -> Double { Double(reg(stripBase(kind, ch, mix: mix) + Reg.level)) }
    func setLevel(_ kind: Kind, _ ch: Int, mix: Int, _ v: Double, live: Bool = false) {
        let val = UInt32(max(0, min(255, v.rounded())))
        set(stripBase(kind, ch, mix: mix) + Reg.level, val, publish: !live)
        if let p = partner(kind, ch, mix: mix) { set(stripBase(kind, p, mix: mix) + Reg.level, val, publish: !live) }
    }

    func pan(_ kind: Kind, _ ch: Int, mix: Int) -> Double { Double(reg(stripBase(kind, ch, mix: mix) + Reg.pan)) }
    func setPan(_ kind: Kind, _ ch: Int, mix: Int, _ v: Double, live: Bool = false) {
        set(stripBase(kind, ch, mix: mix) + Reg.pan, UInt32(max(0, min(255, v.rounded()))), publish: !live)
    }

    func flag(_ kind: Kind, _ ch: Int, mix: Int, _ f: UInt32) -> Bool { reg(stripBase(kind, ch, mix: mix) + Reg.flags) & f != 0 }
    func toggleFlag(_ kind: Kind, _ ch: Int, mix: Int, _ f: UInt32) {
        let on = !flag(kind, ch, mix: mix, f)
        for c in [ch] + (partner(kind, ch, mix: mix).map { [$0] } ?? []) {
            let off = stripBase(kind, c, mix: mix) + Reg.flags
            // The original firmware writes either 1 (mute) or 2 (solo): keep a single state at a time.
            set(off, on ? f : 0)
        }
    }

    /// Clears every solo of the current mix (FireControl's "Solo Off" button).
    func clearSolos(mix: Int) {
        for ch in 0..<18 {
            for kind in [Kind.input, .playback] where flag(kind, ch, mix: mix, Reg.flagSolo) {
                set(stripBase(kind, ch, mix: mix) + Reg.flags, 0)
            }
        }
    }

    // MARK: Routing

    func outputSource(_ out: Int) -> Int { Int(reg(Reg.outputSource(out))) }
    func setOutputSource(_ out: Int, _ src: Int) { set(Reg.outputSource(out), UInt32(src)) }

    /// Assigns a stereo source to an output pair (as FireControl does: L on the even output, R on the odd one).
    func setPairSource(pair: Int, left: Int) {
        setOutputSource(pair * 2, left)
        setOutputSource(pair * 2 + 1, left + 1)
    }

    func sourceName(_ src: Int) -> String {
        switch src {
        case 0..<18: return inputName(src)
        case 18..<36: return playbackName(src - 18)
        case 36..<54: return mixName((src - 36) / 2) + ((src - 36) % 2 == 0 ? " L" : " R")
        default: return "—"
        }
    }

    // Main / Phones
    func monitorPair(_ idx: Int) -> Int { Int(reg(Reg.monitorSource(idx))) / 2 }
    func setMonitorPair(_ idx: Int, _ pair: Int) { set(Reg.monitorSource(idx), UInt32(pair * 2)) }
    /// nil = no override, otherwise mix number (0-8).
    func monitorOverride(_ idx: Int) -> Int? {
        let v = reg(Reg.monitorOverride(idx))
        return (v == 0 || v == 0xFF) ? nil : Int(v) - 1
    }
    func setMonitorOverride(_ idx: Int, _ mix: Int?) { set(Reg.monitorOverride(idx), mix.map { UInt32($0 + 1) } ?? 0) }

    // MARK: Settings

    func bool(_ off: UInt32) -> Bool { reg(off) != 0 }
    func setBool(_ off: UInt32, _ on: Bool) { set(off, on ? 1 : 0) }

    // MARK: Backups

    /// Writes back the parameters of a backup (only the words that differ).
    func restore(from url: URL) -> String {
        guard let saved = Backup.load(url) else { return L("Unreadable file") }
        var n = 0
        var off = Reg.writableRange.lowerBound
        while off < Reg.writableRange.upperBound {
            let v = saved[Int(off / 4)]
            if v != reg(off) { set(off, v); n += 1 }
            off += 4
        }
        return L("%d parameters restored", n)
    }
}

/// Meters live outside SwiftUI: each MeterNSView subscribes and redraws only when its LEDs change.
final class MeterStore {
    static let shared = MeterStore()
    static let leds = 28
    private(set) var levels = [Int](repeating: 0, count: 60)   // number of lit LEDs
    private(set) var peaks = [Int](repeating: 0, count: 60)
    private var holdUntil = [Date](repeating: .distantPast, count: 60)
    private let views = NSHashTable<MeterNSView>.weakObjects()

    func register(_ v: MeterNSView) { views.add(v) }

    /// Raw bytes (≈ 0x20 at rest, ≈ 0xA8 with a guitar played on IN1).
    func update(_ b: [UInt8]) {
        let now = Date()
        for i in 0..<min(60, b.count) {
            let v = Int(Double(b[i]) / 255 * Double(MeterStore.leds))
            levels[i] = v
            if v >= peaks[i] { peaks[i] = v; holdUntil[i] = now.addingTimeInterval(1.2) }
            else if now > holdUntil[i] { peaks[i] = max(v, peaks[i] - 1) }
        }
        for v in views.allObjects { v.refresh() }
    }
    func level(_ i: Int?) -> Int { i.map { $0 >= 0 && $0 < 60 ? levels[$0] : 0 } ?? 0 }
    func peak(_ i: Int?) -> Int { i.map { $0 >= 0 && $0 < 60 ? peaks[$0] : 0 } ?? 0 }
}

enum Backup {
    /// ~/Library/Application Support/OpenControl
    static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("OpenControl", isDirectory: true)
        // Versions up to 1.2 were named "FireStudio Mixer" and used this folder name.
        migrate(from: base.appendingPathComponent("FireStudioMixer", isDirectory: true), to: url)
        return url
    }

    /// GUID of the connected unit: backups and presets are stored per unit.
    static var unit: UInt64? {
        didSet { if let g = unit { adoptLegacyFolders(for: g) } }
    }

    /// ~/Library/Application Support/OpenControl/Units/<GUID>
    static func unitFolder(_ guid: UInt64) -> URL {
        appSupport.appendingPathComponent("Units", isDirectory: true)
            .appendingPathComponent(String(format: "%016llX", guid), isDirectory: true)
    }

    static var folder: URL {
        let base = unit.map(unitFolder) ?? appSupport
        let url = base.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Versions up to 1.1 kept one Backups and one Presets folder for the single unit they supported.
    /// They are moved, once, into the folder of the first unit that connects (never overwriting anything).
    private static func adoptLegacyFolders(for guid: UInt64) {
        let fm = FileManager.default
        let dest = unitFolder(guid)
        try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
        migrate(from: appSupport.appendingPathComponent("Sauvegardes", isDirectory: true),
                to: appSupport.appendingPathComponent("Backups", isDirectory: true))
        for name in ["Backups", "Presets"] {
            migrate(from: appSupport.appendingPathComponent(name, isDirectory: true),
                    to: dest.appendingPathComponent(name, isDirectory: true))
        }
    }

    /// Renames a folder created by the first (French-only) versions, without ever overwriting anything.
    static func migrate(from old: URL, to new: URL) {
        let fm = FileManager.default
        if fm.fileExists(atPath: old.path) && !fm.fileExists(atPath: new.path) {
            try? fm.moveItem(at: old, to: new)
        }
    }

    static func save(_ regs: [UInt32], name: String? = nil) -> URL? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HH-mm-ss"; f.locale = Locale(identifier: "en_US_POSIX")
        let url = folder.appendingPathComponent((name ?? "auto_" + f.string(from: Date())) + ".fsmix")
        guard write(regs, to: url) else { return nil }
        prune()
        return url
    }

    @discardableResult
    static func write(_ regs: [UInt32], to url: URL) -> Bool {
        let text = regs.enumerated().map { String(format: "%04x %08x", $0.offset * 4, $0.element) }.joined(separator: "\n")
        return (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil
    }

    static func load(_ url: URL) -> [UInt32]? {
        guard let text = try? String(contentsOf: url) else { return nil }
        var regs = [UInt32](repeating: 0, count: Reg.quadlets)
        var count = 0
        for line in text.split(separator: "\n") {
            let p = line.split(separator: " ")
            guard p.count == 2, let off = UInt32(p[0], radix: 16), let v = UInt32(p[1], radix: 16),
                  off % 4 == 0, Int(off / 4) < regs.count else { return nil }
            regs[Int(off / 4)] = v; count += 1
        }
        return count == Reg.quadlets ? regs : nil
    }

    /// Keeps only the 30 most recent automatic backups.
    private static func prune() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        let autos = files.filter { $0.lastPathComponent.hasPrefix("auto_") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for f in autos.dropFirst(30) { try? fm.removeItem(at: f) }
    }
}
