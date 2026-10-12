import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class ProgrammeReminderManager {
    static let shared = ProgrammeReminderManager()

    private(set) var reminderIDs: Set<UUID> = []
    private init() {}

    func hasReminder(for program: EPGProgram) -> Bool { reminderIDs.contains(program.id) }

    func toggle(program: EPGProgram, channel: Channel) async {
        let center = UNUserNotificationCenter.current()
        if reminderIDs.remove(program.id) != nil {
            center.removePendingNotificationRequests(withIdentifiers: [program.id.uuidString])
            return
        }

        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        } else if settings.authorizationStatus != .authorized && settings.authorizationStatus != .provisional {
            return
        }

        let fireDate = max(Date().addingTimeInterval(1), program.startTime.addingTimeInterval(-5 * 60))
        guard fireDate < program.endTime else { return }
        let content = UNMutableNotificationContent()
        content.title = program.title
        content.subtitle = channel.uniformName
        content.body = "Starts in 5 minutes"
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let request = UNNotificationRequest(
            identifier: program.id.uuidString,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        do {
            try await center.add(request)
            reminderIDs.insert(program.id)
        } catch { }
    }
}
