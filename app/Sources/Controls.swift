import SwiftUI
import AppKit

// MARK: - Sober "console" theme

enum Theme {
    static let window = Color(red: 0.105, green: 0.11, blue: 0.12)
    static let panel = Color(red: 0.14, green: 0.145, blue: 0.16)
    static let stripTop = Color(red: 0.19, green: 0.195, blue: 0.21)
    static let stripBottom = Color(red: 0.145, green: 0.15, blue: 0.165)
    static let hairline = Color.white.opacity(0.07)
    static let text = Color.white.opacity(0.88)
    static let dim = Color.white.opacity(0.45)

    static let input = Color(red: 0.38, green: 0.63, blue: 0.96)
    static let playback = Color(red: 0.42, green: 0.80, blue: 0.56)
    static let master = Color(red: 0.96, green: 0.70, blue: 0.30)
    static let mute = Color(red: 0.93, green: 0.30, blue: 0.28)
    static let solo = Color(red: 0.97, green: 0.82, blue: 0.25)

    static func accent(_ kind: MixerModel.Kind) -> Color {
        switch kind { case .input: return input; case .playback: return playback; case .output: return master }
    }
}

// MARK: - Scroll wheel: routes events to the hovered control

final class ScrollRouter {
    static let shared = ScrollRouter()
    private(set) var owner: UUID?
    private var handler: ((Int) -> Void)?
    private var accumulated: CGFloat = 0
    private var monitor: Any?

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            guard let self = self, let h = self.handler else { return e }
            // Physical direction: up = fader up, whatever the "natural scrolling" setting.
            var d = e.scrollingDeltaY != 0 ? e.scrollingDeltaY : e.scrollingDeltaX   // ⇧ turns Y into X
            if e.isDirectionInvertedFromDevice { d = -d }
            let coarse = e.modifierFlags.contains(.shift)
            var steps = 0
            if e.hasPreciseScrollingDeltas {          // trackpad / Magic Mouse
                self.accumulated += d
                let unit: CGFloat = 6
                steps = Int(self.accumulated / unit)
                self.accumulated -= CGFloat(steps) * unit
            } else if d != 0 {                        // notched wheel
                steps = d > 0 ? max(1, Int(d.rounded())) : min(-1, Int(d.rounded()))
            }
            if steps != 0 { h(steps * (coarse ? 8 : 1)) }
            return nil                                // consumed: the view does not scroll
        }
    }

    func enter(_ id: UUID, _ h: @escaping (Int) -> Void) { owner = id; handler = h; accumulated = 0 }
    func leave(_ id: UUID) { if owner == id { owner = nil; handler = nil } }
}

// MARK: - LED meter with peak hold (AppKit view, outside the SwiftUI graph)

final class MeterNSView: NSView {
    var index: Int? { didSet { shown = (-1, -1); refresh() } }
    private var shown = (-1, -1)
    private static let green = NSColor(Theme.playback), yellow = NSColor(Theme.solo), red = NSColor(Theme.mute)

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }

    func refresh() {
        let s = MeterStore.shared
        let now = (s.level(index), s.peak(index))
        if now != shown { shown = now; needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 2, yRadius: 2).fill()
        let n = MeterStore.leds
        let inner = bounds.insetBy(dx: 1.5, dy: 1.5)
        let gap: CGFloat = 1
        let seg = (inner.height - gap * CGFloat(n - 1)) / CGFloat(n)
        let (level, peak) = shown
        for i in 0..<n {
            let pos = Double(i + 1) / Double(n)
            let color = pos > 0.9 ? MeterNSView.red : (pos > 0.72 ? MeterNSView.yellow : MeterNSView.green)
            let lit = i < level || (peak > 1 && i == peak - 1)
            (lit ? color : color.withAlphaComponent(0.10)).setFill()
            let r = NSRect(x: inner.minX, y: inner.minY + CGFloat(i) * (seg + gap), width: inner.width, height: seg)
            NSBezierPath(roundedRect: r, xRadius: 1, yRadius: 1).fill()
        }
    }
}

struct MeterBar: NSViewRepresentable {
    var index: Int?
    var width: CGFloat = 6
    func makeNSView(context: Context) -> MeterNSView {
        let v = MeterNSView()
        MeterStore.shared.register(v)
        v.index = index
        return v
    }
    func updateNSView(_ v: MeterNSView, context: Context) { if v.index != index { v.index = index } }
}

// MARK: - Fader

/// Vertical fader 0…255 (255 = 0 dB, 0.375 dB per step).
/// Relative drag (no jump), ⌥ = 4× finer, scroll wheel = ±1 step (⇧: ×8), double-click = 0 dB.
/// During a gesture the display is local; the device receives the values in the background.
struct Fader: View {
    static func dB(_ v: Double) -> String {
        v < 1 ? "−∞" : String(format: "%.1f", locale: Locale.current, (v - 255) * 0.375)
    }
    /// Scale marks: (internal value, label)
    static let marks: [(Double, String)] = [(255, "0"), (239, "6"), (223, "12"), (191, "24"), (127, "48"), (63, "72"), (0, "∞")]

    var value: Double
    var accent: Color
    var onChange: (Double, _ live: Bool) -> Void
    var height: CGFloat = 190

    @State private var drag: Double?
    @State private var lastY: CGFloat = 0
    @State private var hover = false
    @State private var commit: DispatchWorkItem?
    @State private var id = UUID()
    private let cap: CGFloat = 30

