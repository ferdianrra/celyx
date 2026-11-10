import CoreGraphics
import Foundation

struct GardenCollectionItem: Identifiable {
    let star: CatalogStar
    let record: CollectedStar
    var id: Int { record.id }
    var coordinates: String { String(format: "%.2f°, %.2f°", record.latitude, record.longitude) }
    var collectedDate: String {
        record.date.formatted(
            .dateTime.month(.abbreviated).day().year().locale(Locale(identifier: "en")))
    }

    static func resolve(records: [Int: CollectedStar], catalogue: [CatalogStar]) -> [Self] {
        let indexed = Dictionary(
            (catalogue + CatalogStar.planets).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        return records.values.map { record in
            let star =
                record.id == CatalogStar.sun.id
                ? .sun
                : record.id == CatalogStar.moon.id
                    ? .moon
                    : indexed[record.id]
                        ?? CatalogStar(
                            id: record.id, ra_deg: 0, dec_deg: 0, mag: 0, bv: nil, name: nil,
                            designation: "Object \(record.id)",
                            distance_ly: nil, con: nil, collectible_candidate: nil)
            return Self(star: star, record: record)
        }.sorted { $0.record.date == $1.record.date ? $0.id < $1.id : $0.record.date > $1.record.date }
    }
}

enum GardenOrbit {
    // Stable decorative layout: collecting another object never relocates existing ones.
    // These are collection markers, not astronomical positions or physical planet orbits.
    private static func seed(_ id: Int) -> UInt64 {
        UInt64(bitPattern: Int64(id)) &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    }
    static func angle(id: Int) -> Double { Double((seed(id) >> 16) % 10000) / 10000 * 2 * .pi }
    static func point(id: Int, rotation: Double, diameter: Double, center: CGPoint) -> CGPoint {
        let radius = (0.17 + Double(seed(id) % 1000) / 1000 * 0.23) * diameter
        let angle = angle(id: id) + rotation
        return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius * 0.58)
    }
}
