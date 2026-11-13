import AppKit
import Testing
import LimitwenCore
@testable import Limitwen

/// Uses the production status-item click/presentation path and real AppKit window geometry.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LIMITWEN_NATIVE_UI_TESTS"] == "1"), .serialized) @MainActor
struct PopoverPresentationTests {
    @Test func cancellingAMenuDoesNotDisableDismissalWhenTheAppDeactivates() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let suite = "LimitwenDismissalTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(preview: true, defaults: defaults)
        let popover = NSPopover()
        let controller = StatusController(model: model, popover: popover)
        defer { popover.close() }
        try await Task.sleep(for: .milliseconds(300))
        controller.showInitial()
        try await Task.sleep(for: .milliseconds(300))
        try #require(popover.isShown)
        popover.animates = false
        let view = try #require(popover.contentViewController?.view)
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Cancel reset reminders", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Quit Limitwen", action: nil, keyEquivalent: "")
        let cancellation = MenuCancellation(menu)
        let timer = Timer(timeInterval: 0.15, target: cancellation, selector: #selector(MenuCancellation.cancel), userInfo: nil, repeats: false)
        RunLoop.main.add(timer, forMode: .eventTracking)
        menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.maxX - 20, y: 20), in: view)
        timer.invalidate()
        try #require(popover.isShown, "Cancelling the menu should leave the popover usable")
        // AppKit sends this event when the subsequent outside click activates
        // another app. Exercise the real lifecycle boundary after menu tracking.
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        #expect(!popover.isShown, "Outside activation after cancelling a menu must dismiss the popover")
        controller.showInitial()
        popover.animates = false
        #expect(popover.isShown, "The popover must remain reopenable")
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        #expect(!popover.isShown, "Dismissal must also work on subsequent presentations")
    }

    @Test func openingFromMenuBarKeepsTheEntirePopoverOnScreen() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let suite = "LimitwenPopoverTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(preview: true, defaults: defaults)
        model.notice = "Claude connected. Start or continue a Claude Code session to receive usage."
        let popover = RecordingPopover()
        let controller = StatusController(model: model, popover: popover)
        popover.animates = false
        popover.behavior = .applicationDefined
        defer { popover.close() }

        try await Task.sleep(for: .milliseconds(300))
        controller.showInitial()
        try await Task.sleep(for: .milliseconds(300))
        try expectVisibleContent(popover)

        let loaded = model.states
        model.states = [:]
        model.notice = nil
        controller.rebuild()
        try await Task.sleep(for: .milliseconds(300))
        try expectVisibleContent(popover)

        model.states = loaded
        model.notice = "Claude connected. Start or continue a Claude Code session to receive usage."
        controller.rebuild()
        try await Task.sleep(for: .milliseconds(300))
        try expectVisibleContent(popover)

        for provider in ProviderID.allCases.reversed() {
            controller.showInitial(provider: provider)
            try await Task.sleep(for: .milliseconds(300))
            #expect(model.selected == provider)
            try expectVisibleContent(popover)
        }
    }

    @Test func longConnectionMessagesStayWithinTheDisplay() async throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        let model = AppModel(preview: true)
        model.notice = String(repeating: "Connection details must remain readable without pushing controls off screen. ", count: 40)
        let popover = RecordingPopover()
        let controller = StatusController(model: model, popover: popover)
        defer { popover.close() }
        try await Task.sleep(for: .milliseconds(200))
        controller.showInitial()
        try await Task.sleep(for: .milliseconds(300))
        try expectVisibleContent(popover)
    }

    @Test func settingsUsesOnePanelAndReopensTheSameWindow() async throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        let model = AppModel(preview: true)
        let controller = StatusController(model: model)
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        controller.showSettings()
        try await Task.sleep(for: .milliseconds(200))
        let window = try #require(NSApp.windows.first { !before.contains(ObjectIdentifier($0)) && $0.styleMask.contains(.titled) })
        defer { window.close() }
        #expect(window.windowController != nil)
        #expect(!(window.contentViewController is NSTabViewController))
        #expect(window.toolbar == nil, "A single settings panel needs no tab toolbar")
        let content = try #require(window.contentViewController?.view)
        #expect(content.bounds.width >= content.fittingSize.width, "Settings must not clip its content")
        window.miniaturize(nil)
        controller.showSettings()
        try await Task.sleep(for: .milliseconds(200))
        #expect(!window.isMiniaturized)
        #expect(window.isVisible)
        window.close()
        model.showSettings()
        try await Task.sleep(for: .milliseconds(200))
        #expect(window.isVisible)
        #expect(NSApp.windows.filter { $0.title == "Limitwen Settings" && $0.isVisible }.count == 1)
    }

    @Test func escapeDismissesPopoverThroughResponderChain() async throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        let model = AppModel(preview: true)
        let popover = NSPopover()
        let controller = StatusController(model: model, popover: popover)
        defer { popover.close() }
        try await Task.sleep(for: .milliseconds(200))
        controller.showInitial()
        try await Task.sleep(for: .milliseconds(300))
        try #require(popover.isShown)
        popover.animates = false
        let window = try #require(popover.contentViewController?.view.window)
        #expect(window.canBecomeKey, "The native popover must support keyboard focus")
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        window.sendEvent(escape)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!popover.isShown)
    }

    @Test func customControlsDoNotStackNativeRectangularFocusRings() async throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        let model = AppModel(preview: true)
        let popover = NSPopover()
        let controller = StatusController(model: model, popover: popover)
        defer { popover.close() }
        controller.showInitial()
        try await Task.sleep(for: .milliseconds(300))
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let content = try #require(popover.contentViewController?.view)
        let pinViews = descendants(content).filter { $0.frame.size == NSSize(width: 20, height: 24) }
        // Borderless AppKit buttons retain an additional blue keyboard treatment
        // even with focusRingType=.none. Use SwiftUI's plain keyboard control.
        #expect(!pinViews.contains { $0 is NSButton }, "Pin must not retain borderless button focus chrome")
        // Plain SwiftUI key proxies are created lazily in popovers; exercise
        // Tab/Space in the running app rather than asserting an eager NSButton.
        controller.showSettings()
        try await Task.sleep(for: .milliseconds(300))
        let settings = try #require(NSApp.windows.first { $0.title == "Limitwen Settings" })
        defer { settings.close() }
        let settingsView = try #require(settings.contentView)
        let cardViews = descendants(settingsView).filter { $0.frame.width > 150 && $0.frame.width < 260 && $0.frame.height > 100 && $0.frame.height < 200 }
        #expect(cardViews.isEmpty, "Rings are fixed; Settings must not restore the removed meter-choice cards")
    }

    @Test func repinnedStatusItemTracksItsOwnAppearanceWithoutPolling() async throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        let model = AppModel(preview: true)
        let popover = RecordingPopover()
        let controller = StatusController(model: model, popover: popover)
        defer { popover.close() }
        model.change { $0.pinned = [.codex] }
        model.change { $0.pinned = [.claude, .codex] }
        controller.showInitial(provider: .claude)
        try await Task.sleep(for: .milliseconds(200))
        let button = try #require(popover.anchorView as? NSStatusBarButton)
        button.appearance = NSAppearance(named: .aqua)
        controller.rebuild()
        let lightImage = try #require(button.image)
        button.appearance = NSAppearance(named: .darkAqua)
        try await Task.sleep(for: .milliseconds(100))
        #expect(button.image !== lightImage, "Status appearance changes must redraw immediately, without polling")
        let darkImage = try #require(button.image)
        #expect(darkImage.tiffRepresentation != lightImage.tiffRepresentation, "Appearance must change the rendered pixels, not only the image object")
        button.appearance = NSAppearance(named: .aqua)
        try await Task.sleep(for: .milliseconds(100))
        #expect(button.image !== darkImage)
    }

    private func expectVisibleContent(_ popover: RecordingPopover) throws {
        try #require(popover.isShown)
        let window = try #require(popover.contentViewController?.view.window)
        let view = try #require(popover.contentViewController?.view)
        let frame = window.frame
        let content = window.convertToScreen(view.convert(view.bounds, to: nil))
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        // The native arrow can meet the status button inside the menu bar. The content
        // must remain inside the usable display and the whole window below the button.
        #expect(visibleFrames.contains { $0.insetBy(dx: -1, dy: -1).contains(content) },
                "Popover content must fit: content=\(content), window=\(frame), screens=\(visibleFrames), show=\(popover.presentation)")
        #expect(frame.maxY <= popover.anchor.minY + 1, "The popover must open below its menu bar item: window=\(frame), anchor=\(popover.anchor)")
        #expect(NSScreen.screens.contains { $0.frame.insetBy(dx: -1, dy: -1).contains(frame) })
    }
}

@MainActor private final class MenuCancellation: NSObject {
    let menu: NSMenu
    init(_ menu: NSMenu) { self.menu = menu }
    @objc func cancel() { menu.cancelTracking() }
}

@MainActor
private final class RecordingPopover: NSPopover {
    weak var anchorView: NSView?
    var presentation = ""
    var anchor: NSRect = .zero
    override func show(relativeTo positioningRect: NSRect, of positioningView: NSView, preferredEdge: NSRectEdge) {
        anchorView = positioningView
        let size = contentSize
        anchor = positioningView.window?.convertToScreen(positioningView.convert(positioningRect, to: nil)) ?? .zero
        super.show(relativeTo: positioningRect, of: positioningView, preferredEdge: preferredEdge)
        presentation = "content before=\(size), window initially=\(contentViewController?.view.window?.frame ?? .zero), anchor=\(anchor), flipped=\(positioningView.isFlipped)"
    }
}
