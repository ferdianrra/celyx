import Foundation
import Observation

/// Local state for reminders and events the user has collected.
@Observable
final class SkyEventStore {
    private let defaults = UserDefaults.standard
    private(set) var reminders: Set<String>
    private(set) var collected: Set<String>

    init() {
        reminders = Set(
            defaults.stringArray(forKey: "skyEventReminders") ?? [])
        collected = Set(defaults.stringArray(forKey: "collectedSkyEvents") ?? [])
    }
    func toggleReminder(_ event: SkyEvent) {
        if reminders.contains(event.id) {
            reminders.remove(event.id)
        } else {
            reminders.insert(event.id)
        }
        defaults.set(Array(reminders), forKey: "skyEventReminders")
    }
    func collect(_ event: SkyEvent) {
        collected.insert(event.id)
        defaults.set(Array(collected), forKey: "collectedSkyEvents")
    }
}
