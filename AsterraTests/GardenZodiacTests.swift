import CoreGraphics
import Foundation
import SwiftUI
import Testing
import UIKit
import simd

@testable import Asterra

@MainActor
struct GardenZodiacTests {
    @Test func onlyTheTwelveZodiacFiguresAreAvailableAndAllAssetsLoad() throws {
        let figures = GardenZodiacFigure.load()
        #expect(figures.count == 12)
        #expect(Set(figures.map(\.id)) == GardenZodiacFigure.codes)
        let catalogue = Set(try SkyAssets.stars().map(\.id))
        for item in figures {
            #expect(!item.requiredStarIDs.isEmpty)
            #expect(item.requiredStarIDs.isSubset(of: catalogue))
            #expect(UIImage(named: item.assetName) != nil)
        }
        #expect(figures.first { $0.id == "Ari" }?.requiredStarIDs.count == 4)
        #expect(figures.first { $0.id == "Lib" }?.requiredStarIDs.count == 6)
    }

    @Test func customDrawingsResolveFromTheCatalogAndRemainCached() async throws {
        let expected = ["Cap": "capricon-figure", "Psc": "pisces-figure", "Sco": "scorpio-figure"]
        for (code, name) in expected {
            let item = try #require(GardenZodiacFigure.load().first { $0.id == code })
            #expect(item.assetName == "constellation-figures/\(name)")
            let first = try #require(await GardenZodiacArtworkStore.shared.load(assetNamed: item.assetName))
            let second = try #require(await GardenZodiacArtworkStore.shared.load(assetNamed: item.assetName))
            #expect(first.image === second.image)
            #expect(max(first.image.width, first.image.height) <= 512)
            #expect(first.glow != nil)
            try #require(UIImage(cgImage: first.image).pngData()).write(to:
                URL(fileURLWithPath: "/private/tmp/asterra-source-\(code).png"))
        }
        #expect(await GardenZodiacArtworkStore.shared.load(assetNamed: "constellation-figures/missing") == nil)
    }

    @Test func everyRequiredStarMustBeCollectedBeforeArtworkUnlocks() throws {
        let figures = GardenZodiacFigure.load()
        #expect(GardenZodiacFigure.unlocked(figures, collected: []).isEmpty)
        for figure in figures {
            for missing in figure.requiredStarIDs {
                let partial = figure.requiredStarIDs.subtracting([missing])
                #expect(!GardenZodiacFigure.unlocked(figures, collected: partial).contains { $0.id == figure.id })
            }
            #expect(GardenZodiacFigure.unlocked(figures, collected: figure.requiredStarIDs).map(\.id) == [figure.id])
        }
        let all = figures.reduce(into: Set<Int>()) { $0.formUnion($1.requiredStarIDs) }
        #expect(GardenZodiacFigure.unlocked(figures, collected: all).count == 12)
    }

    @Test func completingAndDeletingAStarUpdatesTheGardenFigure() throws {
        let libra = try #require(GardenZodiacFigure.load().first { $0.id == "Lib" })
        let ids = libra.requiredStarIDs.sorted()
        let last = try #require(ids.last)
        let suite = "celyx.zodiac.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let records = ids.dropLast().map {
            CollectedStar(id: $0, date: AppPreviewData.date, latitude: -6.2, longitude: 106.85)
        }
        defaults.set(try JSONEncoder().encode(records), forKey: "collectedStars")
        let model = HomeViewModel(location: AppPreviewData.location, defaults: defaults)
        defer {
            for record in model.collected.values {
                if let filename = record.photoFilename { StarPhotoStore.remove(filename) }
            }
            defaults.removePersistentDomain(forName: suite)
        }
        let garden = GardenViewModel(model: model)
        #expect(garden.completedZodiacFigures.isEmpty)
        let star = try #require(model.stars.first { $0.id == last })
        try model.saveCameraObservation(CameraObservationDraft(star: star, image: AppPreviewData.albumPhoto,
            date: AppPreviewData.date, location: AppPreviewData.location, identificationNote: nil), note: "")
        garden.place()
        #expect(garden.completedZodiacFigures.map(\.id) == ["Lib"])
        let restored = GardenViewModel(model: HomeViewModel(defaults: defaults))
        #expect(restored.completedZodiacFigures.map(\.id) == ["Lib"])
        model.deleteCollected(id: try #require(ids.first))
        garden.place()
        #expect(garden.completedZodiacFigures.isEmpty)
    }

    private func scene(for item: GardenZodiacFigure) throws -> (SkySnapshot, NightSeaCamera) {
        let sky = try #require((0..<24).map { hour in
            AstronomyService.snapshot(date: AppPreviewData.date.addingTimeInterval(Double(hour) * 3600),
                                      location: AppPreviewData.location)
        }.first { ($0.basis * item.figure.center).z > 0.5 })
        let center = sky.basis * item.figure.center
        var camera = NightSeaCamera()
        camera.azimuth = atan2(center.x, center.y)
        camera.altitude = asin(center.z)
        return (sky, camera)
    }

    @Test func artworkStaysOnItsAnchorsAcrossZoomAndGyroRoll() throws {
        for item in GardenZodiacFigure.load().filter({ ["Lib", "Ari"].contains($0.id) }) {
            let (sky, original) = try scene(for: item)
            let size = CGSize(width: 402, height: 650)
            for gyro in [false, true] {
                var camera = original
                camera.fieldOfView = 40
                if gyro {
                    camera.orientation = WormholeFreeze.orientation(forward: camera.forward, right: camera.right, up: camera.up)
                        * simd_quatd(angle: 0.25, axis: SIMD3(0, 0, 1))
                }
                let projected = GardenZodiacFigure.project([item], basis: sky.basis, size: size,
                    point: { camera.project($0, in: size) })
                let drawing = try #require(projected.first)
                for anchor in item.figure.definition.anchors {
                    let expected = try #require(camera.project(Refraction.apparent(sky.basis * anchor.equatorial), in: size))
                    let actual = CGPoint(x: anchor.pixel[0], y: anchor.pixel[1]).applying(drawing.transform)
                    #expect(hypot(actual.x - expected.x, actual.y - expected.y) < 1e-6)
                }
            }
        }
    }

    @Test func horizonClipExcludesTheSeaAndFollowsPhoneRoll() {
        let size = CGSize(width: 100, height: 100)
        let upright = GardenZodiacFigure.skyClip(size: size) { Double(50 - $0.y) }
        #expect(upright.count == 4 && upright.allSatisfy { $0.y <= 50 })
        let rolled = GardenZodiacFigure.skyClip(size: size) { Double($0.x + $0.y - 100) }
        #expect(!rolled.isEmpty && rolled.allSatisfy { $0.x + $0.y >= 100 })
        #expect(GardenZodiacFigure.skyClip(size: size) { _ in -1 }.isEmpty)
    }

    @Test(arguments: ["Lib", "Cap", "Psc", "Sco"])
    func completedArtworkRendersForVisualReview(code: String) async throws {
        let libra = try #require(GardenZodiacFigure.load().first { $0.id == code })
        let (sky, camera) = try scene(for: libra)
        let size = CGSize(width: 402, height: 500)
        let projected = GardenZodiacFigure.project([libra], basis: sky.basis, size: size,
            point: { camera.project($0, in: size) })
        let stars = try SkyAssets.stars().filter { libra.requiredStarIDs.contains($0.id) }
        let positions = Dictionary(uniqueKeysWithValues: stars.compactMap { star -> (Int, CGPoint)? in
            camera.project(Refraction.apparent(sky.direction(ra: star.ra_deg, dec: star.dec_deg)), in: size).map { (star.id, $0) }
        })
        let items = stars.map { GardenCollectionItem(star: $0, record: CollectedStar(id: $0.id,
            date: AppPreviewData.date, latitude: -6.2, longitude: 106.85)) }
        let connections = GardenConstellationConnection.resolve(figures: GardenConstellationConnection.loadFigures(), items: items)
        let content = ZStack {
            GardenConstellationLines(connections: connections, positions: positions)
            ForEach(positions.keys.sorted(), id: \.self) { id in
                Circle().fill(.white).frame(width: 4, height: 4).position(positions[id]!)
            }
        }.frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: content); renderer.scale = 2
        let lines = try #require(renderer.uiImage)
        let decoded = try #require(await GardenZodiacArtworkStore.shared.load(assetNamed: libra.assetName))
        let view = GardenZodiacFigureLayerView()
        view.frame = CGRect(origin: .zero, size: size)
        view.update(unlockedIDs: [code], projected: projected,
            skyClip: [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height)],
            artwork: [code: decoded], animatedIDs: [], isActive: true, reduceMotion: true)
        view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0.02, green: 0.03, blue: 0.08, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            view.layer.render(in: context.cgContext)
            lines.draw(in: CGRect(origin: .zero, size: size))
        }
        try #require(image.pngData()).write(to: URL(fileURLWithPath: "/private/tmp/asterra-zodiac-\(code).png"))
    }

    @Test func artworkAndGlowAreDecodedOnceAndReused() async throws {
        let first = try #require(await GardenZodiacArtworkStore.shared.load(assetNamed: "constellation-figures/libra-figure"))
        let second = try #require(await GardenZodiacArtworkStore.shared.load(assetNamed: "constellation-figures/libra-figure"))
        #expect(first.image === second.image)
        #expect(first.glow === second.glow)
        #expect(first.glow != nil)
    }

    @Test func motionUpdatesReuseImageLayersWithoutRestartingTheReveal() async throws {
        let libra = try #require(GardenZodiacFigure.load().first { $0.id == "Lib" })
        let decoded = try #require(await GardenZodiacArtworkStore.shared.load(assetNamed: "constellation-figures/libra-figure"))
        let view = GardenZodiacFigureLayerView()
        view.frame = CGRect(x: 0, y: 0, width: 402, height: 650)
        let clip = [CGPoint.zero, CGPoint(x: 402, y: 0), CGPoint(x: 402, y: 650), CGPoint(x: 0, y: 650)]
        func update(_ step: Int, active: Bool = true, reduceMotion: Bool = false) {
            let drawing = ProjectedConstellationFigure(figure: libra.figure,
                transform: CGAffineTransform(translationX: Double(step % 100), y: 20), opacity: 0.64)
            view.update(unlockedIDs: ["Lib"], projected: [drawing], skyClip: clip,
                artwork: ["Lib": decoded], animatedIDs: ["Lib"], isActive: active, reduceMotion: reduceMotion)
        }
        update(0)
        let container = try #require(view.layer.sublayers?.first)
        let image = try #require(container.sublayers?.first)
        let original = try #require(image.contents) as AnyObject
        let startedAt = try #require(image.animation(forKey: "zodiac-reveal")?.beginTime)
        let start = CACurrentMediaTime()
        for step in 1...1000 { update(step) }
        print("Zodiac retained-layer update: \((CACurrentMediaTime() - start) * 1000 / 1000) ms/update (simulator)")
        #expect(view.layer.sublayers?.first === container)
        let current = try #require(image.contents) as AnyObject
        #expect(current === original)
        #expect(image.animation(forKey: "zodiac-reveal")?.beginTime == startedAt)
        update(1, reduceMotion: true)
        #expect(image.animationKeys()?.isEmpty ?? true)
        update(1, active: false)
        #expect(container.isHidden)
    }
}
