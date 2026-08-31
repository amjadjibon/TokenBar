import Foundation
import OSLog
import UserNotifications

/// Delivers the notices `NotificationPlanner` decides on.
@MainActor
final class NotificationManager {
    private let center: UNUserNotificationCenter
    private let logger = Logger(subsystem: TokenBarLog.subsystem, category: "notifications")

    private var planner = NotificationPlanner()
    private var authorized = false

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async {
        do {
            authorized = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            logger.error("Notification authorization failed")
            authorized = false
        }
    }

    func evaluate(usage: ProviderUsage, previous: ProviderUsage?, settings: AppSettings) {
        for notice in planner.plan(usage: usage, previous: previous, settings: settings) {
            post(notice)
        }
    }

    private func post(_ notice: Notice) {
        guard authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body

        center.add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
        logger.info("Posted notification: \(notice.title, privacy: .public)")
    }
}
