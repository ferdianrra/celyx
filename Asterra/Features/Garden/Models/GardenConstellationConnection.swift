import Foundation
import CoreGraphics

/// An actual figure edge whose two neighboring stars are both in the collection.
struct GardenConstellationConnection: Identifiable, Equatable {
    let constellation: String
    let startID: Int
    let endID: Int
    var id: String { "\(constellation):\(min(startID, endID)):\(max(startID, endID))" }

    /// Includes partially visible lines, even when both endpoint stars are beyond opposite edges.
    static func visible(_ connections: [Self], positions: [Int: CGPoint], size: CGSize) -> [Self] {
        guard size.width > 0, size.height > 0 else { return [] }
        return connections.filter { connection in
            guard let a = positions[connection.startID], let b = positions[connection.endID],
                a.x.isFinite, a.y.isFinite, b.x.isFinite, b.y.isFinite
            else { return false }
            let dx = b.x - a.x, dy = b.y - a.y
            guard hypot(dx, dy) > 16 else { return false }
            var enter: CGFloat = 0, exit: CGFloat = 1
            // Clip the segment against all four sides of the viewport.
            for (p, q) in [(-dx, a.x), (dx, size.width - a.x),
                           (-dy, a.y), (dy, size.height - a.y)] {
                if abs(p) < 1e-10 {
                    if q < 0 { return false }
                } else {
                    let fraction = q / p
                    if p < 0 { enter = max(enter, fraction) }
                    else { exit = min(exit, fraction) }
                    if enter > exit { return false }
                }
            }
            return enter < exit
        }
    }

    static func loadFigures() -> [String: Constellation] {
        guard let url = try? SkyAssets.url("constellations", extension: "json"),
            let data = try? Data(contentsOf: url),
            let figures = try? JSONDecoder().decode([String: Constellation].self, from: data)
        else { return [:] }
        return figures
    }

    static func resolve(figures: [String: Constellation], items: [GardenCollectionItem]) -> [Self] {
        let collected = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var connections: [String: Self] = [:]
        for (code, figure) in figures {
            for segment in figure.segments {
                for (a, b) in zip(segment, segment.dropFirst()) where a != b {
                    guard let first = collected[a], let second = collected[b],
                        first.star.con == code, second.star.con == code
                    else { continue }
                    // Draw toward the newly collected star.
                    let firstIsOlder = first.record.date == second.record.date
                        ? a < b : first.record.date < second.record.date
                    let connection = Self(constellation: code,
                        startID: firstIsOlder ? a : b, endID: firstIsOlder ? b : a)
                    connections[connection.id] = connection
                }
            }
        }
        return connections.values.sorted { $0.id < $1.id }
    }
}
