import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Tranche

struct StripView: View {
    @EnvironmentObject var m: MixerModel
    var kind: MixerModel.Kind
    var ch: Int
    var mix: Int
    var title: String
    var meterIndex: Int?
    var showPan = true
    var showSolo = true

    var body: some View {
        let accent = Theme.accent(kind)
        VStack(spacing: 7) {
            if showPan {
                PanControl(value: m.pan(kind, ch, mix: mix), accent: accent) { m.setPan(kind, ch, mix: mix, $0, live: $1) }
            } else {
                Color.clear.frame(height: 14)
            }
            HStack(spacing: 4) {
                GlowButton(label: "M", on: m.flag(kind, ch, mix: mix, Reg.flagMute), color: Theme.mute) {
                    m.toggleFlag(kind, ch, mix: mix, Reg.flagMute)
                }
                if showSolo {
                    GlowButton(label: "S", on: m.flag(kind, ch, mix: mix, Reg.flagSolo), color: Theme.solo) {
                        m.toggleFlag(kind, ch, mix: mix, Reg.flagSolo)
                    }
                }
            }
            HStack(alignment: .top, spacing: 3) {
                Fader(value: m.level(kind, ch, mix: mix), accent: accent) { m.setLevel(kind, ch, mix: mix, $0, live: $1) }
                MeterBar(index: meterIndex).frame(width: 9, height: 187)
            }
            Text(Fader.dB(m.level(kind, ch, mix: mix)) + (m.level(kind, ch, mix: mix) < 1 ? "" : " dB"))
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundColor(Theme.text.opacity(0.7))
                .frame(height: 12)
            // bandeau de nom
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(Theme.text)
                .lineLimit(2).multilineTextAlignment(.center)
                .frame(width: 62, height: 26)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.35)))
                .overlay(Rectangle().fill(accent).frame(height: 2).cornerRadius(1), alignment: .top)
        }
        .padding(.vertical, 8).padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [Theme.stripTop, Theme.stripBottom], startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline))
    }
}

struct LinkButton: View {
    @EnvironmentObject var m: MixerModel
    var kind: MixerModel.Kind
    var pair: Int
    var mix: Int
    var body: some View {
        let on = m.isLinked(kind, pair: pair, mix: mix)
        Button { m.setLinked(kind, pair: pair, mix: mix, !on) } label: {
            HStack(spacing: 3) {
                Image(systemName: "link").font(.system(size: 9, weight: .bold))
                Text("LINK").font(.system(size: 8.5, weight: .bold)).kerning(0.8)
            }
            .foregroundColor(on ? .black.opacity(0.8) : Theme.dim)
            .frame(maxWidth: .infinity, minHeight: 16)
            .background(RoundedRectangle(cornerRadius: 3).fill(on ? Theme.accent(kind) : Color.white.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .help("Liaison stéréo des canaux \(pair * 2 + 1)/\(pair * 2 + 2)")
    }
}

/// Groupe de 2 tranches liables.
struct PairView: View {
    @EnvironmentObject var m: MixerModel
    var kind: MixerModel.Kind
    var pair: Int
    var mix: Int
    var name: (Int) -> String
    var meter: (Int) -> Int?

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                ForEach(0..<2) { i in
                    let ch = pair * 2 + i
                    StripView(kind: kind, ch: ch, mix: mix, title: name(ch), meterIndex: meter(ch))
                }
            }
            LinkButton(kind: kind, pair: pair, mix: mix)
        }
    }
}

// MARK: - Pages

struct MixTabs: View {
    @EnvironmentObject var m: MixerModel
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<Reg.mixCount, id: \.self) { i in
                let sel = m.selectedMix == i
                Button { m.selectedMix = i } label: {
                    Text(m.mixName(i))
                        .font(.system(size: 11, weight: sel ? .bold : .medium))
                        .foregroundColor(sel ? .black.opacity(0.85) : Theme.text.opacity(0.8))
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(Capsule().fill(sel ? Theme.master : Color.white.opacity(0.06)))
                }.buttonStyle(.plain)
            }
        }
    }
}

