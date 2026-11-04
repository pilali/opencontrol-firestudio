import Foundation
import Combine

/// Image locale de la zone mixeur + communication avec l'appareil.
final class MixerModel: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var status = "Recherche de la FireStudio…"
    /// Pas @Published : on notifie à la main, et pas pendant un glisser (sinon toute la fenêtre est redessinée).
    private(set) var regs = [UInt32](repeating: 0, count: Reg.quadlets)
    let meterStore = MeterStore.shared
    private var meterBusy = false
    @Published private(set) var sampleRate: Int = 0
    @Published private(set) var lastBackup: URL?
    @Published var selectedMix = 0

    private let io = DispatchQueue(label: "firestudio.io")
    private var pending: [UInt32: UInt32] = [:]     // écritures en attente (dernière valeur par adresse)
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

    // MARK: Connexion

    func connect() {
        io.async {
            let o = fs_open()
            guard o == 0 else {
                let msg = o == -4 ? "FireStudio occupée par un autre programme (accès exclusif)"
                                  : "FireStudio introuvable (vérifie le câble / l'adaptateur)"
                DispatchQueue.main.async { self.status = msg }
                return
            }
            var buf = [UInt32](repeating: 0, count: Reg.quadlets)
            let r = fs_read(0, &buf, UInt32(Reg.quadlets))
            var rate: UInt32 = 0
            _ = fs_read_abs(0xE0000000 + 0x28 + 0x5C, &rate)    // DICE global : sample rate
            DispatchQueue.main.async {
                if r != 0 { self.status = "Erreur de lecture (\(r))"; fs_close(); return }
                self.objectWillChange.send()
                self.regs = buf
                self.sampleRate = Int(rate)
                self.connected = true
                self.status = "Connectée"
                self.lastBackup = Backup.save(buf)
            }
        }
    }

    func reloadFromDevice() {
        io.async {
            var buf = [UInt32](repeating: 0, count: Reg.quadlets)
            let r = fs_read(0, &buf, UInt32(Reg.quadlets))
            DispatchQueue.main.async { if r == 0 { self.objectWillChange.send(); self.regs = buf } else { self.lost(r) } }
        }
    }

    private func lost(_ code: Int32) {
        connected = false
        status = "Connexion perdue (\(code)) — nouvelle tentative…"
        io.async { fs_close() }
    }

    private func pollMeters() {
        guard connected, !meterBusy else { return }   // pas d'empilement si le bus est lent
        meterBusy = true
        io.async {
            var q = [UInt32](repeating: 0, count: Int(Reg.meterQuadlets))
            let r = fs_read(Reg.metersBase, &q, Reg.meterQuadlets)
            guard r == 0 else { DispatchQueue.main.async { self.meterBusy = false; self.lost(r) }; return }
            var bytes = [UInt8](repeating: 0, count: 60)
            for i in 0..<60 { bytes[i] = UInt8((q[i / 4] >> (8 * UInt32(i % 4))) & 0xFF) }
            DispatchQueue.main.async { self.meterBusy = false; self.meterStore.update(bytes) }
        }
    }

    // MARK: Accès registres

    func reg(_ off: UInt32) -> UInt32 { regs[Int(off / 4)] }

    /// `publish: false` pendant un glisser : la carte reçoit la valeur, l'interface n'est pas redessinée.
    func set(_ off: UInt32, _ value: UInt32, publish: Bool = true) {
        guard Reg.writableRange.contains(off), off % 4 == 0 else { return }
        if publish { objectWillChange.send() }
        guard regs[Int(off / 4)] != value else { return }
        regs[Int(off / 4)] = value
        io.async {
            self.pending[off] = value
            guard !self.flushScheduled else { return }
            self.flushScheduled = true
            self.io.asyncAfter(deadline: .now() + 0.04) { self.flush() }
        }
    }

    private func flush() {                         // sur la file io
        flushScheduled = false
        let batch = pending; pending.removeAll()
        for (off, v) in batch.sorted(by: { $0.key < $1.key }) {
            let r = fs_write(off, v)
            if r != 0 { DispatchQueue.main.async { self.lost(r) }; return }
        }
    }

    // MARK: Noms

    func name(_ index: Int) -> String {
        let base = Int(Reg.namesBase / 4) + index * 3
        guard base + 2 < regs.count else { return "?" }
        var bytes: [UInt8] = []
        for q in regs[base..<base + 3] { for k in 0..<4 { bytes.append(UInt8((q >> (8 * UInt32(k))) & 0xFF)) } }
        let s = bytes.prefix { $0 != 0 }
        return String(decoding: s, as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }
    func inputName(_ ch: Int) -> String { name(ch) }
    func playbackName(_ ch: Int) -> String { name(18 + ch) }
    func mixName(_ m: Int) -> String { name(36 + m).isEmpty ? "Mix \(m + 1)" : name(36 + m) }

    // MARK: Tranches

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
        if on {   // aligne le canal droit sur le gauche
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
            // Le firmware d'origine écrit soit 1 (mute) soit 2 (solo) : on garde un seul état à la fois.
            set(off, on ? f : 0)
        }
    }

    /// Désactive tous les solos du mix courant (bouton « Solo Off » de FireControl).
    func clearSolos(mix: Int) {
        for ch in 0..<18 {
            for kind in [Kind.input, .playback] where flag(kind, ch, mix: mix, Reg.flagSolo) {
                set(stripBase(kind, ch, mix: mix) + Reg.flags, 0)
            }
        }
    }

    // MARK: Routage

    func outputSource(_ out: Int) -> Int { Int(reg(Reg.outputSource(out))) }
    func setOutputSource(_ out: Int, _ src: Int) { set(Reg.outputSource(out), UInt32(src)) }

    /// Affecte une source stéréo à une paire de sorties (comme FireControl : L sur la sortie paire, R sur l'impaire).
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
    /// nil = pas de remplacement, sinon numéro de mix (0-8).
    func monitorOverride(_ idx: Int) -> Int? {
        let v = reg(Reg.monitorOverride(idx))
        return (v == 0 || v == 0xFF) ? nil : Int(v) - 1
    }
    func setMonitorOverride(_ idx: Int, _ mix: Int?) { set(Reg.monitorOverride(idx), mix.map { UInt32($0 + 1) } ?? 0) }

    // MARK: Réglages

    func bool(_ off: UInt32) -> Bool { reg(off) != 0 }
    func setBool(_ off: UInt32, _ on: Bool) { set(off, on ? 1 : 0) }

    // MARK: Sauvegardes

    /// Réécrit les paramètres d'une sauvegarde (uniquement les mots qui diffèrent).
    func restore(from url: URL) -> String {
        guard let saved = Backup.load(url) else { return "Fichier illisible" }
        var n = 0
        var off = Reg.writableRange.lowerBound
        while off < Reg.writableRange.upperBound {
            let v = saved[Int(off / 4)]
            if v != reg(off) { set(off, v); n += 1 }
            off += 4
        }
        return "\(n) paramètres restaurés"
    }
}

