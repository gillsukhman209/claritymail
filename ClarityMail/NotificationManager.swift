import Foundation
import UserNotifications
#if os(iOS)
import UIKit
#endif

extension Notification.Name {
    static let openMorningBrief = Notification.Name("openMorningBrief")
    static let openEmailFromNotification = Notification.Name("openEmailFromNotification")
    static let emailSyncNeeded = Notification.Name("emailSyncNeeded")
}

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async {
        do {
            let isAllowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            if isAllowed {
                await MainActor.run {
                    registerForRemoteNotifications()
                }
            }
        } catch {
            // Permission failures should not block email loading.
        }
    }

    func registerDeviceToken(_ deviceToken: Data) async {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()

        do {
            try await APIClient().registerDeviceToken(
                token: token,
                platform: "ios",
                environment: Self.apnsEnvironment
            )
        } catch {
            // Token registration will retry next app launch.
        }
    }

    func notifyNewEmail(_ email: Email) async {
        let content = UNMutableNotificationContent()
        content.title = email.displayNameForNotification
        content.subtitle = email.subject
        content.body = email.snippet
        content.sound = .default
        content.userInfo = [
            "route": "email",
            "emailId": email.id,
            "accountId": email.accountId ?? ""
        ]

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

    func setBadgeCount(_ count: Int) async {
        if #available(iOS 16.0, macOS 13.0, *) {
            try? await UNUserNotificationCenter.current().setBadgeCount(max(count, 0))
        } else {
            await MainActor.run {
                #if os(iOS)
                UIApplication.shared.applicationIconBadgeNumber = max(count, 0)
                #endif
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let userInfo = notification.request.content.userInfo
        if (userInfo["route"] as? String) == "email" {
            await MainActor.run {
                NotificationCenter.default.post(name: .emailSyncNeeded, object: nil)
            }
        }

        return [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let route = userInfo["route"] as? String

        if route == "morningBrief", let briefId = userInfo["briefId"] as? String {
            UserDefaults.standard.set(briefId, forKey: "pendingMorningBriefId")

            await MainActor.run {
                NotificationCenter.default.post(name: .openMorningBrief, object: nil)
            }
            return
        }

        if route == "email", let emailId = userInfo["emailId"] as? String {
            UserDefaults.standard.set(emailId, forKey: "pendingNotificationEmailId")
            if let accountId = userInfo["accountId"] as? String, !accountId.isEmpty {
                UserDefaults.standard.set(accountId, forKey: "pendingNotificationAccountId")
            }

            await MainActor.run {
                NotificationCenter.default.post(name: .openEmailFromNotification, object: nil)
            }
        }
    }
}

private extension NotificationManager {
    static var apnsEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    @MainActor
    func registerForRemoteNotifications() {
        #if os(iOS)
        UIApplication.shared.registerForRemoteNotifications()
        #endif
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
