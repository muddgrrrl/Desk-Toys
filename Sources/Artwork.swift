import AppKit

struct AppMark {
    let fileName: String
    let name: String
    let color: NSColor
    let drawGlyph: () -> Void
}

let ink = NSColor(srgbRed: 0.075, green: 0.085, blue: 0.115, alpha: 1)

func stroke(_ path: NSBezierPath, width: CGFloat = 6) {
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
}

func line(_ points: CGPoint...) {
    let path = NSBezierPath()
    path.move(to: points[0])
    points.dropFirst().forEach { path.line(to: $0) }
    stroke(path)
}

func bell() {
    let body = NSBezierPath()
    body.move(to: CGPoint(x: 25, y: 36))
    body.curve(to: CGPoint(x: 33, y: 57), controlPoint1: CGPoint(x: 31, y: 42), controlPoint2: CGPoint(x: 33, y: 49))
    body.curve(to: CGPoint(x: 67, y: 57), controlPoint1: CGPoint(x: 33, y: 82), controlPoint2: CGPoint(x: 67, y: 82))
    body.curve(to: CGPoint(x: 75, y: 36), controlPoint1: CGPoint(x: 67, y: 49), controlPoint2: CGPoint(x: 69, y: 42))
    body.close()
    stroke(body)
    NSBezierPath(ovalIn: NSRect(x: 45, y: 22, width: 10, height: 10)).fill()
    line(CGPoint(x: 18, y: 62), CGPoint(x: 22, y: 71))
    line(CGPoint(x: 82, y: 62), CGPoint(x: 78, y: 71))
}

func fuse() {
    let ring = NSBezierPath()
    ring.appendArc(withCenter: CGPoint(x: 50, y: 46), radius: 24, startAngle: 35, endAngle: 325)
    stroke(ring)
    line(CGPoint(x: 50, y: 61), CGPoint(x: 50, y: 46), CGPoint(x: 61, y: 41))
    line(CGPoint(x: 69, y: 73), CGPoint(x: 75, y: 81))
    line(CGPoint(x: 79, y: 64), CGPoint(x: 88, y: 67))
}

func pocket() {
    let sheet = rounded(NSRect(x: 26, y: 26, width: 48, height: 48), 7)
    stroke(sheet)
    line(CGPoint(x: 37, y: 59), CGPoint(x: 63, y: 59))
    line(CGPoint(x: 37, y: 49), CGPoint(x: 63, y: 49))
    line(CGPoint(x: 37, y: 39), CGPoint(x: 52, y: 39))
    line(CGPoint(x: 41, y: 22), CGPoint(x: 59, y: 22))
}

let marks = [
    AppMark(fileName: "DeskBell", name: "Desk Bell",
            color: NSColor(srgbRed: 1, green: 0.62, blue: 0.71, alpha: 1), drawGlyph: bell),
    AppMark(fileName: "FocusFuse", name: "Focus Fuse",
            color: NSColor(srgbRed: 0.81, green: 0.91, blue: 0.58, alpha: 1), drawGlyph: fuse),
    AppMark(fileName: "PromptPocket", name: "Prompt Pocket",
            color: NSColor(srgbRed: 0.66, green: 0.79, blue: 1, alpha: 1), drawGlyph: pocket)
]

func canvas(_ width: Int, _ height: Int, at url: URL, draw: () -> Void) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    draw()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url)
}

func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawMark(_ mark: AppMark, in frame: NSRect) {
    let edge = frame.width
    let tile = rounded(frame, edge * 0.245)
    let dark = mark.color.blended(withFraction: 0.83, of: ink) ?? ink
    NSGradient(starting: dark, ending: ink)?.draw(in: tile, angle: 38)
    tile.lineWidth = edge * 0.013
    mark.color.withAlphaComponent(0.65).setStroke()
    tile.stroke()
    let inset = edge * 0.13
    let outline = rounded(frame.insetBy(dx: inset, dy: inset), edge * 0.16)
    outline.lineWidth = edge * 0.008
    mark.color.withAlphaComponent(0.21).setStroke()
    outline.stroke()

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext.current!.cgContext
    context.translateBy(x: frame.minX, y: frame.minY)
    context.scaleBy(x: edge / 100, y: edge / 100)
    mark.color.setStroke()
    mark.color.setFill()
    mark.drawGlyph()
    NSGraphicsContext.restoreGraphicsState()
}

func label(_ value: String, _ font: NSFont, _ color: NSColor, at origin: CGPoint) {
    NSAttributedString(string: value, attributes: [.font: font, .foregroundColor: color]).draw(at: origin)
}

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for mark in marks {
    try canvas(1024, 1024, at: destination.appendingPathComponent("\(mark.fileName).png")) {
        drawMark(mark, in: NSRect(x: 70, y: 70, width: 884, height: 884))
    }
}

if CommandLine.arguments.contains("--banner") {
    try canvas(1280, 360, at: destination.appendingPathComponent("desk-toys.png")) {
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 360)
        let base = rounded(frame, 32)
        let dusk = NSColor(srgbRed: 0.14, green: 0.16, blue: 0.22, alpha: 1)
        NSGradient(starting: ink, ending: dusk)?.draw(in: base, angle: 25)

        let line = NSBezierPath()
        line.move(to: CGPoint(x: 54, y: 300))
        line.line(to: CGPoint(x: 1226, y: 300))
        line.lineWidth = 2
        NSColor.white.withAlphaComponent(0.12).setStroke()
        line.stroke()

        let heading = NSFont.systemFont(ofSize: 82, weight: .heavy)
        label("Desk Toys", heading, .white, at: CGPoint(x: 50, y: 152))
        label("Three little apps for your Mac.", .systemFont(ofSize: 31, weight: .medium),
              NSColor(srgbRed: 0.76, green: 0.79, blue: 0.87, alpha: 1), at: CGPoint(x: 54, y: 106))

        for (index, mark) in marks.enumerated() {
            let x = 680.0 + Double(index) * 182
            drawMark(mark, in: NSRect(x: x, y: 117, width: 140, height: 140))
            let font = NSFont.systemFont(ofSize: 21, weight: .semibold)
            let name = NSAttributedString(string: mark.name, attributes: [.font: font, .foregroundColor: mark.color])
            name.draw(at: CGPoint(x: x + (140 - name.size().width) / 2, y: 70))
        }
    }
}