    var body: some View {
        let shown = drag ?? value
        HStack(alignment: .top, spacing: 1) {
            scale
            GeometryReader { g in
                let travel = g.size.height - cap
                let y = travel * CGFloat(1 - shown / 255)
                ZStack(alignment: .top) {
                    // slot
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.black.opacity(0.7))
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.white.opacity(0.06)))
                        .frame(width: 5)
                        .padding(.vertical, cap / 2 - 2)
                        .frame(maxWidth: .infinity)
                    // subtle fill below the cap
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(accent.opacity(0.55))
                        .frame(width: 3, height: max(0, travel - y))
                        .offset(y: y + cap / 2)
                    capView.offset(y: y)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { d in
                        if drag == nil { drag = value; lastY = 0; commit?.cancel() }
                        let fine = NSEvent.modifierFlags.contains(.option)
                        let delta = d.translation.height - lastY
                        lastY = d.translation.height
                        let v = max(0, min(255, (drag ?? value) - Double(delta / max(travel, 1)) * 255 * (fine ? 0.25 : 1)))
                        drag = v
                        onChange(v, true)
                    }
                    .onEnded { _ in
                        if let v = drag { onChange(v.rounded(), false) }
                        drag = nil
                    })
                .onTapGesture(count: 2) { drag = nil; onChange(255, false) }
            }
            .frame(width: 32, height: height)
        }
        .onHover { inside in
            hover = inside
            if inside { ScrollRouter.shared.enter(id) { wheel($0) } } else { ScrollRouter.shared.leave(id) }
        }
        .onChange(of: value) { _ in   // the value changed elsewhere: the handler must see the new one
            if hover { ScrollRouter.shared.enter(id) { wheel($0) } }
        }
        .onDisappear { ScrollRouter.shared.leave(id) }
    }

    private func wheel(_ steps: Int) {
        let v = max(0, min(255, (drag ?? value).rounded() + Double(steps)))
        drag = v
        onChange(v, true)
        commit?.cancel()
        let w = DispatchWorkItem { onChange(v, false); drag = nil }
        commit = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: w)
    }

    private var capView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: [Color(white: hover ? 0.86 : 0.78), Color(white: 0.52), Color(white: 0.40)],
                                     startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.6), radius: 2, y: 2)
            VStack(spacing: 3) {
                ForEach(0..<2) { _ in Rectangle().fill(Color.black.opacity(0.35)).frame(height: 1) }
                Rectangle().fill(Color.white.opacity(0.95)).frame(height: 1.5)
                ForEach(0..<2) { _ in Rectangle().fill(Color.black.opacity(0.35)).frame(height: 1) }
            }
            .padding(.horizontal, 4)
        }
        .frame(width: 28, height: cap)
    }

    private var scale: some View {
        Canvas { ctx, size in Fader.drawScale(&ctx, size, cap) }
            .frame(width: 16, height: height)
    }

    static func drawScale(_ ctx: inout GraphicsContext, _ size: CGSize, _ cap: CGFloat) {
        let travel = size.height - cap
        for (v, label) in marks {
            let y = cap / 2 + travel * CGFloat(1 - v / 255)
            ctx.fill(Path(CGRect(x: size.width - 4, y: y - 0.5, width: 4, height: 1)), with: .color(Theme.dim))
            let t = ctx.resolve(Text(label).font(.system(size: 7.5, weight: .medium)).foregroundColor(Theme.dim))
            ctx.draw(t, at: CGPoint(x: size.width - 6, y: y), anchor: .trailing)
        }
    }
}

// MARK: - Pan

struct PanControl: View {
    var value: Double                 // 0…255, 0x7F = center
    var accent: Color
    var onChange: (Double, _ live: Bool) -> Void
    @State private var drag: Double?
    @State private var start: Double = 0

    private func panHelp(_ v: Double) -> String {
        let amount = Int(abs(v - 0x7F))
        if amount == 0 { return L("Center") }
        return v < 0x7F ? L("L %d", amount) : L("R %d", amount)
    }

    var body: some View {
        let shown = drag ?? value
        GeometryReader { g in
            let w = g.size.width
            let x = w * CGFloat(shown / 255)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.6)).frame(height: 4)
                Rectangle().fill(accent.opacity(0.8))
                    .frame(width: abs(x - w / 2), height: 2)
                    .offset(x: min(x, w / 2))
                Rectangle().fill(Theme.dim).frame(width: 1, height: 8).offset(x: w / 2)
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.8), Color(white: 0.45)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
                    .frame(width: 10, height: 10).offset(x: x - 5)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { d in
                    if drag == nil { start = value }
                    let fine = NSEvent.modifierFlags.contains(.option)
                    let v = max(0, min(255, start + Double(d.translation.width / w) * 255 * (fine ? 0.25 : 1)))
                    drag = v
                    onChange(v, true)
                }
                .onEnded { _ in
                    if let v = drag { onChange(v.rounded(), false) }
                    drag = nil
                })
            .onTapGesture(count: 2) { onChange(0x7F, false) }
        }
        .frame(width: 50, height: 14)
        .help(panHelp(shown))
    }
}

// MARK: - Buttons

struct GlowButton: View {
    var label: String
    var on: Bool
    var color: Color
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: 10, weight: .heavy, design: .rounded))
                .frame(width: 22, height: 17)
                .foregroundColor(on ? .black.opacity(0.85) : Theme.dim)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(on ? color : Color.white.opacity(0.06))
                        .shadow(color: on ? color.opacity(0.7) : .clear, radius: 4)
                )
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(on ? 0 : 0.08)))
        }
        .buttonStyle(.plain)
    }
}

/// Section header with a colored rule.
struct SectionHeader: View {
    var title: String
    var color: Color
    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 3, height: 11)
            Text(title.uppercased(with: Locale.current)).font(.system(size: 10, weight: .semibold)).kerning(1.2).foregroundColor(Theme.dim)
        }
    }
}
