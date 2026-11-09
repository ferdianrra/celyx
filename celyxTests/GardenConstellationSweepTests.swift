import Foundation
import Testing

@testable import celyx

@MainActor
struct GardenConstellationSweepTests {
    private let edge = GardenConstellationConnection(constellation: "Lib", startID: 125, endID: 222)

    @Test func bothStarsHaveStaggeredFiveSecondTimers() throws {
        var scheduler = GardenConstellationSweepScheduler(connections: [edge], start: 0)
        scheduler.update(at: 4.9)
        #expect(scheduler.active.isEmpty)
        scheduler.update(at: 5)
        #expect(scheduler.active.first?.sourceID == 125)
        scheduler.update(at: 7.5)
        #expect(scheduler.active.first?.sourceID == 222)
        scheduler.update(at: 10)
        #expect(scheduler.active.first?.sourceID == 125)
        scheduler.update(at: 12.5)
        #expect(scheduler.active.first?.sourceID == 222)
    }

    @Test func overdueNeighborsWaitInsteadOfSendingOpposingSweepsOnTheSameLine() throws {
        var scheduler = GardenConstellationSweepScheduler(connections: [edge], start: 0)
        scheduler.update(at: 20)
        #expect(scheduler.active.count == 1)
        #expect(scheduler.active.first?.sourceID == 125)
        scheduler.update(at: 22.5)
        #expect(scheduler.active.count == 1)
        #expect(scheduler.active.first?.sourceID == 222)
    }

    @Test func crowdedConstellationsStayCalmAndEveryStarGetsATurn() {
        let edges = (1..<10).map {
            GardenConstellationConnection(constellation: "Test", startID: $0, endID: $0 + 1)
        }
        var scheduler = GardenConstellationSweepScheduler(connections: edges, start: 0)
        var sources: Set<Int> = []
        var destinations: [Int: Set<String>] = [:]
        var starts: [Int: TimeInterval] = [:]
        var observedStarts: Set<String> = []
        for step in 0...1500 {
            scheduler.update(at: Double(step) / 10)
            #expect(scheduler.active.count <= 2)
            #expect(Set(scheduler.active.map(\.connectionID)).count == scheduler.active.count)
            for sweep in scheduler.active {
                sources.insert(sweep.sourceID)
                destinations[sweep.sourceID, default: []].insert(sweep.connectionID)
                if observedStarts.insert("\(sweep.sourceID):\(sweep.startedAt)").inserted {
                    if let previous = starts[sweep.sourceID] {
                        #expect(sweep.startedAt - previous >= 5 - 0.00001)
                    }
                    starts[sweep.sourceID] = sweep.startedAt
                }
            }
        }
        #expect(sources == Set(1...10))
        #expect(destinations[5]?.count == 2)
    }

    @Test func idleSchedulerSleepsUntilTheNextTimerOrCompletion() {
        var scheduler = GardenConstellationSweepScheduler(connections: [edge], start: 0)
        #expect(scheduler.nextUpdate(after: 0) == 5)
        scheduler.update(at: 5)
        #expect(abs(scheduler.nextUpdate(after: 5) - 7.4) < 0.00001)
    }
}
