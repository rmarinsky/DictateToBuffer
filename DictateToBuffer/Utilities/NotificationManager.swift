import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()

    private init() {
        // Permission is now requested by PermissionManager at startup
    }

    func showSuccess(text: String) {
        let content = UNMutableNotificationContent()
        content.title = "Transcription Complete"
        content.body = text.prefix(100) + (text.count > 100 ? "..." : "")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    func showError(message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Transcription Failed"
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    func showWarning(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
