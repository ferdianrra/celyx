#if DEBUG
import CoreGraphics
import Foundation
import Testing
import UIKit
import simd

@testable import Asterra

@MainActor
struct DemoSkyTests {
    @Test func demoIncludesVegaAndSwitchesPatternsAtLocalNoonAndMidnight() throws {
        let catalogue = try SkyAssets.stars()
        let vega = try #require(catalogue.first { $0.title == "Vega" })
        let figures = GardenZodiacFigure.load()
        let sagittarius = try #require(figures.first { $0.id == "Sgr" }).requiredStarIDs
        let aquarius = try #require(figures.first { $0.id == "Aqr" }).requiredStarIDs
        var jakarta = Calendar(identifier: .gregorian)
        jakarta.timeZone = try #require(TimeZone(identifier: "Asia/Jakarta"))
        let midnight = try #require(jakarta.date(from: DateComponents(year: 2026, month: 11, day: 24)))
        let noon = midnight.addingTimeInterval(12 * 3600)
        func ids(at date: Date, calendar: Calendar? = nil) -> Set<Int> {
            Set(DemoSky.stars(in: catalogue, date: date, calendar: calendar ?? jakarta).map(\.id))
        }
        #expect(ids(at: midnight) == sagittarius.union([vega.id]))
        #expect(ids(at: noon.addingTimeInterval(-1)) == sagittarius.union([vega.id]))
        #expect(ids(at: noon) == aquarius.union([vega.id]))
        #expect(ids(at: midnight.addingTimeInterval(86400 - 1)) == aquarius.union([vega.id]))
        #expect(ids(at: midnight.addingTimeInterval(86400)) == sagittarius.union([vega.id]))
        var utc = jakarta
        utc.timeZone = .gmt
        #expect(ids(at: noon, calendar: utc) == sagittarius.union([vega.id]))
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
        #expect(Set(entries.map(\.id)) == Set(DemoSky.stars(in: catalogue, date: date).map(\.id)))
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
        #expect(original.count == elsewhere.count)
        let laterDirections = Dictionary(uniqueKeysWithValues: later.map { ($0.id, $0.direction) })
        let shared = original.filter { laterDirections[$0.id] != nil }
        #expect(!shared.isEmpty)
        for entry in shared {
            let direction = try #require(laterDirections[entry.id])
            #expect(simd_distance(entry.direction, direction) > 0.1)
        }
        #expect(zip(original, elsewhere).allSatisfy { simd_distance($0.direction, $1.direction) > 0.1 })
        #expect((original + later).contains { $0.direction.z < 0 })
    }

    @Test func demoDoesNotInventPositionsWithoutAnObserverLocation() throws {
        #expect(DemoSky.entries(in: try SkyAssets.stars(), date: AppPreviewData.date, location: nil).isEmpty)
        let service = SkyFinderService(star: nil, location: AppPreviewData.location, catalogue: [])
        #expect(service.demoProjection(horizon: SIMD3(0, 0, 1)) == nil)
        #expect(service.demoProjection(horizon: SIMD3(0, 0, -1)) == nil)
    }

    @Test func reticleChoosesTheClosestUncollectedStarAndRetainsItsLock() throws {
        let stars = DemoSky.stars(in: try SkyAssets.stars(), date: AppPreviewData.date)
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

    @Test(arguments: [11, 12])
    func demoCapturesUseTheSharedSuccessHandlerAndPreserveObservationContext(hour: Int) async throws {
        let suite = "celyx.demo.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let model = HomeViewModel(location: AppPreviewData.location, date: AppPreviewData.date, defaults: defaults)
        defer {
            for record in model.collected.values {
                if let filename = record.photoFilename { StarPhotoStore.remove(filename) }
            }
            defaults.removePersistentDomain(forName: suite)
        }
        let viewModel = StarCollectViewModel(model: model)
        let size = CGSize(width: 80, height: 120)
        let composite = await DemoSky.composite(nil,
            stars: [(point: CGPoint(x: 40, y: 60), color: SIMD3(1, 1, 1))], viewSize: size)
        let image = try #require(composite)
        #expect(image.width == 80 && image.height == 120)
        var freeze = WormholeFreeze.placeholder(size: size)
        freeze.image = image
        var handled: Set<Int> = []
        viewModel.onSaved = { target, record, capture in
            #expect(target.id == record.id)
            #expect(model.collected[target.id]?.captureID == record.captureID)
            #expect(capture?.image === image)
            handled.insert(target.id)
            return true
        }
        let date = try #require(Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: AppPreviewData.date))
        let stars = DemoSky.stars(in: model.stars, date: date)
        for star in stars {
            let draft = DemoSky.observation(star: star, image: image, date: date, location: AppPreviewData.location)
            viewModel.saveCapture(draft, for: .init(star: star, detection: nil), freeze: freeze)
        }
        #expect(handled == Set(model.collected.keys))
        #expect(viewModel.capturedItem == nil)
        #expect(viewModel.errorMessage == nil)
        let restored = HomeViewModel(defaults: defaults)
        #expect(Set(restored.collected.keys) == Set(stars.map(\.id)))
        let unlocked = GardenZodiacFigure.unlocked(GardenZodiacFigure.load(), collected: Set(restored.collected.keys))
        #expect(Set(unlocked.map(\.id)) == [hour < 12 ? "Sgr" : "Aqr"])
        for record in restored.collected.values {
            #expect(record.identificationNote?.contains("optical verification bypassed") == true)
            #expect(record.date == date)
            #expect(record.latitude == AppPreviewData.location.latitude)
            #expect(record.longitude == AppPreviewData.location.longitude)
            #expect(StarPhotoStore.load(record.photoFilename) != nil)
        }
    }
}
#endif
