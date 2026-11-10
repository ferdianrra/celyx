import Foundation

/// Individual star timers share a small animation budget, without colliding on the same edge.
struct GardenConstellationSweepScheduler {
    static let interval: TimeInterval = 5
    static let duration: TimeInterval = 2.4
    static let maximumActive = 2

    struct Sweep: Equatable {
        let connectionID: String
        let sourceID: Int
        let startedAt: TimeInterval
        var endsAt: TimeInterval { startedAt + GardenConstellationSweepScheduler.duration }
    }

    private let neighbors: [Int: [String]]
    private var nextDue: [Int: TimeInterval]
    private var neighborIndex: [Int: Int] = [:]
    private(set) var active: [Sweep] = []

    init(connections: [GardenConstellationConnection], start: TimeInterval) {
        var neighbors: [Int: Set<String>] = [:]
        for connection in connections {
            neighbors[connection.startID, default: []].insert(connection.id)
            neighbors[connection.endID, default: []].insert(connection.id)
        }
        self.neighbors = neighbors.mapValues { $0.sorted() }
        let stars = neighbors.keys.sorted()
        self.nextDue = Dictionary(uniqueKeysWithValues: stars.enumerated().map { index, id in
            // Start the first visible star immediately; stagger the others within the first cycle.
            (id, start + Double(index) * Self.interval / Double(stars.count))
        })
    }

    mutating func update(at time: TimeInterval) {
        active.removeAll { $0.endsAt <= time }
        // Oldest waiting timer goes first, so busy constellations cannot starve a star.
        let waiting = nextDue.filter { $0.value <= time }.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value
        }
        for (starID, _) in waiting {
            guard active.count < Self.maximumActive else { break }
            guard let edges = neighbors[starID], !edges.isEmpty else { continue }
            let index = neighborIndex[starID, default: 0]
            let candidate = (0..<edges.count).map { (index + $0) % edges.count }
                .first { candidate in !active.contains { $0.connectionID == edges[candidate] } }
            guard let candidate else { continue } // Wait for the neighbor's sweep to finish.
            active.append(Sweep(connectionID: edges[candidate], sourceID: starID, startedAt: time))
            neighborIndex[starID] = (candidate + 1) % edges.count
            nextDue[starID] = time + Self.interval
        }
    }

    func nextUpdate(after time: TimeInterval) -> TimeInterval {
        // Sleep until a timer or completion, rather than polling during stillness.
        let upcoming = nextDue.values.filter { $0 > time } + active.map(\.endsAt)
        return upcoming.min() ?? time + Self.interval
    }
}