struct MixerPage: View {
    @EnvironmentObject var m: MixerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                MixTabs()
                Spacer()
                Button { m.clearSolos(mix: m.selectedMix) } label: {
                    Text("SOLO OFF").font(.system(size: 10, weight: .bold)).kerning(0.8)
                        .foregroundColor(Theme.solo)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .overlay(Capsule().stroke(Theme.solo.opacity(0.6)))
                }.buttonStyle(.plain)
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    section("Entrées", Theme.input) {
                        ForEach(0..<9) { p in
                            PairView(kind: .input, pair: p, mix: m.selectedMix, name: m.inputName, meter: Reg.inputMeter)
                        }
                    }
                    section(m.bool(Reg.a2md) ? "Retours DAW / ADAT 9-16" : "Retours DAW", Theme.playback) {
                        ForEach(0..<9) { p in
                            PairView(kind: .playback, pair: p, mix: m.selectedMix, name: m.playbackName, meter: Reg.playbackMeter)
                        }
                    }
                    section("Master", Theme.master) {
                        StripView(kind: .output, ch: 18 + m.selectedMix, mix: 0, title: m.mixName(m.selectedMix),
                                  meterIndex: Reg.mixMeter(m.selectedMix, right: false), showPan: false, showSolo: false)
                    }
                }.padding(.bottom, 10)
            }
            Text("Glisser : fader · ⌥ glisser : réglage fin · molette : ±0,375 dB (⇧ ×8) · double-clic : 0 dB / centre")
                .font(.system(size: 10)).foregroundColor(Theme.dim)
        }
    }

    func section<C: View>(_ title: String, _ color: Color, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: title, color: color)
            HStack(alignment: .top, spacing: 8) { content() }
        }
    }
}

struct RoutingPage: View {
    @EnvironmentObject var m: MixerModel
    static let pairNames = ["Out 1/2", "Out 3/4", "Out 5/6", "Out 7/8", "Out 9/10", "Out 11/12",
                            "Out 13/14", "Out 15/16", "S/PDIF (17/18)"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("Sorties physiques") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(0..<9) { OutputRow(pair: $0) }
                    }.padding(6)
                }
                GroupBox("Main et casques") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(0..<4) { MonitorRow(idx: $0) }
                        Text("Main et les casques recopient une paire de sorties. Pour écouter un mix au casque, envoie-le sur cette paire ci-dessus.")
                            .font(.caption).foregroundColor(.secondary)
                    }.padding(6)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SourceOption: Hashable { let value: Int; let label: String }

struct OutputRow: View {
    @EnvironmentObject var m: MixerModel
    var pair: Int

    /// Sources stéréo proposées (valeur = canal gauche).
    private var sources: [SourceOption] {
        var s: [SourceOption] = []
        for mix in 0..<Reg.mixCount { s.append(SourceOption(value: 36 + mix * 2, label: m.mixName(mix))) }
        for p in 0..<9 { s.append(SourceOption(value: p * 2, label: "Entrée " + m.inputName(p * 2) + " / " + m.inputName(p * 2 + 1))) }
        for p in 0..<9 { s.append(SourceOption(value: 18 + p * 2, label: m.playbackName(p * 2) + " / " + m.playbackName(p * 2 + 1))) }
        let cur = m.outputSource(pair * 2)
        if !s.contains(where: { $0.value == cur }) { s.append(SourceOption(value: cur, label: "Autre : " + m.sourceName(cur))) }
        return s
    }

    var body: some View {
        let left = m.outputSource(pair * 2), right = m.outputSource(pair * 2 + 1)
        let binding = Binding<Int>(get: { left }, set: { m.setPairSource(pair: pair, left: $0) })
        return HStack(spacing: 10) {
            Text(RoutingPage.pairNames[pair]).frame(width: 110, alignment: .leading)
            Picker("", selection: binding) {
                ForEach(sources, id: \.self) { o in Text(o.label).tag(o.value) }
            }.frame(width: 320)
            HStack(spacing: 2) {
                MeterBar(index: Reg.sourceMeter(left)).frame(width: 9)
                MeterBar(index: Reg.sourceMeter(right)).frame(width: 9)
            }.frame(height: 18)
            Text(m.sourceName(left) + " · " + m.sourceName(right)).font(.caption).foregroundColor(.secondary)
        }
    }
}

struct MonitorRow: View {
    @EnvironmentObject var m: MixerModel
    var idx: Int

    var body: some View {
        let pairB = Binding<Int>(get: { m.monitorPair(idx) }, set: { m.setMonitorPair(idx, $0) })
        return HStack(spacing: 10) {
            Text(idx == 0 ? "Main" : "Phones \(idx)").frame(width: 110, alignment: .leading)
            Picker("Copie de", selection: pairB) {
                ForEach(0..<9) { Text(RoutingPage.pairNames[$0]).tag($0) }
            }.frame(width: 230)
        }
    }
}

