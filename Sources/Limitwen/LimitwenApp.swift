import AppKit
import SwiftUI
import UserNotifications
import LimitwenCore

@main
enum LimitwenApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        if let index = CommandLine.arguments.firstIndex(of: "--render-previews"), CommandLine.arguments.indices.contains(index + 1) {
            do { try PreviewRenderer.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
            catch { fputs("Preview rendering failed.\n", stderr) }
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var model: AppModel?
    private var status: StatusController?
    private var wakeObserver: NSObjectProtocol?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel(preview: CommandLine.arguments.contains("--preview"))
        self.model = model
        UNUserNotificationCenter.current().delegate = self
        status = StatusController(model: model)
        let menu = NSMenu()
        let root = NSMenuItem()
        let appMenu = NSMenu(title: "Limitwen")
        let preferences = appMenu.addItem(withTitle: "Settings…", action: #selector(showPreferences), keyEquivalent: ",")
        preferences.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Limitwen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        root.submenu = appMenu; menu.addItem(root); NSApp.mainMenu = menu
        model.start()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak model] _ in
            Task { @MainActor in await model?.refresh(force: true) }
        }
        if CommandLine.arguments.contains("--show") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                self?.status?.showInitial()
            }
        }
    }
    @objc private func showPreferences() { model?.showSettings() }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let parts = response.notification.request.identifier.split(separator: ":")
        let provider = parts.count > 1 ? ProviderID(rawValue: String(parts[1])) : nil
        await MainActor.run { self.status?.showInitial(provider: provider) }
        await self.model?.refresh(force: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { status?.showInitial(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
}
