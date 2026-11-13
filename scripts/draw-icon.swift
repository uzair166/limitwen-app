import AppKit

// Original vector artwork, rendered at every macOS icon size.
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Unable to create icon surface") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let transform = NSAffineTransform()
        transform.scale(by: CGFloat(pixels) / 1024)
        transform.concat()
        let surface = NSBezierPath(roundedRect: NSRect(x: 50, y: 50, width: 924, height: 924), xRadius: 207, yRadius: 207)
        NSGradient(colors: [NSColor(srgbRed: 0.23, green: 0.25, blue: 0.28, alpha: 1), NSColor(srgbRed: 0.09, green: 0.10, blue: 0.12, alpha: 1)])?.draw(in: surface, angle: -90)
        NSColor.white.withAlphaComponent(0.16).setStroke()
        surface.lineWidth = 3; surface.stroke()
        for (radius, fraction, width, alpha) in [(270.0, 0.74, 37.0, 0.92), (168.0, 0.38, 33.0, 0.64)] {
            let track = NSBezierPath(ovalIn: NSRect(x: 512 - radius, y: 512 - radius, width: 2 * radius, height: 2 * radius))
            track.lineWidth = width
            NSColor.white.withAlphaComponent(0.075).setStroke(); track.stroke()
            let arc = NSBezierPath()
            arc.lineWidth = width; arc.lineCapStyle = .round
            arc.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: radius, startAngle: 90, endAngle: 90 - fraction * 360, clockwise: true)
            NSColor(srgbRed: 0.88, green: 0.91, blue: 0.95, alpha: alpha).setStroke(); arc.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Unable to render app icon") }
        let suffix = scale == 2 ? "@2x" : ""
        try png.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
