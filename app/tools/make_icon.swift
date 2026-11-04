// Dessine l'icône de FireStudio Mixer (1024×1024) : swift make_icon.swift <sortie.png>
import AppKit

let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }

// Fond : carré arrondi (grille macOS : 824 px, marge 100)
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow(); shadow.shadowColor = c(0, 0, 0, 0.45); shadow.shadowBlurRadius = 28; shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
c(0.10, 0.105, 0.115).setFill(); shape.fill()
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.saveGraphicsState()
shape.addClip()
NSGradient(colors: [c(0.21, 0.215, 0.235), c(0.11, 0.115, 0.13)])!.draw(in: body, angle: -90)
// reflet discret en haut
NSGradient(colors: [c(1, 1, 1, 0.08), c(1, 1, 1, 0)])!.draw(in: NSRect(x: 100, y: 600, width: 824, height: 324), angle: -90)

// Trois faders
let accents = [c(0.38, 0.63, 0.96), c(0.42, 0.80, 0.56), c(0.96, 0.70, 0.30)]
let xs: [CGFloat] = [255, 410, 565]
let caps: [CGFloat] = [560, 410, 640]       // hauteur des poignées
for (i, x) in xs.enumerated() {
    // graduations
    for k in 0..<7 {
        let y = 250 + CGFloat(k) * 90
        c(1, 1, 1, 0.16).setFill()
        NSBezierPath(rect: NSRect(x: x - 62, y: y - 2, width: 22, height: 4)).fill()
    }
    // rainure
    c(0, 0, 0, 0.75).setFill()
    NSBezierPath(roundedRect: NSRect(x: x - 11, y: 230, width: 22, height: 560), xRadius: 11, yRadius: 11).fill()
    // remplissage coloré sous la poignée
    accents[i].withAlphaComponent(0.85).setFill()
    NSBezierPath(roundedRect: NSRect(x: x - 5, y: 238, width: 10, height: caps[i] - 238), xRadius: 5, yRadius: 5).fill()
    // poignée
    let cap = NSRect(x: x - 52, y: caps[i] - 46, width: 104, height: 92)
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = c(0, 0, 0, 0.6); sh.shadowBlurRadius = 14; sh.shadowOffset = NSSize(width: 0, height: -8); sh.set()
    let capPath = NSBezierPath(roundedRect: cap, xRadius: 12, yRadius: 12)
    c(0.5, 0.5, 0.5).setFill(); capPath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [c(0.86, 0.86, 0.87), c(0.55, 0.55, 0.57), c(0.40, 0.40, 0.42)])!.draw(in: capPath, angle: -90)
    for k in [-26, -14, 14, 26] as [CGFloat] {
        c(0, 0, 0, 0.30).setFill()
        NSBezierPath(rect: NSRect(x: cap.minX + 14, y: caps[i] + k - 2, width: cap.width - 28, height: 4)).fill()
    }
    c(1, 1, 1, 0.95).setFill()
    NSBezierPath(rect: NSRect(x: cap.minX + 10, y: caps[i] - 3.5, width: cap.width - 20, height: 7)).fill()
}

// Vu-mètre à LED
let mx: CGFloat = 712, n = 14
for k in 0..<n {
    let y = 236 + CGFloat(k) * 40
    let pos = CGFloat(k + 1) / CGFloat(n)
    let col = pos > 0.86 ? c(0.93, 0.30, 0.28) : (pos > 0.66 ? c(0.97, 0.82, 0.25) : c(0.42, 0.80, 0.56))
    let lit = k < 10
    (lit ? col : col.withAlphaComponent(0.13)).setFill()
    NSBezierPath(roundedRect: NSRect(x: mx, y: y, width: 58, height: 30), xRadius: 6, yRadius: 6).fill()
}
// liseré
NSGraphicsContext.restoreGraphicsState()
c(1, 1, 1, 0.10).setStroke()
let border = NSBezierPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), xRadius: 184, yRadius: 184); border.lineWidth = 3; border.stroke()
img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
