import EventKit
import Foundation

@MainActor
protocol SkyEventReminderScheduling {
    func save(_ event: SkyEvent, existingIdentifier: String?, now: Date) async throws -> String
    func remove(identifier: String) async throws
}

enum SkyEventReminderError: LocalizedError {
    case accessDenied, noList, ended, busy

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Allow Asterra to access Reminders in Settings to add or remove this reminder."
        case .noList:
            "No writable reminder list is available. Create a list in the Reminders app, then try again."
        case .ended:
            "This event's viewing window has ended."
        case .busy:
            "Another reminder is being updated. Please try again in a moment."
        }
    }
}

/// Only identifiers saved by Asterra are used to update or remove reminders.
@MainActor
final class SkyEventReminderService: SkyEventReminderScheduling {
    private let eventStore = EKEventStore()

    private func authorize() async throws {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            return
        case .notDetermined:
            guard try await eventStore.requestFullAccessToReminders() else {
                throw SkyEventReminderError.accessDenied
            }
        default:
            throw SkyEventReminderError.accessDenied
        }
    }

    func save(_ event: SkyEvent, existingIdentifier: String?, now: Date) async throws -> String {
        guard event.end > now else { throw SkyEventReminderError.ended }
        try await authorize()
        let existing = existingIdentifier.flatMap { eventStore.calendarItem(withIdentifier: $0) as? EKReminder }
        let reminder = existing ?? EKReminder(eventStore: eventStore)
        if existing == nil {
            guard let list = eventStore.defaultCalendarForNewReminders(),
                  list.allowsContentModifications else { throw SkyEventReminderError.noList }
            reminder.calendar = list
        }
        // An ongoing event gets an immediate reminder rather than an alarm in the past.
        let alarmDate = max(event.start, now.addingTimeInterval(1))
        reminder.title = event.title
        reminder.notes = """
        Asterra Sky Event
        Viewing window: \(event.collectWindow)
        Direction: \(event.direction)

        \(event.about)

        Viewing tips: \(event.tips)
        """
        reminder.timeZone = .current
        reminder.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .timeZone], from: alarmDate)
        reminder.alarms = [EKAlarm(absoluteDate: alarmDate)]
        reminder.isCompleted = false
        try eventStore.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    func remove(identifier: String) async throws {
        try await authorize()
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else { return }
        try eventStore.remove(reminder, commit: true)
    }
}
