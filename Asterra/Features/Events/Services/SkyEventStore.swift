import Foundation
import Observation

/// Local state for event notifications and events the user has collected.
@Observable
final class SkyEventStore {
    private let defaults = UserDefaults.standard
    /// Every event notifies by default; the bell turns it off for the events listed here.
    private(set) var muted: Set<String>
    private(set) var collected: Set<String>

    init() {
        muted = Set(defaults.stringArray(forKey: "mutedSkyEvents") ?? [])
        collected = Set(defaults.stringArray(forKey: "collectedSkyEvents") ?? [])
    }
    func isReminderOn(_ event: SkyEvent) -> Bool { !muted.contains(event.id) }
    func toggleReminder(_ event: SkyEvent) {
        if muted.contains(event.id) {
            muted.remove(event.id)
        } else {
            muted.insert(event.id)
        }
        defaults.set(Array(muted), forKey: "mutedSkyEvents")
    }
    func collect(_ event: SkyEvent) {
        collected.insert(event.id)
        defaults.set(Array(collected), forKey: "collectedSkyEvents")
    }
}
