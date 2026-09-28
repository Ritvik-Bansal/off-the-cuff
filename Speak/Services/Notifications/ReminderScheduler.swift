import Foundation
import UserNotifications

/// Schedules the daily "time to practice" local notification.
enum ReminderScheduler {
    private static let identifier = "daily-practice-reminder"

    /// Requests permission if needed. Returns whether notifications are allowed.
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            return false
        }
    }

    /// Replaces any existing reminder with one repeating daily at hour:minute.
    static func schedule(hour: Int, minute: Int) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "Your 1-minute speech is waiting"
        content.body = messages.randomElement() ?? "A fresh prompt is ready. Talk it out for 60 seconds."
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    private static let messages = [
        "A fresh prompt is ready. Talk it out for 60 seconds.",
        "Keep your streak alive — one minute, one topic.",
        "Fewer ums start with one more rep. Ready?",
        "Interview-ready is built daily. Your prompt is waiting.",
    ]
}