/// Vu-mètres : hors de SwiftUI. Chaque MeterNSView s'abonne et ne se redessine que si ses LED changent.
final class MeterStore {
    static let shared = MeterStore()
    static let leds = 28
    private(set) var levels = [Int](repeating: 0, count: 60)   // nombre de LED allumées
    private(set) var peaks = [Int](repeating: 0, count: 60)
    private var holdUntil = [Date](repeating: .distantPast, count: 60)
    private let views = NSHashTable<MeterNSView>.weakObjects()

    func register(_ v: MeterNSView) { views.add(v) }

    /// Octets bruts (≈ 0x20 au repos, ≈ 0xA8 avec une guitare sur IN1).
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
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("FireStudioMixer/Sauvegardes", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func save(_ regs: [UInt32], name: String? = nil) -> URL? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let url = folder.appendingPathComponent((name ?? "auto_" + f.string(from: Date())) + ".fsmix")
        let text = regs.enumerated().map { String(format: "%04x %08x", $0.offset * 4, $0.element) }.joined(separator: "\n")
        do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { return nil }
        prune()
        return url
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

    /// Ne garde que les 30 sauvegardes automatiques les plus récentes.
    private static func prune() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        let autos = files.filter { $0.lastPathComponent.hasPrefix("auto_") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for f in autos.dropFirst(30) { try? fm.removeItem(at: f) }
    }
}
