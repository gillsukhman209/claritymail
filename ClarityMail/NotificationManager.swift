import Foundation
import UserNotifications

extension Notification.Name {
    static let openMorningBrief = Notification.Name("openMorningBrief")
}

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

    func notifyMorningBrief(_ brief: MorningBrief) async {
        let content = UNMutableNotificationContent()
        content.title = "Morning Brief"
        content.body = brief.notificationPreview
        content.sound = .default
        content.userInfo = [
            "route": "morningBrief",
            "briefId": brief.id
        ]

        let request = UNNotificationRequest(
            identifier: "morning-brief-\(brief.id)",
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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard userInfo["route"] as? String == "morningBrief" else { return }

        if let briefId = userInfo["briefId"] as? String {
            UserDefaults.standard.set(briefId, forKey: "pendingMorningBriefId")
        }

        await MainActor.run {
            NotificationCenter.default.post(name: .openMorningBrief, object: nil)
        }
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

private extension MorningBrief {
    var notificationPreview: String {
        let important = summary.important.first ?? summary.deadlines.first
        let action = summary.needsAction.first
        let fyiCount = summary.fyi.count

        var parts: [String] = []
        if let important {
            parts.append("Important: \(important.shortNotificationText)")
        }
        if let action {
            parts.append("Action: \(action.shortNotificationText)")
        }
        if fyiCount > 0 {
            parts.append("FYI: \(fyiCount) useful \(fyiCount == 1 ? "update" : "updates").")
        }
        if parts.isEmpty {
            parts.append("\(totalUnread) unread scanned, \(ignoredCount) low-priority ignored.")
        }

        return parts.joined(separator: " ")
    }
}

private extension MorningBriefItem {
    var shortNotificationText: String {
        let text = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = text.count > 72 ? String(text.prefix(69)).trimmingCharacters(in: .whitespacesAndNewlines) + "..." : text
        return trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") ? trimmed : "\(trimmed)."
    }
}
