import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Channel strip

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
            Text(verbatim: Fader.dB(m.level(kind, ch, mix: mix)) + (m.level(kind, ch, mix: mix) < 1 ? "" : " dB"))
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundColor(Theme.text.opacity(0.7))
                .frame(height: 12)
            // scribble strip
            Text(verbatim: title)
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
                Text(verbatim: "LINK").font(.system(size: 8.5, weight: .bold)).kerning(0.8)
            }
            .foregroundColor(on ? .black.opacity(0.8) : Theme.dim)
            .frame(maxWidth: .infinity, minHeight: 16)
            .background(RoundedRectangle(cornerRadius: 3).fill(on ? Theme.accent(kind) : Color.white.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .help(L("Stereo link for channels %d/%d", pair * 2 + 1, pair * 2 + 2))
    }
}

/// Group of 2 linkable strips.
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
                    Text(verbatim: m.mixName(i))
                        .font(.system(size: 11, weight: sel ? .bold : .medium))
                        .foregroundColor(sel ? .black.opacity(0.85) : Theme.text.opacity(0.8))
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(Capsule().fill(sel ? Theme.master : Color.white.opacity(0.06)))
                }.buttonStyle(.plain)
            }
        }
    }
}

/// Enlarges the window once so that the two-row mixer fits without scrolling (within the screen).
/// Done once per layout version: afterwards the size the user chooses is kept.
enum WindowFitter {
    private static let key = "fittedLayout"
    private static let layout = 2
    private static var done = false

    static func fit(content: CGSize, viewport: CGSize, attempt: Int = 0) {
        guard !done, content.width > 0, viewport.width > 0,
              UserDefaults.standard.integer(forKey: key) < layout else { return }
        // At launch the window may not be on screen yet: retry a few times.
        guard let win = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let screen = (win.screen ?? NSScreen.main)?.visibleFrame else {
            if attempt < 20 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { fit(content: content, viewport: viewport, attempt: attempt + 1) }
            }
            return
        }
        done = true
        UserDefaults.standard.set(layout, forKey: key)
        let dw = max(0, ceil(content.width - viewport.width)), dh = max(0, ceil(content.height - viewport.height))
        guard dw > 0 || dh > 0 else { return }
        var f = win.frame
        f.size.width = min(f.width + dw + 4, screen.width)
        f.size.height = min(f.height + dh + 4, screen.height)
        f.origin.y = max(screen.minY, win.frame.maxY - f.height)        // keep the title bar in place
        f.origin.x = min(max(screen.minX, f.origin.x), screen.maxX - f.width)
        win.setFrame(f, display: true, animate: true)
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
                    Text(verbatim: "SOLO OFF").font(.system(size: 10, weight: .bold)).kerning(0.8)
                        .foregroundColor(Theme.solo)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .overlay(Capsule().stroke(Theme.solo.opacity(0.6)))
                }.buttonStyle(.plain)
            }
            GeometryReader { viewport in
                ScrollView([.horizontal, .vertical]) {
                    HStack(alignment: .center, spacing: 22) {
                        VStack(alignment: .leading, spacing: 16) {
                            section(L("Inputs"), Theme.input) {
                                ForEach(0..<9) { p in
                                    PairView(kind: .input, pair: p, mix: m.selectedMix, name: m.inputName, meter: Reg.inputMeter)
                                }
                            }
                            section(m.bool(Reg.a2md) ? L("DAW returns / ADAT 9-16") : L("DAW returns"), Theme.playback) {
                                ForEach(0..<9) { p in
                                    PairView(kind: .playback, pair: p, mix: m.selectedMix, name: m.playbackName, meter: Reg.playbackMeter)
                                }
                            }
                        }
                        section("Master", Theme.master) {
                            StripView(kind: .output, ch: 18 + m.selectedMix, mix: 0, title: m.mixName(m.selectedMix),
                                      meterIndex: Reg.mixMeter(m.selectedMix, right: false), showPan: false, showSolo: false)
                        }
                    }
                    .padding(.bottom, 10)
                    .fixedSize()
                    .background(GeometryReader { g in
                        Color.clear.onAppear { WindowFitter.fit(content: g.size, viewport: viewport.size) }
                    })
                    .frame(minWidth: viewport.size.width, minHeight: viewport.size.height, alignment: .topLeading)
                }
            }
            Text(L("Drag: fader · ⌥ drag: fine · scroll wheel: ±0.375 dB (⇧ ×8) · double-click: 0 dB / center"))
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
                GroupBox(L("Physical outputs")) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(0..<9) { OutputRow(pair: $0) }
                    }.padding(6)
                }
                GroupBox(L("Main and headphones")) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(0..<4) { MonitorRow(idx: $0) }
                        Text(L("Main and the headphones copy an output pair. To hear a mix in the headphones, send it to that pair above."))
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

    /// Offered stereo sources (value = left channel).
    private var sources: [SourceOption] {
        var s: [SourceOption] = []
        for mix in 0..<Reg.mixCount { s.append(SourceOption(value: 36 + mix * 2, label: m.mixName(mix))) }
        for p in 0..<9 { s.append(SourceOption(value: p * 2, label: L("Input %@ / %@", m.inputName(p * 2), m.inputName(p * 2 + 1)))) }
        for p in 0..<9 { s.append(SourceOption(value: 18 + p * 2, label: m.playbackName(p * 2) + " / " + m.playbackName(p * 2 + 1))) }
        let cur = m.outputSource(pair * 2)
        if !s.contains(where: { $0.value == cur }) { s.append(SourceOption(value: cur, label: L("Other: %@", m.sourceName(cur)))) }
        return s
    }

    var body: some View {
        let left = m.outputSource(pair * 2), right = m.outputSource(pair * 2 + 1)
        let binding = Binding<Int>(get: { left }, set: { m.setPairSource(pair: pair, left: $0) })
        return HStack(spacing: 10) {
            Text(verbatim: RoutingPage.pairNames[pair]).frame(width: 110, alignment: .leading)
            Picker("", selection: binding) {
                ForEach(sources, id: \.self) { o in Text(o.label).tag(o.value) }
            }.frame(width: 320)
            HStack(spacing: 2) {
                MeterBar(index: Reg.sourceMeter(left)).frame(width: 9)
                MeterBar(index: Reg.sourceMeter(right)).frame(width: 9)
            }.frame(height: 18)
            Text(verbatim: m.sourceName(left) + " · " + m.sourceName(right)).font(.caption).foregroundColor(.secondary)
        }
    }
}

