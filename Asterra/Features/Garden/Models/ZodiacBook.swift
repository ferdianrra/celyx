import CoreGraphics
import Foundation
import simd

/// One page of the constellation book: a zodiac pattern, its artwork and where each pattern star sits on it.
struct ZodiacBookEntry: Identifiable, Hashable {
    struct Member: Identifiable, Hashable {
        let star: CatalogStar
        /// Position on the artwork, 0...1 in both axes.
        let point: CGPoint
        var id: Int { star.id }
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    let code: String
    let name: String
    let assetName: String
    /// Pattern stars, brightest first.
    let members: [Member]
    let segments: [[Int]]
    var id: String { code }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.code == rhs.code }
    func hash(into hasher: inout Hasher) { hasher.combine(code) }

    func collectedCount(_ collected: Set<Int>) -> Int { members.filter { collected.contains($0.id) }.count }
    func progress(_ collected: Set<Int>) -> Double {
        members.isEmpty ? 0 : Double(collectedCount(collected)) / Double(members.count)
    }

    /// Lines appear once both neighbouring stars are collected, like the garden.
    func lines(_ collected: Set<Int>) -> [(CGPoint, CGPoint)] {
        let points = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.point) })
        return segments.flatMap { segment in
            zip(segment, segment.dropFirst()).compactMap { a, b in
                guard collected.contains(a), collected.contains(b), let p = points[a], let q = points[b] else { return nil }
                return (p, q)
            }
        }
    }

    /// The 12 zodiac pages in calendar order of their evening season, starting with Aries.
    static func load(catalogue: [CatalogStar]) -> [Self] {
        guard !catalogue.isEmpty else { return [] }
        let patterns = GardenConstellationConnection.loadFigures()
        let stars = Dictionary(catalogue.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let figures = Dictionary(GardenZodiacFigure.load().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return order.compactMap { code in
            guard let zodiac = figures[code], let pattern = patterns[code] else { return nil }
            let figure = zodiac.figure
            guard let place = artworkPlacement(figure) else { return nil }
            let members = zodiac.requiredStarIDs.compactMap { stars[$0] }
                .sorted { $0.mag < $1.mag }
                .map { Member(star: $0, point: place($0)) }
            return Self(code: code, name: ConstellationNames.name(for: code) ?? code,
                        assetName: zodiac.assetName, members: members, segments: pattern.segments)
        }
    }

    static let order = ["Ari", "Tau", "Gem", "Cnc", "Leo", "Vir", "Lib", "Sco", "Sgr", "Cap", "Aqr", "Psc"]

    /// Flat sky chart around the figure's centre, fitted to the artwork through its three anchor stars.
    private static func artworkPlacement(_ figure: ConstellationFigure) -> ((CatalogStar) -> CGPoint)? {
        let center = figure.center
        let east = simd_normalize(simd_cross(SIMD3(0, 0, 1), center))
        let north = simd_cross(center, east)
        func chart(_ direction: SIMD3<Double>) -> CGPoint {
            let onPlane = direction / simd_dot(direction, center)
            return CGPoint(x: simd_dot(onPlane, east), y: simd_dot(onPlane, north))
        }
        let size = CGSize(width: figure.definition.size[0], height: figure.definition.size[1])
        let source = figure.definition.anchors.map { chart($0.equatorial) }
        let target = figure.definition.anchors.map { CGPoint(x: $0.pixel[0] / size.width, y: $0.pixel[1] / size.height) }
        guard let transform = ConstellationFigureProjection.affine(source: source, target: target) else { return nil }
        return { star in
            let ra = star.ra_deg * .pi / 180, dec = star.dec_deg * .pi / 180
            return chart(SIMD3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec))).applying(transform)
        }
    }
}

/// Short observing notes for the info popover. Seasons are for mid-evening (around 9 pm) at low latitudes like Indonesia.
enum ZodiacBookNotes {
    struct Note { let bestTime: String; let howToSpot: String }

    static func note(for code: String) -> Note? { notes[code] }

    private static let notes: [String: Note] = [
        "Ari": .init(bestTime: "Evenings from November to January.",
                     howToSpot: "Find the Pleiades (the tiny misty cluster), then look a little to its west for two stars side by side: Hamal and Sheratan."),
        "Tau": .init(bestTime: "Evenings from December to February.",
                     howToSpot: "Follow Orion’s Belt away from Sirius to the orange star Aldebaran, sitting in a V of stars. The Pleiades ride on the bull’s back."),
        "Gem": .init(bestTime: "Evenings from January to March.",
                     howToSpot: "Look past Orion’s red shoulder, Betelgeuse, for two bright stars close together: Castor and Pollux, the twins’ heads."),
        "Cnc": .init(bestTime: "Evenings from February to April.",
                     howToSpot: "It’s faint. Look halfway between Pollux and Regulus. In a dark sky, the misty Beehive Cluster marks its middle."),
        "Leo": .init(bestTime: "Evenings from March to May.",
                     howToSpot: "Look for a backward question mark of stars ending in bright Regulus. A triangle of stars to its east forms the lion’s tail."),
        "Vir": .init(bestTime: "Evenings from April to June.",
                     howToSpot: "Find Spica, a bright blue-white star on its own. Following the Big Dipper’s handle arcs to Arcturus, then on to Spica."),
        "Lib": .init(bestTime: "Evenings from May to July.",
                     howToSpot: "Look between Spica and the red star Antares for a lopsided box of modest stars. Its two brightest are the scale’s pans."),
        "Sco": .init(bestTime: "Evenings from June to August.",
                     howToSpot: "Find the red star Antares, the scorpion’s heart. A long curve of stars hooks down from it to the stinger."),
        "Sgr": .init(bestTime: "Evenings from July to September.",
                     howToSpot: "East of Scorpius’ tail, look for eight stars shaped like a teapot. The Milky Way’s brightest part rises like steam from its spout."),
        "Cap": .init(bestTime: "Evenings from August to October.",
                     howToSpot: "East of the Teapot, look for a wide, faint triangle of stars, like a smile or a boat."),
        "Aqr": .init(bestTime: "Evenings from September to November.",
                     howToSpot: "It’s faint. Look for a small Y of four stars, the Water Jar, southwest of the Great Square of Pegasus."),
        "Psc": .init(bestTime: "Evenings from October to December.",
                     howToSpot: "It’s faint. Just south of the Great Square of Pegasus, look for a small ring of stars called the Circlet."),
    ]
}
