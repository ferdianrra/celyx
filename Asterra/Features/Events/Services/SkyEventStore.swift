import Foundation
import Observation

/// Local collection state and successfully saved iPhone reminders.
@MainActor
@Observable
final class SkyEventStore {
    private let defaults: UserDefaults
    private let reminderService: any SkyEventReminderScheduling
    private var reminderIdentifiers: [String: String]
    private(set) var reminders: Set<String>
    private(set) var collected: Set<String>
    private(set) var isUpdatingReminder = false

    init(defaults: UserDefaults = .standard, reminderService: (any SkyEventReminderScheduling)? = nil) {
        self.defaults = defaults
        self.reminderService = reminderService ?? SkyEventReminderService()
        let identifiers = defaults.dictionary(forKey: "skyEventReminderIdentifiers") as? [String: String] ?? [:]
        reminderIdentifiers = identifiers
        // Legacy bell flags never created real reminders. Keep their persisted key,
        // but require a successful system save before showing a bell as enabled.
        reminders = Set(identifiers.keys)
        collected = Set(defaults.stringArray(forKey: "collectedSkyEvents") ?? [])
    }

    func setReminder(_ enabled: Bool, for event: SkyEvent, now: Date = .now) async throws {
        guard !isUpdatingReminder else { throw SkyEventReminderError.busy }
        isUpdatingReminder = true
        defer { isUpdatingReminder = false }
        if enabled {
            let identifier = try await reminderService.save(
                event, existingIdentifier: reminderIdentifiers[event.id], now: now)
            reminderIdentifiers[event.id] = identifier
            reminders.insert(event.id)
        } else {
            if let identifier = reminderIdentifiers[event.id] {
                try await reminderService.remove(identifier: identifier)
            }
            reminderIdentifiers.removeValue(forKey: event.id)
            reminders.remove(event.id)
        }
        defaults.set(reminderIdentifiers, forKey: "skyEventReminderIdentifiers")
        defaults.set(Array(reminders), forKey: "skyEventReminders")
    }

    func collect(_ event: SkyEvent) {
        collected.insert(event.id)
        defaults.set(Array(collected), forKey: "collectedSkyEvents")
    }
}
