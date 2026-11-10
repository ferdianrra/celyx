import CoreGraphics
import Foundation
import simd

/// Zodiac artwork unlocks from the complete bundled line pattern, not simply constellation membership.
struct GardenZodiacFigure: Identifiable {
    static let codes: Set<String> = ["Ari", "Tau", "Gem", "Cnc", "Leo", "Vir", "Lib", "Sco", "Sgr", "Cap", "Aqr", "Psc"]
    struct ArtworkMapping: Decodable {
        let assetName: String
        let normalizedAnchors: [[Double]]
    }
    let assetName: String
    let figure: ConstellationFigure
    let requiredStarIDs: Set<Int>
    var id: String { figure.id }

    static func load() -> [Self] {
        let patterns = GardenConstellationConnection.loadFigures()
        guard let url = try? SkyAssets.url("zodiac-artwork", extension: "json"),
              let data = try? Data(contentsOf: url),
              let artwork = try? JSONDecoder().decode([String: ArtworkMapping].self, from: data) else { return [] }
        return ((try? ConstellationFigure.load()) ?? []).compactMap { figure in
            guard codes.contains(figure.id), let pattern = patterns[figure.id], let mapping = artwork[figure.id],
                  !mapping.assetName.isEmpty, mapping.normalizedAnchors.count == 3,
                  mapping.normalizedAnchors.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isFinite) }) else { return nil }
            let required = Set(pattern.segments.flatMap { $0 })
            guard !required.isEmpty else { return nil }
            let definition = figure.definition
            let anchors = zip(mapping.normalizedAnchors, definition.anchors).map { point, anchor in
                ConstellationFigure.Anchor(pixel: [point[0] * definition.size[0], point[1] * definition.size[1]],
                                           ra_deg: anchor.ra_deg, dec_deg: anchor.dec_deg)
            }
            let mapped = ConstellationFigure(id: figure.id,
                definition: .init(file: definition.file, size: definition.size, anchors: anchors), center: figure.center)
            return Self(assetName: mapping.assetName, figure: mapped, requiredStarIDs: required)
        }
    }

    static func unlocked(_ figures: [Self], collected: Set<Int>) -> [Self] {
        figures.filter { !$0.requiredStarIDs.isEmpty && $0.requiredStarIDs.isSubset(of: collected) }
    }

    /// The garden and AR supply their own projection, including gyro roll and zoom.
    static func project(_ figures: [Self], basis: simd_double3x3?, size: CGSize,
                        point: (SIMD3<Double>) -> CGPoint?) -> [ProjectedConstellationFigure] {
        guard let basis, size.width > 0, size.height > 0 else { return [] }
        return figures.compactMap { item in
            let figure = item.figure
            guard (basis * figure.center).z > 0 else { return nil }
            let targets = figure.definition.anchors.compactMap { point(Refraction.apparent(basis * $0.equatorial)) }
            let sources = figure.definition.anchors.map { CGPoint(x: $0.pixel[0], y: $0.pixel[1]) }
            guard let transform = ConstellationFigureProjection.affine(source: sources, target: targets) else { return nil }
            let bounds = CGRect(x: 0, y: 0, width: figure.definition.size[0], height: figure.definition.size[1]).applying(transform)
            guard bounds.intersects(CGRect(origin: .zero, size: size)),
                bounds.width < size.width * 8, bounds.height < size.height * 8 else { return nil }
            return ProjectedConstellationFigure(figure: figure, transform: transform, opacity: 0.64)
        }
    }

    /// Clip artwork at the real horizon, even when the phone is rolled.
    static func skyClip(size: CGSize, height: (CGPoint) -> Double) -> [CGPoint] {
        let corners = [CGPoint.zero, CGPoint(x: size.width, y: 0),
                       CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height)]
        var output: [CGPoint] = []
        for (a, b) in zip(corners, corners.dropFirst() + [corners[0]]) {
            let ha = height(a), hb = height(b)
            if ha >= 0 { output.append(a) }
            if (ha >= 0) != (hb >= 0) {
                let t = ha / (ha - hb)
                output.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        return output
    }

}
