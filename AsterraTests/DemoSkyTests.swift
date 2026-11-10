#if DEBUG
import CoreGraphics
import Foundation
import Testing
import UIKit
import simd

@testable import Asterra

@MainActor
struct DemoSkyTests {
    @Test func demoIncludesEveryLibraAriesAndCapricornusPatternMember() throws {
        let stars = DemoSky.stars(in: try SkyAssets.stars())
        #expect(Set(stars.map(\.id)) == [103, 125, 222, 329, 349, 476, 51, 105, 333, 459, 717, 187, 1227, 603, 595, 398, 144, 356, 699, 568])
        #expect(stars.filter { $0.con == "Lib" }.count == 6)
        #expect(stars.filter { $0.con == "Ari" }.count == 4)
        #expect(stars.filter { $0.con == "Cap" }.count == 10)
        #expect(!stars.contains { $0.title == "Rigel" })
    }

    @Test func capricornusStartsWithNineAndTheLastCaptureUnlocksItsFigure() throws {
        let suite = "asterra.demo.capricornus.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = HomeViewModel(defaults: defaults)
        let last = try #require(try DemoSky.prepareCapricornus(model: model, date: AppPreviewData.date,
                                                         location: AppPreviewData.location))
        #expect(last.title == "Deneb Algedi")
        #expect(model.collected.count == 9)
        #expect(model.collected[last.id] == nil)
        let figure = try #require(GardenZodiacFigure.load().first { $0.id == "Cap" })
        #expect(GardenZodiacFigure.unlocked([figure], collected: Set(model.collected.keys)).isEmpty)
        let restored = HomeViewModel(defaults: defaults)
        #expect(restored.collected.count == 9)
        for record in restored.collected.values {
            #expect(record.photoFilename == nil)
            #expect(record.identificationNote?.contains("no camera capture") == true)
            #expect(record.latitude == AppPreviewData.location.latitude)
        }
        try DemoSky.prepareCapricornus(model: restored, date: Date(), location: AppPreviewData.location)
        #expect(restored.collected.count == 9)
        try restored.seedDemoObservations([CollectedStar(id: last.id, date: Date(), latitude: -6.2, longitude: 106.8)])
        #expect(GardenZodiacFigure.unlocked([figure], collected: Set(restored.collected.keys)).count == 1)
        #expect(try DemoSky.prepareCapricornus(model: restored, date: Date(), location: AppPreviewData.location) == nil)
        #expect(restored.collected.count == 10)
    }

    @Test func capricornusSetupPreservesExistingObservationsAndLeavesAnotherMissingStar() throws {
        let suite = "asterra.demo.capricornus.existing.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = HomeViewModel(defaults: defaults)
        let original = CollectedStar(id: 144, date: AppPreviewData.date, latitude: 12, longitude: 34,
                                    photoFilename: "existing-photo.jpg", note: "Keep my note")
        try model.seedDemoObservations([original])
        let last = try #require(try DemoSky.prepareCapricornus(model: model, date: Date(), location: AppPreviewData.location))
        #expect(last.id != 144 && model.collected[last.id] == nil)
        #expect(model.collected.count == 9)
        #expect(model.collected[144]?.photoFilename == original.photoFilename)
        #expect(model.collected[144]?.note == original.note)
        #expect(model.collected[144]?.date == original.date)
    }

    @Test func demoPositionsMatchTheRealGardenForTheSameLocationAndTime() throws {
        let catalogue = try SkyAssets.stars()
        let location = AppPreviewData.location
        let date = AppPreviewData.date
        let entries = DemoSky.entries(in: catalogue, date: date, location: location)
        let items = entries.map { entry in
            GardenCollectionItem(star: entry.star, record: CollectedStar(id: entry.id, date: date,
                latitude: location.latitude, longitude: location.longitude))
        }
        let garden = GardenViewModel.placement(items: items, location: location, date: date)
        #expect(entries.count == 20)
        for entry in entries {
            let object = try #require(garden.placed.first { $0.id == entry.id })
            #expect(simd_distance(entry.direction, object.object.direction) < 1e-10)
        }
    }

    @Test func demoPositionsFollowTimeAndObserverLocation() throws {
        let catalogue = try SkyAssets.stars()
        let date = AppPreviewData.date
        let location = AppPreviewData.location
        let original = DemoSky.entries(in: catalogue, date: date, location: location)
        let later = DemoSky.entries(in: catalogue, date: date.addingTimeInterval(6 * 3600), location: location)
        let elsewhere = DemoSky.entries(in: catalogue, date: date,
            location: ObserverLocation(latitude: 40, longitude: -74, isManual: true))
        #expect(original.count == 20 && later.count == 20 && elsewhere.count == 20)
        #expect(zip(original, later).allSatisfy { simd_distance($0.direction, $1.direction) > 0.1 })
        #expect(zip(original, elsewhere).allSatisfy { simd_distance($0.direction, $1.direction) > 0.1 })
        // Opposite constellations remain on opposite sides of the real sky, rather than side by side.
        let hamal = try #require(original.first { $0.star.title == "Hamal" })
        let zuben = try #require(original.first { $0.star.title == "Zubenelgenubi" })
        #expect(simd_dot(hamal.direction, zuben.direction) < -0.8)
        #expect(original.contains { $0.direction.z < 0 })
    }

    @Test func demoDoesNotInventPositionsWithoutAnObserverLocation() throws {
        #expect(DemoSky.entries(in: try SkyAssets.stars(), date: AppPreviewData.date, location: nil).isEmpty)
        let service = SkyFinderService(star: nil, location: AppPreviewData.location, catalogue: [])
        #expect(service.demoProjection(horizon: SIMD3(0, 0, 1)) == nil)
        #expect(service.demoProjection(horizon: SIMD3(0, 0, -1)) == nil)
    }

    @Test func reticleChoosesTheClosestUncollectedStarAndRetainsItsLock() throws {
        let stars = DemoSky.stars(in: try SkyAssets.stars())
        let a = stars[0], b = stars[1]
        let projections: [DemoSky.Projection] = [
            .init(star: a, point: CGPoint(x: 110, y: 100), arrow: nil),
            .init(star: b, point: CGPoint(x: 102, y: 100), arrow: nil),
        ]
        func target(collected: Set<Int> = [], excluded: Int? = nil, locked: Int? = nil) -> Int? {
            DemoSky.target(in: projections, collected: collected, excludedID: excluded,
                lockedID: locked, center: CGPoint(x: 100, y: 100), radius: 20, lockRadius: 30)?.id
        }
        #expect(target() == b.id)
        #expect(target(locked: a.id) == a.id)
        #expect(target(collected: [b.id]) == a.id)
        #expect(target(excluded: b.id) == a.id)
        #expect(target(collected: [a.id, b.id]) == nil)
    }

    @Test func everyDemoMemberPersistsWithItsRealObservationContextAndBypassMetadata() throws {
        let suite = "celyx.demo.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let model = HomeViewModel(location: AppPreviewData.location, date: AppPreviewData.date, defaults: defaults)
        defer {
            for record in model.collected.values {
                if let filename = record.photoFilename { StarPhotoStore.remove(filename) }
            }
            defaults.removePersistentDomain(forName: suite)
        }
        let image = try #require(DemoSky.composite(nil,
            stars: [(point: CGPoint(x: 40, y: 60), color: SIMD3(1, 1, 1))],
            viewSize: CGSize(width: 80, height: 120)))
        #expect(image.width == 80 && image.height == 120)
        for star in DemoSky.stars(in: model.stars) {
            try DemoSky.save(star: star, image: image, date: AppPreviewData.date, location: AppPreviewData.location, model: model)
        }
        let restored = HomeViewModel(defaults: defaults)
        #expect(restored.collected.count == 20)
        #expect(CollectionCategory.constellations(restored.collectionItems).count == 3)
        let capricornus = try #require(GardenZodiacFigure.load().first { $0.id == "Cap" })
        #expect(GardenZodiacFigure.unlocked([capricornus], collected: Set(restored.collected.keys)).count == 1)
        for record in restored.collected.values {
            #expect(record.identificationNote?.contains("optical verification bypassed") == true)
            #expect(record.date == AppPreviewData.date)
            #expect(record.latitude == AppPreviewData.location.latitude)
            #expect(record.longitude == AppPreviewData.location.longitude)
            #expect(StarPhotoStore.load(record.photoFilename) != nil)
        }
    }
}
#endif
