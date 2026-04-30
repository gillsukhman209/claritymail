import Foundation
import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            // Permission failures should not block email loading.
        }
    }

    func notifyNewEmail(_ email: Email) async {
        let content = UNMutableNotificationContent()
        content.title = email.displayNameForNotification
        content.subtitle = email.subject
        content.body = email.snippet
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "email-\(email.accountId ?? "account")-\(email.id)",
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

private extension Email {
    var displayNameForNotification: String {
        if let start = sender.firstIndex(of: "<") {
            return sender[..<start].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return sender
    }
}
