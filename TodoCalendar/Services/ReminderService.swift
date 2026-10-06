import Foundation
import UserNotifications

actor ReminderService {
    static let shared = ReminderService()
    private let center = UNUserNotificationCenter.current()

    func requestPermission() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func synchronize(_ items: [TodoItem]) async throws {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        try Task.checkCancellation()
        // Keep the nearest reminders within the system's pending-notification budget.
        let now = Date.now
        let interval = DateInterval(start: now, end: Calendar.current.date(byAdding: .year, value: 2, to: now)!)
        let future = items.flatMap { $0.occurrences(in: interval) }.filter { ($0.reminderDate ?? .distantPast) > now }
            .sorted { $0.reminderDate! < $1.reminderDate! }.prefix(60)
        center.removeAllPendingNotificationRequests()
        for item in future {
            try Task.checkCancellation()
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.notes.isEmpty ? "예정된 투두를 확인해 주세요." : item.notes
            content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.reminderDate!)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try await center.add(UNNotificationRequest(identifier: item.occurrenceID, content: content, trigger: trigger))
        }
    }
}