struct MonitorRow: View {
    @EnvironmentObject var m: MixerModel
    var idx: Int

    var body: some View {
        let pairB = Binding<Int>(get: { m.monitorPair(idx) }, set: { m.setMonitorPair(idx, $0) })
        return HStack(spacing: 10) {
            Text(verbatim: idx == 0 ? "Main" : "Phones \(idx)").frame(width: 110, alignment: .leading)
            Picker(L("Copy of"), selection: pairB) {
                ForEach(0..<9) { Text(verbatim: RoutingPage.pairNames[$0]).tag($0) }
            }.frame(width: 230)
        }
    }
}

struct SettingsPage: View {
    @EnvironmentObject var m: MixerModel
    @State private var message = ""
    @StateObject private var driver = DriverModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 18) {
                GroupBox(L("FireStudio settings")) {
                    VStack(alignment: .leading, spacing: 8) {
                        toggle(L("Terminate BNC (75 Ω word clock termination)"), Reg.bnct)
                        toggle(L("Expanded Mix Mode (ADAT 2) — DAW returns 11-18 become ADAT 9-16"), Reg.a2md)
                        toggle(L("Talkback to digital outputs"), Reg.tbdo)
                        toggle(L("Copy 1/2 to main L/R in surround mode"), Reg.dcmt)
                        toggle(L("Mains active in surround mode (unchecked = mains muted)"), Reg.mtss)
                        Text(L("Sample rate: %d Hz (change it in Audio MIDI Setup)", m.sampleRate))
                            .font(.caption).foregroundColor(.secondary)
                    }.padding(6).frame(maxHeight: .infinity, alignment: .top)
                }.fixedSize(horizontal: true, vertical: false)
                DriverBox(driver: driver)
                }.fixedSize(horizontal: false, vertical: true)
                GroupBox(L("Backups")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("A full copy of the device state is saved on every connection."))
                            .font(.caption).foregroundColor(.secondary)
                        if let b = m.lastBackup { Text(L("Latest: %@", b.lastPathComponent)).font(.caption.monospaced()) }
                        HStack {
                            Button(L("Save current state…")) { saveAs() }
                            Button(L("Restore a backup…")) { restore() }
                            Button(L("Open folder")) { NSWorkspace.shared.open(Backup.folder) }
                            Button(L("Reload from device")) { m.reloadFromDevice() }
                        }
                        if !message.isEmpty { Text(message).font(.caption) }
                    }.padding(6)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { driver.start() }
        .onDisappear { driver.stop() }
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
            message = L("Saved: %@", url.lastPathComponent)
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
                Text(verbatim: "FIRESTUDIO").font(.system(size: 12, weight: .heavy)).kerning(2).foregroundColor(Theme.text)
                Text(verbatim: m.connected ? "26x26 · \(m.sampleRate / 1000) kHz" : m.status)
                    .font(.system(size: 11)).foregroundColor(Theme.dim)
                Spacer()
                Picker("", selection: $tab) {
                    Text(L("Mixer")).tag(0); Text(L("Outputs / routing")).tag(1); Text(L("Settings")).tag(2)
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
                        Text(verbatim: m.status).foregroundColor(.secondary)
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

/// Settings of the PreSonus driver: operation mode, clock source, stream error counters.
struct DriverBox: View {
    @EnvironmentObject var m: MixerModel
    @ObservedObject var driver: DriverModel

    var body: some View {
        GroupBox(L("Driver")) {
            VStack(alignment: .leading, spacing: 8) {
                if let mode = driver.mode {
                    opModeSection(mode)
                    Divider()
                    clockSection
                    Divider()
                    errorSection
                } else {
                    Text(L("PreSonus driver not loaded: operation mode unavailable."))
                        .font(.caption).foregroundColor(.secondary)
                }
            }.padding(6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    func opModeSection(_ mode: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Operation mode")).font(.callout.weight(.semibold))
            Picker(L("Operation mode"), selection: Binding(get: { mode }, set: { driver.set($0) })) {
                Text(L("Lowest latency")).tag(0)
                Text(L("Normal (default)")).tag(1)
                Text(L("Safe")).tag(2)
                Text(L("Safest")).tag(3)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .disabled(driver.busy)
            if let o = driver.offsets, o.rate > 0 {
                Text(L("Driver safety buffer at %d Hz: output %d, input %d samples (%@ ms in total).",
                       o.rate, o.output, o.input, DriverBox.ms(o.output + o.input, o.rate)))
                    .font(.caption.monospacedDigit())
            }
            Text(L("A higher mode adds a little latency but makes playback more robust against dropouts and crackles. Changing it briefly restarts the audio stream; the PreSonus driver remembers the setting."))
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var clockSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(L("Clock source")).font(.callout.weight(.semibold))
                Picker(L("Clock source"), selection: Binding(get: { driver.clock ?? 8 }, set: { driver.setClock($0) })) {
                    ForEach(DriverSettings.clockSources, id: \.item) { Text($0.name).tag($0.item) }
                }
                .labelsHidden()
                .frame(maxWidth: 160)
                .disabled(driver.busy || driver.clock == nil)
                lockBadge
            }
            Text(L("Use Internal unless another device is the clock master. When the interface follows S/PDIF, ADAT or word clock, it stays muted until it receives a valid signal on that input."))
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder var lockBadge: some View {
        if let locked = m.clockLocked {
            HStack(spacing: 4) {
                Circle().fill(locked ? Color.green : Color.red).frame(width: 8, height: 8)
                Text(locked ? L("Locked") : L("Not locked")).font(.caption)
            }
        }
    }

    var errorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(L("Stream errors")).font(.callout.weight(.semibold))
                if let e = driver.errors {
                    Text(verbatim: "\(e.total)")
                        .font(.callout.monospacedDigit().weight(.semibold))
                        .foregroundColor(e.total == 0 ? .green : .orange)
                }
                Spacer()
                Button(L("Reset")) { driver.resetErrors() }.disabled(driver.errors == nil)
            }
            if let e = driver.errors {
                Text(L("Playback %d · recording %d · timing %d", e.playback, e.recording, e.timing))
                    .font(.caption.monospacedDigit())
            }
            Text(L("Dropouts counted by the driver on the FireWire audio stream. Reset, play the project, then check: if the counter stays at 0, the interface is not the cause."))
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func ms(_ samples: Int, _ rate: Int) -> String {
        String(format: "%.1f", locale: Locale.current, Double(samples) * 1000 / Double(rate))
    }
}
