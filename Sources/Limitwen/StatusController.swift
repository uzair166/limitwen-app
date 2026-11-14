import AppKit
import SwiftUI
import LimitwenCore

@MainActor
final class StatusController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private var items: [String: NSStatusItem] = [:]
    private let popover: NSPopover
    private var settingsController: SettingsController?
    private weak var currentAnchor: NSStatusBarButton?
    private var appearanceObserver: NSKeyValueObservation?
    private var itemAppearanceObservers: [String: NSKeyValueObservation] = [:]
    private var outsideClickMonitor: Any?

    init(model: AppModel, popover: NSPopover = NSPopover()) {
        self.model = model
        self.popover = popover
        super.init()
        popover.behavior = .transient
        // A menu-bar glance should appear immediately, without a zoom/fade.
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: LimitsView(model: model)
            .onExitCommand { [weak popover] in popover?.performClose(nil) })
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDeactivated),
            name: NSApplication.didResignActiveNotification, object: NSApp)
        model.onMenuChange = { [weak self] in self?.rebuild() }
        model.onSettings = { [weak self] in self?.showSettings() }
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.rebuild() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        rebuild()
        // Prepare SwiftUI's initial layout during setup, not on the first click.
        measureContent()
    }

    func popoverWillShow(_ notification: Notification) {
        model.setPresentationVisible("popover", visible: true)
        // Native menu tracking can leave a transient popover's automatic dismissal
        // inactive. Keep an independent outside-click path for each presentation.
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        model.setPresentationVisible("popover", visible: false)
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    @objc private func applicationDeactivated() {
        if popover.isShown { popover.performClose(nil) }
    }

    func rebuild() {
        let pins = model.preferences.visiblePins
        let desired = pins.isEmpty ? ["app"] : pins.map(\.rawValue)
        for key in Array(items.keys) where !desired.contains(key) {
            if popover.isShown { popover.performClose(nil) }
            itemAppearanceObservers.removeValue(forKey: key)
            if let item = items.removeValue(forKey: key) { NSStatusBar.system.removeStatusItem(item) }
        }
        for key in desired.reversed() {
            let item: NSStatusItem
            if let existing = items[key] { item = existing }
            else {
                item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.autosaveName = "Limitwen.\(key)"
                items[key] = item
            }
            guard let button = item.button else { continue }
            if itemAppearanceObservers[key] == nil {
                // Status items adopt the menu bar's appearance after insertion,
                // independently of NSApp (including wallpaper-driven changes).
                itemAppearanceObservers[key] = button.observe(\.effectiveAppearance, options: [.new]) { [weak self, weak button] _, _ in
                    Task { @MainActor in
                        guard let self, let button, self.items[key]?.button === button else { return }
                        // AppKit may invalidate appearance during status-item layout
                        // even when its value is unchanged. Rebuilding here feeds
                        // that notification back into layout indefinitely.
                        guard let provider = ProviderID(rawValue: key) else { return }
                        button.effectiveAppearance.performAsCurrentDrawingAppearance {
                            let image = self.makeImage(provider: provider, snapshot: self.model.states[provider]?.snapshot)
                            if button.image !== image { button.image = image }
                        }
                    }
                }
            }
            button.target = self; button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.identifier = NSUserInterfaceItemIdentifier(key)
            button.font = .systemFont(ofSize: 10.5, weight: .medium)
            button.imagePosition = .imageTrailing
            if let provider = ProviderID(rawValue: key) {
                button.title = model.preferences.showInitials ? provider.initials + " " : ""
                let snapshot = model.states[provider]?.snapshot
                button.effectiveAppearance.performAsCurrentDrawingAppearance {
                    button.image = makeImage(provider: provider, snapshot: snapshot)
                }
                let stale = snapshot?.isStale(at: model.now) == true || model.states[provider]?.error != nil
                let limits = snapshot?.displayWindows.map { window in
                    let suffix = stale || window.hasElapsed(at: model.now) ? "last known" : "remaining"
                    return "\(window.title): \(window.remainingPercent.map { "\(Int($0.rounded()))% \(suffix)" } ?? "not reported")"
                }.joined(separator: ", ") ?? "Usage not available"
                let label = "\(provider.name) — \(limits)\(model.preview ? ". Preview" : "")"
                button.toolTip = label
                button.setAccessibilityLabel(label)
            } else {
                button.title = ""
                button.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "Limitwen")
                button.toolTip = "Limitwen — your subscriptions"
                button.setAccessibilityLabel("Limitwen — open usage")
            }
        }
    }

    private func makeImage(provider: ProviderID, snapshot: UsageSnapshot?) -> NSImage {
        MenuMeter.image(windows: snapshot?.displayWindows ?? [],
            stale: snapshot?.isStale(at: model.now) == true || model.states[provider]?.error != nil,
            now: model.now, threshold: model.preferences.threshold)
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Refresh limits", action: #selector(refresh), keyEquivalent: "r").target = self
            menu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Limitwen", action: #selector(quit), keyEquivalent: "q").target = self
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY), in: sender)
            return
        }
        let selected = sender.identifier.flatMap { ProviderID(rawValue: $0.rawValue) }
        if popover.isShown && model.selected == selected { popover.performClose(nil); return }
        present(sender, provider: selected)
    }
    private func present(_ sender: NSStatusBarButton, provider: ProviderID?) {
        if popover.isShown { popover.performClose(nil) }
        currentAnchor = sender
        updateAvailableSpace()
        model.selected = provider
        popover.animates = false
        // AppKit must know the final size before choosing which side of the anchor fits.
        // An unmeasured hosting controller initially reports a zero-sized popover.
        measureContent()
        NSApp.activate(ignoringOtherApps: true)
        let below: NSRectEdge = sender.isFlipped ? .maxY : .minY
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: below)
        popover.contentViewController?.view.window?.makeKey()
    }
    private func measureContent() {
        if let view = popover.contentViewController?.view {
            view.layoutSubtreeIfNeeded()
            popover.contentSize = view.fittingSize
        }
    }
    func showInitial(provider: ProviderID? = nil) {
        let key = provider.flatMap { items[$0.rawValue] == nil ? nil : $0.rawValue } ?? model.preferences.visiblePins.first?.rawValue ?? "app"
        if let button = items[key]?.button { present(button, provider: provider ?? ProviderID(rawValue: key)) }
    }
    @objc private func refresh() { Task { await model.refresh(force: true) } }
    @objc private func settings() { showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func screenChanged() {
        updateAvailableSpace()
        if popover.isShown, let currentAnchor { present(currentAnchor, provider: model.selected) }
    }
    private func updateAvailableSpace() {
        let height = (currentAnchor?.window?.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 800) - 20
        if model.popoverAvailableHeight != height { model.popoverAvailableHeight = height }
    }
    func showSettings() {
        popover.performClose(nil)
        if settingsController == nil { settingsController = SettingsController(model: model) }
        NSApp.activate(ignoringOtherApps: true)
        settingsController?.present()
    }
}
