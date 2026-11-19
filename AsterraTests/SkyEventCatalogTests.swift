import CoreGraphics
import Foundation
import Testing
import simd

@testable import Asterra

@MainActor
struct SkyEventCatalogTests {
    private let november2026 = DateInterval(
        start: Date(timeIntervalSince1970: 1_793_491_200),  // 2026-11-01 UTC
        duration: 30 * 86400)

    @Test func eventsAreComputedForTheObserverAndAreStable() {
        let catalog = SkyEventCatalog()
        catalog.update(location: ObserverLocation(latitude: -6.1754, longitude: 106.8272))
        let events = catalog.events(in: november2026)
        #expect(events.contains { $0.kind == .moon && $0.title.contains("Moon") })
        #expect(events.contains { $0.id.hasPrefix("leonids-") })
        #expect(events.allSatisfy { $0.start < $0.end && $0.end.timeIntervalSince($0.start) < 24 * 3600 })
        #expect(Set(events.map(\.id)).count == events.count)
        // Cached and deterministic.
        #expect(catalog.events(in: november2026).map(\.id) == events.map(\.id))
    }

    @Test func viewingWindowAndDirectionFollowTheObserver() throws {
        let jakarta = SkyEventCatalog()
        jakarta.update(location: ObserverLocation(latitude: -6.1754, longitude: 106.8272))
        let newYork = SkyEventCatalog()
        newYork.update(location: ObserverLocation(latitude: 40.7128, longitude: -74.0060))
        let a = try #require(jakarta.events(in: november2026).first { $0.id.hasPrefix("full-moon-") })
        let b = try #require(newYork.events(in: november2026).first { $0.id.hasPrefix("full-moon-") })
        // Same global event, different local viewing window.
        #expect(a.id == b.id)
        #expect(a.start != b.start)
    }

    @Test func eventsCanOnlyBeCollectedInsideTheirWindowAndPointAtTheTarget() throws {
        let location = ObserverLocation(latitude: -6.1754, longitude: 106.8272)
        let catalog = SkyEventCatalog()
        catalog.update(location: location)
        let event = try #require(catalog.events(in: november2026).first { $0.id.hasPrefix("mars-jupiter-") })
        #expect(!event.isOpen(at: event.start.addingTimeInterval(-60)))
        #expect(event.isOpen(at: event.start.addingTimeInterval(60)))
        #expect(!event.isOpen(at: event.end.addingTimeInterval(60)))
        #expect(event.hasEnded(at: event.end.addingTimeInterval(60)))
        // During the window the guide points above the horizon, in the direction shown on the card.
        let middle = event.start.addingTimeInterval(event.end.timeIntervalSince(event.start) / 2)
        let sky = SkyEventCatalog.horizon(of: event.target, at: middle, location: location)
        #expect(sky.altitude > 0)
        #expect(abs(simd_length(sky.direction) - 1) < 1e-6)
        let guidance = SkyEventCatalog.guidance(of: event.target, at: middle, location: location)
        #expect(guidance.members.map(\.name) == ["Mars", "Jupiter"])
        #expect(guidance.position.direction == sky.direction)
    }

    @Test func monthListSeparatesEventsAtTheEndOfTheirViewingWindow() throws {
        let catalog = SkyEventCatalog()
        catalog.update(location: ObserverLocation(latitude: -6.1754, longitude: 106.8272))
        let events = catalog.events(in: november2026)
        let event = try #require(events.first { november2026.contains($0.end) })
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let model = SkyCalendarViewModel(events: events, calendar: calendar, now: { event.end })
        #expect(model.listSections(at: event.end).current.contains(event))
        let sections = model.listSections(at: event.end.addingTimeInterval(1))
        #expect(!sections.current.contains(event))
        #expect(sections.past.contains(event))
        #expect(sections.current.map(\.start) == sections.current.map(\.start).sorted())
        #expect(sections.past.map(\.end) == sections.past.map(\.end).sorted(by: >))
        #expect(model.events(on: calendar.startOfDay(for: event.start)).contains(event))
        model.filters = [event.kind]
        #expect(model.listSections(at: event.end.addingTimeInterval(1)).past.allSatisfy { $0.kind == event.kind })
    }

