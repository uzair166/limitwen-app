import AppKit
import SwiftUI

/// One native settings window, reused across closing, minimizing and reopening.
@MainActor
final class SettingsController: NSWindowController, NSWindowDelegate {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
        window.title = "Limitwen Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("Limitwen.Settings")
        window.setContentSize(Design.settingsSize)
        super.init(window: window)
        window.delegate = self
    }
    required init?(coder: NSCoder) { nil }

    func present() {
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        model.setPresentationVisible("settings", visible: true)
    }
    func windowWillClose(_ notification: Notification) { model.setPresentationVisible("settings", visible: false) }
    func windowDidMiniaturize(_ notification: Notification) { model.setPresentationVisible("settings", visible: false) }
    func windowDidDeminiaturize(_ notification: Notification) { model.setPresentationVisible("settings", visible: true) }
}
