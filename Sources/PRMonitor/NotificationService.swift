import AppKit
import Foundation
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestPermission() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func deliveryWarning() async -> String? {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus != .authorized || settings.alertSetting != .enabled {
            return "PR Monitor desktop notifications are disabled in macOS settings."
        }
        if settings.scheduledDeliverySetting == .enabled {
            return "macOS is summarizing PR Monitor notifications. Turn off Summarize notifications for immediate alerts."
        }
        return nil
    }

    func send(_ event: MonitorEvent) async throws {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            throw NotificationError.permissionDenied
        }
        let content = UNMutableNotificationContent()
        content.title = event.kind.title
        content.body = event.body
        content.sound = .default
        content.userInfo = ["url": event.url.absoluteString]
        let request = UNNotificationRequest(
            identifier: event.id.uuidString,
            content: content,
            trigger: nil
        )
        try await center.add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let rawURL = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: rawURL) {
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        }
        completionHandler()
    }
}

enum NotificationError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        "Notifications are disabled for PR Monitor in macOS System Settings"
    }
}
