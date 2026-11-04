import SwiftUI

// MARK: - Plage rappelée par un preset

extension Reg {
    /// Mixage + routage. Les réglages matériels (BNC, Expanded Mix Mode, talkback, surround, MSR) sont exclus.
    static func isRecallable(_ off: UInt32) -> Bool {
        guard writableRange.contains(off), off % 4 == 0 else { return false }
        if (0x1114...0x1128).contains(off) || off == dmmm { return false }
        return true
    }
}

extension MixerModel {
    /// Réécrit sur la carte les paramètres rappelables qui diffèrent. Renvoie le nombre de mots modifiés.
    func recall(_ saved: [UInt32]) -> Int {
        guard saved.count == Reg.quadlets else { return 0 }
        var n = 0
        var off = Reg.writableRange.lowerBound
        while off < Reg.writableRange.upperBound {
            if Reg.isRecallable(off), saved[Int(off / 4)] != reg(off) { set(off, saved[Int(off / 4)]); n += 1 }
            off += 4
        }
        return n
    }

    func matches(_ saved: [UInt32]) -> Bool {
        guard saved.count == Reg.quadlets else { return false }
        var off = Reg.writableRange.lowerBound
        while off < Reg.writableRange.upperBound {
            if Reg.isRecallable(off), saved[Int(off / 4)] != reg(off) { return false }
            off += 4
        }
        return true
    }
}

extension Backup {
    @discardableResult
    static func write(_ regs: [UInt32], to url: URL) -> Bool {
        let text = regs.enumerated().map { String(format: "%04x %08x", $0.offset * 4, $0.element) }.joined(separator: "\n")
        return (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil
    }
}

// MARK: - Stockage des 6 presets

final class PresetStore: ObservableObject {
    static let count = 6
    @Published private(set) var names: [String]
    @Published private(set) var data: [[UInt32]?]
    @Published var storeMode = false
    @Published var message = ""

    private var folder: URL {
        let url = Backup.folder.deletingLastPathComponent().appendingPathComponent("Presets", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func file(_ i: Int) -> URL { folder.appendingPathComponent("preset-\(i + 1).fsmix") }
    private var namesFile: URL { folder.appendingPathComponent("noms.json") }

    init() {
        names = Array(repeating: "", count: PresetStore.count)
        data = Array(repeating: nil, count: PresetStore.count)
        if let d = try? Data(contentsOf: namesFile), let n = try? JSONDecoder().decode([String].self, from: d), n.count == PresetStore.count {
            names = n
        }
        for i in 0..<PresetStore.count { data[i] = Backup.load(file(i)) }
    }

    func isEmpty(_ i: Int) -> Bool { data[i] == nil }
    func title(_ i: Int) -> String { names[i].isEmpty ? "Preset \(i + 1)" : names[i] }

    func store(_ i: Int, _ m: MixerModel) {
        guard m.connected else { return }
        if Backup.write(m.regs, to: file(i)) {
            data[i] = m.regs
            flash("« \(title(i)) » mémorisé")
        } else {
            flash("Échec de l'enregistrement")
        }
        storeMode = false
    }

    func recall(_ i: Int, _ m: MixerModel) {
        guard let saved = data[i] else { flash("Emplacement vide — « Mémoriser » puis clic pour l'enregistrer"); return }
        let n = m.recall(saved)
        flash(n == 0 ? "« \(title(i)) » est déjà actif" : "« \(title(i)) » rappelé (\(n) paramètres)")
    }

    func rename(_ i: Int, _ name: String) {
        names[i] = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let d = try? JSONEncoder().encode(names) { try? d.write(to: namesFile) }
    }

    func clear(_ i: Int) {
        try? FileManager.default.removeItem(at: file(i))
        data[i] = nil
        rename(i, "")
        flash("Emplacement \(i + 1) effacé")
    }

    private var flashWork: DispatchWorkItem?
    private func flash(_ s: String) {
        message = s
        flashWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.message = "" }
        flashWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: w)
    }
}

// MARK: - Barre de presets

struct PresetBar: View {
    @EnvironmentObject var m: MixerModel
    @EnvironmentObject var p: PresetStore
    @State private var renaming = false
    @State private var renameIndex = 0
    @State private var renameText = ""

    var body: some View {
        HStack(spacing: 6) {
            SectionHeader(title: "Presets", color: Theme.input)
                .padding(.trailing, 4)
            ForEach(0..<PresetStore.count, id: \.self) { i in slot(i) }
            Button { p.storeMode.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 10, weight: .bold))
                    Text(p.storeMode ? "CHOISIR UN EMPLACEMENT…" : "MÉMORISER").font(.system(size: 9.5, weight: .bold)).kerning(0.6)
                }
                .foregroundColor(p.storeMode ? .black.opacity(0.85) : Theme.mute)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(p.storeMode ? Theme.mute : Color.clear))
                .overlay(Capsule().stroke(Theme.mute.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .help(p.storeMode ? "Annuler" : "Puis clique sur un emplacement pour y enregistrer l'état actuel")
            Text(p.message).font(.system(size: 10.5)).foregroundColor(Theme.dim).lineLimit(1)
            Spacer()
        }
        .sheet(isPresented: $renaming) { renameSheet }
    }

    private func slot(_ i: Int) -> some View {
        let empty = p.isEmpty(i)
        let active = !empty && m.connected && m.matches(p.data[i]!)
        return Button {
            if p.storeMode { p.store(i, m) } else { p.recall(i, m) }
        } label: {
            HStack(spacing: 5) {
                Text("\(i + 1)").font(.system(size: 9, weight: .heavy).monospacedDigit())
                    .foregroundColor(active ? .black.opacity(0.6) : Theme.dim)
                Text(empty ? "vide" : p.title(i))
                    .font(.system(size: 11, weight: active ? .bold : .medium))
                    .lineLimit(1)
            }
            .foregroundColor(active ? .black.opacity(0.85) : (empty ? Theme.dim.opacity(0.7) : Theme.text))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .frame(minWidth: 74)
            .background(
                Capsule().fill(active ? Theme.input : Color.white.opacity(empty ? 0.02 : 0.07))
                    .shadow(color: active ? Theme.input.opacity(0.6) : .clear, radius: 4)
            )
            .overlay(Capsule().stroke(p.storeMode ? Theme.mute.opacity(0.9) : Color.white.opacity(empty ? 0.10 : 0.0),
                                      style: StrokeStyle(lineWidth: 1, dash: empty && !p.storeMode ? [3, 2] : [])))
        }
        .buttonStyle(.plain)
        .help(empty ? "Emplacement vide" : (p.storeMode ? "Remplacer par l'état actuel" : "Rappeler « \(p.title(i)) »"))
        .contextMenu {
            Button("Mémoriser l'état actuel ici") { p.store(i, m) }
            Button("Renommer…") { renameIndex = i; renameText = p.names[i]; renaming = true }.disabled(empty)
            Divider()
            Button("Effacer") { p.clear(i) }.disabled(empty)
        }
    }

    private var renameSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nom du preset \(renameIndex + 1)").font(.headline)
            TextField("Preset \(renameIndex + 1)", text: $renameText)
                .textFieldStyle(.roundedBorder).frame(width: 260)
                .onSubmit { p.rename(renameIndex, renameText); renaming = false }
            HStack {
                Spacer()
                Button("Annuler") { renaming = false }.keyboardShortcut(.cancelAction)
                Button("OK") { p.rename(renameIndex, renameText); renaming = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
    }
}
