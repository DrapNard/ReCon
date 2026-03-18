import Foundation
import UserNotifications

final class NotificationService {
    func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    func showUnreadMessage(sender: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = sender
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "msg.\(sender).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
