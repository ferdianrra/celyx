import Foundation
import Observation

/// Local reminders and legacy collected event IDs. Camera observations are stored with their photos.
@Observable
final class SkyEventStore {
    private let defaults: UserDefaults
    private(set) var reminders: Set<String>
    private(set) var collected: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
}
