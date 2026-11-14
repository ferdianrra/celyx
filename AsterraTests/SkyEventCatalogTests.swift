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
    }
}

