import Foundation
import UserNotifications

struct LimitNotification: Sendable {
    let id: String
    let title: String
    let body: String
    var date: Date? = nil
}

/// Keeps system authorization and delivery outside the app's quota policy.
@MainActor
protocol NotificationDelivery {
    func authorize() async throws -> Bool
    func schedule(_ notification: LimitNotification) async throws
    func cancel(_ identifiers: [String])
}

@MainActor
struct SystemNotifications: NotificationDelivery {
    func authorize() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
    // Construct and submit framework objects outside UI isolation; older SDKs
    // do not mark UNNotificationRequest as Sendable.
    nonisolated func schedule(_ notification: LimitNotification) async throws {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        let trigger = notification.date.map {
            UNTimeIntervalNotificationTrigger(timeInterval: max(1, $0.timeIntervalSinceNow), repeats: false)
        }
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger))
    }
    func cancel(_ identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
