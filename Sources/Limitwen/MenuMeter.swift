import AppKit
import LimitwenCore

@MainActor
enum MenuMeter {
    private struct Signature: Equatable {
        let windows: [QuotaWindow]
        let elapsed: [Bool]
        let stale: Bool
        let threshold: Int
        let appearance: String
        let contrast: Bool
    }
    // A small bounded cache avoids allocating a bitmap every background poll.
    // Expiry, appearance and accessibility changes are explicit visual inputs.
    private static var cache: [(Signature, NSImage)] = []
    static func image(windows: [QuotaWindow], stale: Bool, now: Date, threshold: Int) -> NSImage {
        let ordered = Array(windows.sorted { ($0.durationMinutes ?? Int.max) < ($1.durationMinutes ?? Int.max) }.prefix(2))
        let signature = Signature(windows: ordered, elapsed: ordered.map { $0.hasElapsed(at: now) },
                                  stale: stale, threshold: threshold,
                                  appearance: NSAppearance.currentDrawing().name.rawValue,
                                  contrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
        if let cached = cache.first(where: { $0.0 == signature }) { return cached.1 }
        let image = NSImage(size: NSSize(width: 24, height: 22))
        image.lockFocus()
        defer { image.unlockFocus() }
        let entries: [QuotaWindow?] = ordered.isEmpty ? [nil] : Array(ordered.prefix(2)).map { $0 }
        for (index, entry) in entries.enumerated() {
            let value = entry?.remainingPercent
            let unverified = value == nil || entry?.hasElapsed(at: now) == true
            let low = !unverified && !stale && (value ?? 101) <= Double(threshold)
            let ink: NSColor = low ? Design.warningColor : .labelColor
            let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            let opacity: CGFloat = stale ? 0.45 : index == 0 ? 1 : contrast ? 0.85 : 0.65
            let radius: CGFloat = entries.count == 1 || index == 1 ? 9 : 5.2
            let bounds = NSRect(x: 12 - radius, y: 11 - radius, width: radius * 2, height: radius * 2)
            let track = NSBezierPath(ovalIn: bounds)
            track.lineWidth = 1.65
            if unverified { track.setLineDash([1.3, 2.0], count: 2, phase: 0) }
            NSColor.labelColor.withAlphaComponent(unverified ? 0.28 : 0.14).setStroke(); track.stroke()
            if !unverified, let value, value > 0 {
                let arc = NSBezierPath()
                arc.lineWidth = 1.8; arc.lineCapStyle = .round
                arc.appendArc(withCenter: NSPoint(x: 12, y: 11), radius: radius, startAngle: 90, endAngle: 90 - CGFloat(value) * 3.6, clockwise: true)
                ink.withAlphaComponent(opacity).setStroke(); arc.stroke()
            }
            if value == 0 && !unverified { Design.warningColor.setFill(); NSBezierPath(ovalIn: NSRect(x: 10.5, y: 9.5, width: 3, height: 3)).fill() }
        }
        cache.append((signature, image))
        if cache.count > 12 { cache.removeFirst() }
        return image
    }

}
