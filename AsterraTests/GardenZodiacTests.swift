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
            #expect(Set(item.alignmentStarIDs).count == 3)
            #expect(item.alignmentStarIDs.allSatisfy(item.requiredStarIDs.contains))
            #expect(UIImage(named: item.assetName) != nil)
        }
        #expect(figures.first { $0.id == "Ari" }?.requiredStarIDs.count == 4)
        #expect(figures.first { $0.id == "Lib" }?.requiredStarIDs.count == 6)
    }

    @Test func customDrawingsResolveFromTheCatalogAndRemainCached() async throws {
        let expected = ["Cap": "Capriconous", "Psc": "Pisces", "Sco": "Scorpius"]
        for (code, name) in expected {
            let item = try #require(GardenZodiacFigure.load().first { $0.id == code })
            #expect(item.assetName == "constellation-figures-rafi-aligned/\(name)")
            let first = try #require(await GardenZodiacArtworkStore.shared.load(assetNamed: item.assetName))
            let second = try #require(await GardenZodiacArtworkStore.shared.load(assetNamed: item.assetName))
            #expect(first.image === second.image)
            #expect(max(first.image.width, first.image.height) <= 512)
            #expect(first.glow != nil)
            try #require(UIImage(cgImage: first.image).pngData()).write(to:
                URL(fileURLWithPath: "/private/tmp/asterra-source-\(code).png"))
        }
        #expect(await GardenZodiacArtworkStore.shared.load(assetNamed: "constellation-figures-rafi-aligned/missing") == nil)
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

    #if DEBUG
    @Test func demoFillsAllTwelvePatternsWithoutSavingObservations() throws {
        let figures = GardenZodiacFigure.load()
        let ids = figures
            .reduce(into: Set<Int>()) { $0.formUnion($1.requiredStarIDs) }
        let existingIDs = try #require(figures.first { $0.id == "Lib" }).requiredStarIDs
        let suite = "asterra.zodiac.preview.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let existing = existingIDs.map {
            CollectedStar(id: $0, date: AppPreviewData.date, latitude: -6.2, longitude: 106.85,
                          captureID: UUID())
        }
        let original = try JSONEncoder().encode(existing)
        defaults.set(original, forKey: "collectedStars")
        let home = HomeViewModel(location: AppPreviewData.location, defaults: defaults)
        let garden = GardenViewModel(model: home)
        let camera = garden.camera

        garden.setDemoConstellations(true)
        #expect(Set(garden.placed.map(\.id)) == ids)
        #expect(garden.placed.count == ids.count)
        #expect(Set(garden.placed.filter(\.isPreview).map(\.id)) == ids.subtracting(existingIDs))
        #expect(Set(garden.completedZodiacFigures.map(\.id)) == GardenZodiacFigure.codes)
        #expect(Set(garden.constellationConnections.flatMap { [$0.startID, $0.endID] }) == ids)
        #expect(garden.camera == camera)
        #expect(Set(home.collectionItems.map(\.id)) == existingIDs)
        #expect(defaults.data(forKey: "collectedStars") == original)

        garden.setDemoConstellations(false)
        #expect(Set(garden.placed.map(\.id)) == existingIDs)
        #expect(garden.completedZodiacFigures.map(\.id) == ["Lib"])
        #expect(defaults.data(forKey: "collectedStars") == original)
    }
    #endif

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
        for item in GardenZodiacFigure.load() {
            let (sky, original) = try scene(for: item)
            let size = CGSize(width: 402, height: 650)
            for gyro in [false, true] {
                var camera = original
                camera.fieldOfView = 40
                if gyro {
                    camera.orientation = WormholeFreeze.orientation(forward: camera.forward, right: camera.right, up: camera.up)
                        * simd_quatd(angle: 0.25, axis: SIMD3(0, 0, 1))
                }
                let projected = GardenZodiacFigure.project([item], basis: sky.basis, size: size, forward: camera.forward,
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

    @Test func artworkFadesBeforeGrazingTheCameraPlane() throws {
        let item = try #require(GardenZodiacFigure.load().first { $0.id == "Cap" })
        let (sky, centered) = try scene(for: item)
        let size = CGSize(width: 650, height: 650)

        func project(at angle: Double) -> [ProjectedConstellationFigure] {
            var camera = centered
            camera.fieldOfView = 110
            let rotation = simd_quatd(angle: angle * .pi / 180, axis: centered.up)
            camera.orientation = rotation * WormholeFreeze.orientation(
                forward: centered.forward, right: centered.right, up: centered.up)
            return GardenZodiacFigure.project([item], basis: sky.basis, size: size, forward: camera.forward) {
                camera.project($0, in: size)
            }
        }

        #expect(project(at: 0).first?.opacity == 0.64)
        let edge = try #require([15.0, 20, 25, 30, 37].compactMap { project(at: $0).first }
            .first { $0.opacity < 0.64 })
        #expect(edge.opacity > 0 && edge.opacity < 0.64)
        #expect(project(at: 65).isEmpty)
    }

    @Test func artworkFadesForUnevenStretchButNotForZoomOrRoll() throws {
        let item = try #require(GardenZodiacFigure.load().first { $0.id == "Cap" })
        let (sky, camera) = try scene(for: item)
        let size = CGSize(width: 650, height: 650)
        let center = camera.center(in: size)

        func opacity(stretch: CGFloat, zoom: CGFloat = 1, roll: CGFloat = 0) -> Double? {
            let transform = CGAffineTransform(scaleX: zoom * stretch, y: zoom).rotated(by: roll)
            return GardenZodiacFigure.project([item], basis: sky.basis, size: size, forward: camera.forward) { direction in
                camera.project(direction, in: size).map { point in
                    let offset = CGPoint(x: point.x - center.x, y: point.y - center.y).applying(transform)
                    return CGPoint(x: center.x + offset.x, y: center.y + offset.y)
                }
            }.first?.opacity
        }

        #expect(opacity(stretch: 1, zoom: 1.5, roll: 0.4) == 0.64)
        let faded = try #require(opacity(stretch: 1.19))
        #expect(faded > 0 && faded < 0.64)
        #expect(opacity(stretch: 1.30) == nil)
    }

    /// The horizon mask is clear below the horizon, opaque well above it, soft in between,
    /// and follows phone roll.
    @Test func horizonMaskExcludesTheSeaSoftlyAndFollowsPhoneRoll() throws {
        func alpha(_ image: CGImage) -> [UInt8] {
            var rgba = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = CGContext(data: &rgba, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
        }
        let size = CGSize(width: 100, height: 100)
        // Height falls 0.002 per point from the top: horizon at y = 50, fully clear of the band by y ≈ 32.
        let upright = try #require(GardenZodiacFigure.skyMask(size: size, columns: 10) { 0.002 * Double(50 - $0.y) })
        let values = alpha(upright)
        let rows = upright.height
        let top = values[0], bottom = values[(rows - 1) * 10]
        #expect(top == 255 && bottom == 0)
        #expect(values.contains { $0 > 0 && $0 < 255 })                         // a soft band, not a cut
        for row in 1..<rows { #expect(values[row * 10] <= values[(row - 1) * 10]) }
        let rolled = try #require(GardenZodiacFigure.skyMask(size: size, columns: 10) { 0.01 * Double(100 - $0.x - $0.y) })
        let rolledValues = alpha(rolled)
        #expect(rolledValues[0] == 255 && rolledValues[(rows - 1) * 10 + 9] == 0)
        let below = try #require(GardenZodiacFigure.skyMask(size: size) { _ in -1 })
        #expect(alpha(below).allSatisfy { $0 == 0 })
    }

    /// Zooming deep into a figure fades it out instead of making it vanish at a size cut-off.
    @Test func deepZoomFadesTheArtworkInsteadOfCuttingIt() throws {
        let item = try #require(GardenZodiacFigure.load().first { $0.id == "Cap" })
        let (sky, centered) = try scene(for: item)
        let size = CGSize(width: 402, height: 650)
        var opacities: [Double] = []
        // 5% zoom steps, like a pinch frame by frame.
        for fov in sequence(first: 60.0, next: { $0 * 0.95 }).prefix(while: { $0 > 1 }) {
            var camera = centered
            camera.fieldOfView = fov
            let projected = GardenZodiacFigure.project([item], basis: sky.basis, size: size, forward: camera.forward) {
                camera.project($0, in: size)
            }
            opacities.append(projected.first?.opacity ?? 0)
        }
        // A monotonic fade, no step larger than a few percent per 5% of zoom.
        for (a, b) in zip(opacities, opacities.dropFirst()) { #expect(a >= b && a - b < 0.07) }
        #expect(opacities.last == 0)
    }

    @Test(arguments: ["Lib", "Cap", "Psc", "Sco"])
    func completedArtworkRendersForVisualReview(code: String) async throws {
        let libra = try #require(GardenZodiacFigure.load().first { $0.id == code })
        let (sky, camera) = try scene(for: libra)
        let size = CGSize(width: 402, height: 500)
        let projected = GardenZodiacFigure.project([libra], basis: sky.basis, size: size, forward: camera.forward,
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
            skyMask: GardenZodiacFigure.skyMask(size: size) { _ in 1 },
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
        let first = try #require(await GardenZodiacArtworkStore.shared.load(assetNamed: "constellation-figures-rafi-aligned/Libra"))
        let second = try #require(await GardenZodiacArtworkStore.shared.load(assetNamed: "constellation-figures-rafi-aligned/Libra"))
        #expect(first.image === second.image)
        #expect(first.glow === second.glow)
        #expect(first.glow != nil)
    }

    @Test func motionUpdatesReuseImageLayersWithoutRestartingTheReveal() async throws {
        let libra = try #require(GardenZodiacFigure.load().first { $0.id == "Lib" })
        let decoded = try #require(await GardenZodiacArtworkStore.shared.load(assetNamed: "constellation-figures-rafi-aligned/Libra"))
        let view = GardenZodiacFigureLayerView()
        view.frame = CGRect(x: 0, y: 0, width: 402, height: 650)
        let clip = GardenZodiacFigure.skyMask(size: CGSize(width: 402, height: 650)) { _ in 1 }
        func update(_ step: Int, active: Bool = true, reduceMotion: Bool = false, opacity: Double = 0.64) {
            let drawing = ProjectedConstellationFigure(figure: libra.figure,
                transform: CGAffineTransform(translationX: Double(step % 100), y: 20), opacity: opacity)
            view.update(unlockedIDs: ["Lib"], projected: [drawing], skyMask: clip,
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
        update(1, opacity: 0.25)
        #expect(container.opacity == 0.25)
        #expect(image.animation(forKey: "zodiac-reveal")?.beginTime == startedAt)
        update(1, reduceMotion: true)
        #expect(image.animationKeys()?.isEmpty ?? true)
        update(1, active: false)
        #expect(container.isHidden)
    }
}
