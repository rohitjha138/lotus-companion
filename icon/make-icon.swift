// Draws Lotus's app icon, a layered pink-and-white lotus logo, and writes icon/AppIcon.icns.
// Run from the repo root: swift icon/make-icon.swift
import AppKit

func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(red: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

/// A petal growing up from `base`, `length` long and `width` wide, turned by `angle` degrees.
func petal(base: NSPoint, length: CGFloat, width: CGFloat, angle: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: .zero)
    p.curve(to: NSPoint(x: 0, y: length), controlPoint1: NSPoint(x: -width, y: length * 0.3), controlPoint2: NSPoint(x: -width * 0.45, y: length * 0.86))
    p.curve(to: .zero, controlPoint1: NSPoint(x: width * 0.45, y: length * 0.86), controlPoint2: NSPoint(x: width, y: length * 0.3))
    p.close()
    var t = AffineTransform(translationByX: base.x, byY: base.y)
    t.rotate(byDegrees: -angle)
    p.transform(using: t)
    return p
}

func render(_ size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size)

    // Deep plum rounded square (macOS icon grid: ~10% margin).
    let inset = s * 0.1, box = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let squircle = NSBezierPath(roundedRect: box, xRadius: box.width * 0.225, yRadius: box.width * 0.225)
    NSGradient(starting: rgb(0x2B1638), ending: rgb(0x5A1F4E))!.draw(in: squircle, angle: 90)
    NSGraphicsContext.current?.saveGraphicsState()
    squircle.addClip()

    let u = box.width
    let base = NSPoint(x: box.midX, y: box.minY + u * 0.3)

    // Soft glow behind the flower.
    NSGradient(colors: [rgb(0xFF8FB8, 0.45), rgb(0xFF8FB8, 0)])!
        .draw(fromCenter: NSPoint(x: base.x, y: base.y + u * 0.2), radius: 0, toCenter: NSPoint(x: base.x, y: base.y + u * 0.2), radius: u * 0.5, options: [])

    func draw(_ length: CGFloat, _ width: CGFloat, _ angle: CGFloat, tip: Int, root: Int) {
        let path = petal(base: base, length: u * length, width: u * width, angle: angle)
        NSGradient(starting: rgb(root), ending: rgb(tip))!.draw(in: path, angle: 90 - angle)
        rgb(0xC2185B, 0.35).setStroke()
        path.lineWidth = max(0.5, u * 0.005)
        path.stroke()
    }

    // Back row: wide, pale petals.
    for a: CGFloat in [-78, 78] { draw(0.3, 0.13, a, tip: 0xF8A5C2, root: 0xFFF1F6) }
    for a: CGFloat in [-52, 52] { draw(0.38, 0.16, a, tip: 0xF48FB1, root: 0xFFF5F8) }

    // Golden heart peeking between the rows.
    let heart = NSBezierPath(ovalIn: NSRect(x: base.x - u * 0.1, y: base.y + u * 0.04, width: u * 0.2, height: u * 0.1))
    NSGradient(starting: rgb(0xFFD54F), ending: rgb(0xF9A825))!.draw(in: heart, angle: 90)
    for i in 0..<7 {  // stamens
        let x = base.x + u * (CGFloat(i) - 3) * 0.026
        let stamen = NSBezierPath(ovalIn: NSRect(x: x - u * 0.009, y: base.y + u * 0.125, width: u * 0.018, height: u * 0.018))
        rgb(0xFFE082).setFill()
        stamen.fill()
    }

    // Front row: richer pink tips fading to white at the base.
    for a: CGFloat in [-26, 26] { draw(0.44, 0.18, a, tip: 0xEC407A, root: 0xFFFFFF) }
    draw(0.5, 0.2, 0, tip: 0xE91E63, root: 0xFFFFFF)

    // A calm reflection line.
    let water = NSBezierPath()
    water.move(to: NSPoint(x: base.x - u * 0.24, y: base.y - u * 0.07))
    water.curve(to: NSPoint(x: base.x + u * 0.24, y: base.y - u * 0.07),
                controlPoint1: NSPoint(x: base.x - u * 0.08, y: base.y - u * 0.1),
                controlPoint2: NSPoint(x: base.x + u * 0.08, y: base.y - u * 0.04))
    rgb(0xFFC1D9, 0.7).setStroke()
    water.lineWidth = max(0.6, u * 0.012)
    water.lineCapStyle = .round
    water.stroke()

    NSGraphicsContext.current?.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let set = URL(fileURLWithPath: "icon/AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! render(1024).write(to: URL(fileURLWithPath: "icon/logo.png"))  // for the README and sharing
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", set.path, "-o", "icon/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: set)
print(iconutil.terminationStatus == 0 ? "wrote icon/AppIcon.icns and icon/logo.png" : "iconutil failed")
