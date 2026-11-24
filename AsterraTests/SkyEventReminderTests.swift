import Foundation
import Testing
@testable import Asterra

@MainActor
struct SkyEventReminderTests {
    private func event(start: Date = Date(timeIntervalSince1970: 2_000_000_000)) -> SkyEvent {
        SkyEvent(id: "reminder-test", kind: .object, title: "Uranus at Opposition",
                 start: start, end: start.addingTimeInterval(3_600),
                 headerDate: "", detailDate: "", viewingTime: "", direction: "North",
                 about: "", tips: "", artwork: .init(asset: "", size: 0, x: 0, y: 0),
                 target: .body("Uranus"))
    }

    private func isolatedDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "SkyEventReminderTests.\(UUID().uuidString)"))
    }

    @Test func successfulSavePersistsSystemIdentifierAndRestoresBell() async throws {
        let defaults = try isolatedDefaults()
        let service = ReminderStub()
        let store = SkyEventStore(defaults: defaults, reminderService: service)
        let event = event()
        try await store.setReminder(true, for: event)
        #expect(store.reminders.contains(event.id))
        #expect(service.savedIDs == [event.id])
        #expect(defaults.stringArray(forKey: "skyEventReminders") == [event.id])
        #expect(defaults.dictionary(forKey: "skyEventReminderIdentifiers") as? [String: String]
                == [event.id: "system-reminder"])
        let restored = SkyEventStore(defaults: defaults, reminderService: service)
        #expect(restored.reminders.contains(event.id))
        try await restored.setReminder(true, for: event)
        #expect(service.existingIdentifiers.last == "system-reminder")
        #expect(!store.isUpdatingReminder)
    }

    @Test func deniedOrFailedSaveDoesNotEnableBell() async throws {
        let defaults = try isolatedDefaults()
        let service = ReminderStub()
        service.shouldFail = true
        let store = SkyEventStore(defaults: defaults, reminderService: service)
        await #expect(throws: SkyEventReminderError.self) {
            try await store.setReminder(true, for: event())
        }
        #expect(store.reminders.isEmpty)
        #expect(defaults.dictionary(forKey: "skyEventReminderIdentifiers") == nil)
        #expect(!store.isUpdatingReminder)
    }

    @Test func removalDeletesOnlySavedReminderAndPersistsOffState() async throws {
        let defaults = try isolatedDefaults()
        let service = ReminderStub()
        let event = event()
        defaults.set([event.id: "owned-reminder", "another-event": "other-reminder"],
                     forKey: "skyEventReminderIdentifiers")
        let store = SkyEventStore(defaults: defaults, reminderService: service)
        try await store.setReminder(false, for: event)
        #expect(service.removedIdentifiers == ["owned-reminder"])
        #expect(store.reminders == ["another-event"])
        #expect(SkyEventStore(defaults: defaults, reminderService: service).reminders == ["another-event"])
    }

    @Test func failedRemovalKeepsBellAndIdentifierForRetry() async throws {
        let defaults = try isolatedDefaults()
        let service = ReminderStub()
        service.shouldFail = true
        let event = event()
        defaults.set([event.id: "owned-reminder"], forKey: "skyEventReminderIdentifiers")
        let store = SkyEventStore(defaults: defaults, reminderService: service)
        await #expect(throws: SkyEventReminderError.self) {
            try await store.setReminder(false, for: event)
        }
        #expect(store.reminders.contains(event.id))
        #expect(defaults.dictionary(forKey: "skyEventReminderIdentifiers") as? [String: String]
                == [event.id: "owned-reminder"])
        #expect(!store.isUpdatingReminder)
    }

    @Test func legacyFlagsDoNotPretendSystemReminderWasSaved() throws {
        let defaults = try isolatedDefaults()
        defaults.set(["legacy-event"], forKey: "skyEventReminders")
        defaults.set(["collected-event"], forKey: "collectedSkyEvents")
        let store = SkyEventStore(defaults: defaults, reminderService: ReminderStub())
        #expect(store.reminders.isEmpty)
        #expect(store.collected == ["collected-event"])
    }

    @Test func endedEventIsRejectedBeforeRequestingSystemAccess() async {
        let service = SkyEventReminderService()
        await #expect(throws: SkyEventReminderError.ended) {
            try await service.save(event(start: .distantPast), existingIdentifier: nil, now: .now)
        }
    }
}

@MainActor
private final class ReminderStub: SkyEventReminderScheduling {
    var shouldFail = false
    var savedIDs: [String] = []
    var existingIdentifiers: [String?] = []
    var removedIdentifiers: [String] = []

    func save(_ event: SkyEvent, existingIdentifier: String?, now: Date) async throws -> String {
        if shouldFail { throw SkyEventReminderError.accessDenied }
        savedIDs.append(event.id)
        existingIdentifiers.append(existingIdentifier)
        return existingIdentifier ?? "system-reminder"
    }

    func remove(identifier: String) async throws {
        if shouldFail { throw SkyEventReminderError.accessDenied }
        removedIdentifiers.append(identifier)
    }
}