    @Test func eventCompletionPersistsOnlyOnceInsideTheViewingWindow() throws {
        let catalog = SkyEventCatalog()
        catalog.update(location: ObserverLocation(latitude: -6.1754, longitude: 106.8272))
        let event = try #require(catalog.events(in: november2026).first)
        let suite = "SkyEventCatalogTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = HomeViewModel(defaults: defaults)
        let location = AppPreviewData.location
        let photo = AppPreviewData.albumPhoto
        #expect(throws: CocoaError.self) {
            try model.saveEventObservation(event, image: photo, date: event.start.addingTimeInterval(-1), location: location)
        }
        #expect(throws: CocoaError.self) {
            try model.saveEventObservation(event, image: photo, date: event.end.addingTimeInterval(1), location: location)
        }
        let record = try model.saveEventObservation(event, image: photo, date: event.start, location: location)
        defer { model.deleteCollected(id: record.id) }
        #expect(throws: CocoaError.self) {
            try model.saveEventObservation(event, image: photo, date: event.end, location: location)
        }
        #expect(HomeViewModel(defaults: defaults).hasEventCapture(event))
    }

    @Test func eventAimRequiresAVisibleTargetNearTheReticle() {
        var guide = EventCameraGuide(point: .zero, arrow: .zero, separation: 8, azimuth: 90, altitude: 12)
        #expect(guide.isAimed)
        guide.separation = 9
        #expect(!guide.isAimed)
        guide.separation = 3
        guide.point = nil
        #expect(!guide.isAimed)
        guide.point = .zero
        guide.altitude = -1
        #expect(!guide.isAimed)
    }

    @Test func conjunctionRequiresBothMembersInThePreview() {
        var guide = EventCameraGuide(point: CGPoint(x: 100, y: 150), arrow: .zero, separation: 0, azimuth: 45, altitude: 35,
            members: [.init(name: "Moon", point: CGPoint(x: 80, y: 150)), .init(name: "Jupiter", point: nil)])
        #expect(guide.aimsAtCenter)
        #expect(!guide.isAimed)
        guide.members[1] = .init(name: "Jupiter", point: CGPoint(x: 120, y: 150))
        #expect(guide.isAimed)
    }

    #if DEBUG
    @Test func demoConjunctionUsesTwoDistinctTargetsAndItsOwnCollectionEntry() {
        let now = Date()
        let event = SkyEvent.demoConjunction(at: now)
        let sky = SkyEventCatalog.guidance(of: event.target, at: now, location: AppPreviewData.location)
        #expect(event.isDemo && event.isOpen(at: now))
        #expect(event.collectionID != SkyEvent.demo(at: now).collectionID)
        #expect(sky.members.map(\.name) == ["Moon", "Jupiter"])
        #expect(sky.members.map { $0.position.altitude } == [35, 35])
        #expect(sky.members.first?.position.direction != sky.members.last?.position.direction)
        #expect(abs(sky.position.azimuth - 45) < 1e-6)
    }

    @Test func demoEventSavesRepeatablePhotosAndNotesAsOneGardenObject() throws {
        let now = Date()
        let event = SkyEvent.demo(at: now)
        let sky = SkyEventCatalog.horizon(of: event.target, at: now,
            location: ObserverLocation(latitude: -6.1754, longitude: 106.8272))
        #expect(event.isOpen(at: now))
        #expect(sky.azimuth == 45 && sky.altitude == 35)
        #expect(abs(simd_length(sky.direction) - 1) < 1e-6)
        let suite = "SkyEventDemoTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = HomeViewModel(defaults: defaults)
        let location = AppPreviewData.location
        let photo = AppPreviewData.albumPhoto
        let first = try model.saveEventObservation(event, image: photo, date: now, location: location)
        defer { model.deleteCollected(id: first.id) }
        let captureID = try #require(first.captureID)
        model.updateObservationNote(captureID: captureID, note: "Practice under a clear sky.")
        let nextDemo = SkyEvent.demo(at: now)
        #expect(!model.hasEventCapture(nextDemo))
        let second = try model.saveEventObservation(nextDemo, image: photo, date: now, location: location)
        #expect(first.id == second.id)
        #expect(first.photoFilename != second.photoFilename)

        let reloaded = HomeViewModel(defaults: defaults)
        #expect(reloaded.hasEventCapture(event))
        #expect(reloaded.hasEventCapture(nextDemo))
        #expect(reloaded.observation(captureID: captureID)?.note == "Practice under a clear sky.")
        #expect(StarPhotoStore.load(first.photoFilename) != nil)
        #expect(reloaded.collectionItems.count == 1)
        #expect(CollectionCategory.stars(reloaded.collectionItems).isEmpty)
        let placement = GardenViewModel.placement(items: reloaded.collectionItems, location: location, date: now)
        #expect(placement.placed.map(\.id) == [first.id])
        let marker = try #require(placement.placed.first)
        #expect(simd_length(marker.object.direction - sky.direction) < 1e-6)
        #expect(defaults.object(forKey: "collectedSkyEvents") == nil)
    }
    #endif
}
