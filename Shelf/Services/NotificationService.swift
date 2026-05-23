import Foundation
import UserNotifications

struct NotificationService {
    static let shared = NotificationService()
    private init() {}

    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func scheduleFollowUp(for purchase: Purchase) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "How was it?"
        content.body = "Did you finish \"\(purchase.bookTitle)\"?"
        content.userInfo = ["purchaseId": purchase.id.uuidString]
        content.sound = .default

        // 7 days after purchase
        let fireDate = purchase.purchaseDate.addingTimeInterval(7 * 24 * 3600)
        let interval = max(fireDate.timeIntervalSinceNow, 60) // minimum 60s for testing
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: "followup-\(purchase.id.uuidString)",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    func cancelFollowUp(for purchaseId: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["followup-\(purchaseId.uuidString)"])
    }
}
