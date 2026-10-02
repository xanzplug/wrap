import Foundation
import UserNotifications

/// Notifications before each scheduled shoot:
/// the evening before (6 PM) and 2 hours before it starts.
enum ShootReminders {
    private static let prefix = "shoot-"
    /// The on/off switch in Settings.
    static let enabledKey = "shootRemindersOn"

    /// One reminder, worked out on the main thread before scheduling.
    private struct Reminder {
        let id: String
        let date: Date
        let title: String
        let body: String
    }

    /// Replace all shoot reminders with ones for these projects.
    static func schedule(for projects: [Project]) {
        let enabled = UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
        let reminders = enabled ? makeReminders(for: projects) : []
        let center = UNUserNotificationCenter.current()
        if !reminders.isEmpty {
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        // Clear the old ones first, then add the new ones, in that order.
        Task {
            let pending = await center.pendingNotificationRequests()
            let old = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for reminder in reminders {
                await add(reminder)
            }
        }
    }

    private static func makeReminders(for projects: [Project]) -> [Reminder] {
        let calendar = Calendar.current
        let now = Date()
        var result: [Reminder] = []

        for project in projects {
            guard let shoot = project.upcomingShoot else { continue }
            let left = project.shots.filter { !$0.isDone }.count
            let shotsLine = left == 0 ? "Shot list is empty." : "\(left) shot\(left == 1 ? "" : "s") on the list."
            let time = shoot.formatted(date: .omitted, time: .shortened)
            let id = prefix + project.remoteID.uuidString

            // The evening before, at 6 PM.
            if let dayBefore = calendar.date(byAdding: .day, value: -1, to: shoot),
               let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: dayBefore),
               evening > now {
                result.append(Reminder(id: id + "-eve", date: evening,
                                       title: "Shoot tomorrow: \(project.displayName)",
                                       body: "Starts at \(time). \(shotsLine)"))
            }
            // Two hours before.
            let soon = shoot.addingTimeInterval(-2 * 3600)
            if soon > now {
                result.append(Reminder(id: id + "-soon", date: soon,
                                       title: "Shoot in 2 hours: \(project.displayName)",
                                       body: "Starts at \(time). \(shotsLine)"))
            }
        }
        return result
    }

    private static func add(_ reminder: Reminder) async {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
    }

    /// "Today", "Tomorrow", "In 5 days", or a date further out.
    static func relativeDay(_ date: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2...6: return "In \(days) days"
        default: return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
    }
}