struct SettingsPage: View {
    @EnvironmentObject var m: MixerModel
    @State private var message = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("Réglages FireStudio") {
                    VStack(alignment: .leading, spacing: 8) {
                        toggle("Terminate BNC (terminaison word clock 75 Ω)", Reg.bnct)
                        toggle("Expanded Mix Mode (ADAT 2) — les retours DAW 11-18 deviennent ADAT 9-16", Reg.a2md)
                        toggle("Talkback to Digital Outs", Reg.tbdo)
                        toggle("Copy 1/2 to main L/R in surround mode", Reg.dcmt)
                        toggle("Mains actifs en mode surround (décoché = mains coupés)", Reg.mtss)
                        Text("Fréquence d'échantillonnage : \(m.sampleRate) Hz (à régler dans Configuration audio et MIDI)")
                            .font(.caption).foregroundColor(.secondary)
                    }.padding(6)
                }
                GroupBox("Sauvegardes") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Une copie complète de l'état de la carte est enregistrée à chaque connexion.")
                            .font(.caption).foregroundColor(.secondary)
                        if let b = m.lastBackup { Text("Dernière : " + b.lastPathComponent).font(.caption.monospaced()) }
                        HStack {
                            Button("Enregistrer l'état actuel…") { saveAs() }
                            Button("Restaurer une sauvegarde…") { restore() }
                            Button("Ouvrir le dossier") { NSWorkspace.shared.open(Backup.folder) }
                            Button("Relire la carte") { m.reloadFromDevice() }
                        }
                        if !message.isEmpty { Text(message).font(.caption) }
                    }.padding(6)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func toggle(_ title: String, _ off: UInt32) -> some View {
        Toggle(title, isOn: Binding(get: { m.bool(off) }, set: { m.setBool(off, $0) }))
    }

    func saveAs() {
        let p = NSSavePanel()
        p.directoryURL = Backup.folder
        p.nameFieldStringValue = "Preset.fsmix"
        guard p.runModal() == .OK, let url = p.url else { return }
        if let tmp = Backup.save(m.regs, name: "tmp_export") {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.moveItem(at: tmp, to: url)
            message = "Enregistré : " + url.lastPathComponent
        }
    }

    func restore() {
        let p = NSOpenPanel()
        p.directoryURL = Backup.folder
        p.allowedContentTypes = [UTType(filenameExtension: "fsmix") ?? .data]
        guard p.runModal() == .OK, let url = p.url else { return }
        message = m.restore(from: url)
    }
}

struct ContentView: View {
    @EnvironmentObject var m: MixerModel
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Circle().fill(m.connected ? Theme.playback : Theme.master).frame(width: 8, height: 8)
                    .shadow(color: (m.connected ? Theme.playback : Theme.master).opacity(0.8), radius: 3)
                Text("FIRESTUDIO").font(.system(size: 12, weight: .heavy)).kerning(2).foregroundColor(Theme.text)
                Text(m.connected ? "26x26 · \(m.sampleRate / 1000) kHz" : m.status)
                    .font(.system(size: 11)).foregroundColor(Theme.dim)
                Spacer()
                Picker("", selection: $tab) {
                    Text("Mixer").tag(0); Text("Sorties / routage").tag(1); Text("Réglages").tag(2)
                }.pickerStyle(.segmented).frame(width: 380)
            }
            .padding(10)
            if m.connected {
                PresetBar().padding(.horizontal, 12).padding(.bottom, 8)
            }
            Divider()
            Group {
                if !m.connected {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(m.status).foregroundColor(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if tab == 0 { MixerPage() } else if tab == 1 { RoutingPage() } else { SettingsPage() }
            }
            .padding(12)
        }
        .frame(minWidth: 900, minHeight: 560, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.window)
        .preferredColorScheme(.dark)
        .onAppear { ScrollRouter.shared.install() }
    }
}

@main
struct FireStudioMixerApp: App {
    @StateObject private var model = MixerModel()
    @StateObject private var presets = PresetStore()
    var body: some Scene {
        WindowGroup("FireStudio Mixer") {
            ContentView().environmentObject(model).environmentObject(presets)
        }
    }
}
