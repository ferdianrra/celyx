import Foundation
import CoreGraphics
import SwiftUI
import Testing
import UIKit

@testable import Asterra

@MainActor
struct GardenConstellationTests {
    private func items(_ ids: [Int]) throws -> [GardenCollectionItem] {
        let catalogue = try SkyAssets.stars()
        return try ids.enumerated().map { index, id in
            let star = try #require(catalogue.first { $0.id == id })
            return GardenCollectionItem(star: star,
                record: CollectedStar(id: id, date: Date(timeIntervalSince1970: Double(index)),
                                      latitude: -6.2, longitude: 106.85))
        }
    }

    @Test func neighboringCollectedStarsRevealOnlyTheirActualEdge() throws {
        let figures = GardenConstellationConnection.loadFigures()
        let neighbors = try items([222, 125]) // Brachium -> Zubenelgenubi.
        #expect(GardenConstellationConnection.resolve(figures: figures, items: Array(neighbors.prefix(1))).isEmpty)
        let connections = GardenConstellationConnection.resolve(figures: figures, items: neighbors)
        #expect(connections.count == 1)
        #expect(connections.first?.constellation == "Lib")
        #expect(connections.first?.startID == 222)
        #expect(connections.first?.endID == 125)
        #expect(GardenConstellationConnection.resolve(figures: figures, items: try items([222, 103])).isEmpty)
        #expect(GardenConstellationConnection.resolve(figures: figures, items: try items([222, 51])).isEmpty)
    }

    @Test func completeDemoPatternsHaveSixLibraAndThreeAriesConnections() throws {
        let collected = try items([103, 125, 222, 329, 349, 476, 51, 105, 333, 459])
        let connections = GardenConstellationConnection.resolve(
            figures: GardenConstellationConnection.loadFigures(), items: collected)
        #expect(connections.filter { $0.constellation == "Lib" }.count == 6)
        #expect(connections.filter { $0.constellation == "Ari" }.count == 3)
        #expect(Set(connections.map(\.id)).count == 9)
    }

    @Test func deletingAnEndpointRemovesItsConnections() throws {
        let figures = GardenConstellationConnection.loadFigures()
        let collected = try items([222, 125, 103])
        let before = GardenConstellationConnection.resolve(figures: figures, items: collected)
        let after = GardenConstellationConnection.resolve(figures: figures, items: collected.filter { $0.id != 125 })
        #expect(before.count == 2)
        #expect(after.isEmpty)
    }

    @Test func polylinesAndReversedDuplicatesDoNotInventExtraEdges() throws {
        let figures: [String: Constellation] = [
            "Lib": Constellation(name: "Libra", english: "Scales",
                                 segments: [[222, 125, 103], [125, 222], [103, 103]])
        ]
        let connections = GardenConstellationConnection.resolve(figures: figures, items: try items([222, 125, 103]))
        #expect(connections.count == 2)
        #expect(!connections.contains { Set([$0.startID, $0.endID]) == Set([222, 103]) })
    }

    @Test func gardenKeepsConnectionsInSyncWithCollectionChanges() throws {
        let suite = "celyx.connections.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let records = try items([222, 125]).map(\.record)
        defaults.set(try JSONEncoder().encode(records), forKey: "collectedStars")
        let model = HomeViewModel(location: AppPreviewData.location, defaults: defaults)
        let garden = GardenViewModel(model: model)
        #expect(garden.constellationConnections.count == 1)
        model.deleteCollected(id: 222)
        garden.place()
        #expect(garden.constellationConnections.isEmpty)
    }

    @Test func constellationLinesRenderForVisualReview() throws {
        let connections = GardenConstellationConnection.resolve(
            figures: GardenConstellationConnection.loadFigures(), items: try items([222, 125, 103, 476]))
        let positions: [Int: CGPoint] = [222: CGPoint(x: 70, y: 300), 125: CGPoint(x: 150, y: 180),
                                       103: CGPoint(x: 220, y: 80), 476: CGPoint(x: 330, y: 200)]
        let content = ZStack {
            Color(red: 0.02, green: 0.03, blue: 0.08)
            GardenConstellationLines(connections: connections, positions: positions)
            ForEach(positions.keys.sorted(), id: \.self) { id in
                Circle().fill(.white).frame(width: 4, height: 4).position(positions[id]!)
            }
        }.frame(width: 402, height: 400)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let data = try #require(renderer.uiImage?.pngData())
        try data.write(to: URL(fileURLWithPath: "/private/tmp/celyx-constellation-lines-preview.png"))
    }

    @Test func onlyLinesActuallyCrossingTheFrameCanActivateSweeps() {
        let edge = GardenConstellationConnection(constellation: "Lib", startID: 125, endID: 222)
        func visible(_ a: CGPoint, _ b: CGPoint) -> Bool {
            !GardenConstellationConnection.visible([edge], positions: [125: a, 222: b],
                size: CGSize(width: 100, height: 100)).isEmpty
        }
        #expect(visible(CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 80)))
        #expect(visible(CGPoint(x: 50, y: 50), CGPoint(x: 200, y: 50)))
        #expect(visible(CGPoint(x: -50, y: 50), CGPoint(x: 150, y: 50)))
        #expect(!visible(CGPoint(x: -50, y: -20), CGPoint(x: 150, y: -20)))
        // The bounding box overlaps the viewport, but the actual line misses its corner.
        #expect(!visible(CGPoint(x: -20, y: 10), CGPoint(x: 10, y: -20)))
        #expect(!visible(CGPoint(x: 20, y: 20), CGPoint(x: 25, y: 25)))
        #expect(GardenConstellationConnection.visible([edge], positions: [:],
            size: CGSize(width: 100, height: 100)).isEmpty)
    }

    @Test func offscreenConstellationsDoNotUseTheSweepBudget() {
        let visibleEdge = GardenConstellationConnection(constellation: "Lib", startID: 125, endID: 222)
        let hiddenEdge = GardenConstellationConnection(constellation: "Ari", startID: 51, endID: 105)
        let eligible = GardenConstellationConnection.visible([visibleEdge, hiddenEdge], positions: [
            125: CGPoint(x: 20, y: 20), 222: CGPoint(x: 80, y: 80),
            51: CGPoint(x: -100, y: -100), 105: CGPoint(x: -50, y: -50)
        ], size: CGSize(width: 100, height: 100))
        #expect(eligible == [visibleEdge])
        var scheduler = GardenConstellationSweepScheduler(connections: eligible, start: 0)
        scheduler.update(at: 10)
        #expect(scheduler.active.allSatisfy { $0.connectionID == visibleEdge.id })
        #expect(!scheduler.active.isEmpty)
    }
}
