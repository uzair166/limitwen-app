import AppKit
import SwiftUI
import LimitwenCore

/// Renders app-owned views offscreen for visual review; never captures the desktop or user data.
@MainActor
enum PreviewRenderer {
    static func render(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = AppModel(preview: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            var renderingError: Error?
            NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
                do { try save(MenuReview(model: model), name: "menu-icons-\(name)", appearance: appearance, directory: directory) }
                catch { renderingError = error }
            }
            if let renderingError { throw renderingError }
            try save(LimitsView(model: model), name: "popover-\(name)", appearance: appearance, directory: directory)
            try save(SettingsView(model: model), name: "preferences-\(name)", appearance: appearance, directory: directory)
        }
        model.change { $0.enabled = [.codex]; $0.pinned = [.codex] }
        model.states[.codex] = ProviderState(snapshot: UsageSnapshot(provider: .codex, windows: [
            QuotaWindow(id: "weekly", title: "Weekly window", durationMinutes: 10080, usedPercent: 100, resetsAt: model.now.addingTimeInterval(3600))
        ], observedAt: model.now, source: "Example values"))
        try save(LimitsView(model: model), name: "unknown-and-exhausted", appearance: .aqua, directory: directory)
        model.states[.codex]?.error = "Usage is temporarily unavailable. Try again shortly."
        try save(LimitsView(model: model), name: "stale-error", appearance: .darkAqua, directory: directory)
        model.states = [:]
        try save(LimitsView(model: model), name: "disconnected", appearance: .aqua, directory: directory)
        model.change { $0.enabled = []; $0.pinned = [] }
        try save(LimitsView(model: model), name: "empty", appearance: .aqua, directory: directory)
    }
    private static func save<Content: View>(_ content: Content, name: String, appearance: NSAppearance.Name, directory: URL) throws {
        let host = NSHostingView(rootView: content)
        host.appearance = NSAppearance(named: appearance)
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = host.appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // Resolve SwiftUI's measured scroll content before capturing its final geometry.
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        window.setContentSize(host.fittingSize)
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw ProviderFailure.invalidResponse }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw ProviderFailure.invalidResponse }
        try data.write(to: directory.appendingPathComponent(name + ".png"))
        window.close()
    }
}

private struct MenuReview: View {
    let model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Menu bar · actual component sizes").font(.system(size: 13, weight: .medium))
            HStack(spacing: 12) {
                ForEach(ProviderID.allCases) { provider in
                    HStack(spacing: 3) {
                        Text(provider.initials).font(.system(size: 10.5, weight: .medium))
                        Image(nsImage: MenuMeter.image(windows: model.states[provider]?.snapshot?.displayWindows ?? [], stale: false, now: model.now, threshold: 20))
                    }
                }
                Divider().frame(height: 17)
                Image(nsImage: MenuMeter.image(windows: [.unknownShort, .unknownWeek], stale: false, now: model.now, threshold: 20))
                Text("Unknown").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Text("Inner: shorter window · Outer: longer window\nOnly reported windows appear.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(24).background(Color(nsColor: .windowBackgroundColor))
    }
}
