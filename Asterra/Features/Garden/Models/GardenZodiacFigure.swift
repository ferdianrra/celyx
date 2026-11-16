import CoreGraphics
import Foundation
import simd

/// Zodiac artwork unlocks from the complete bundled line pattern, not simply constellation membership.
struct GardenZodiacFigure: Identifiable {
    static let codes: Set<String> = ["Ari", "Tau", "Gem", "Cnc", "Leo", "Vir", "Lib", "Sco", "Sgr", "Cap", "Aqr", "Psc"]
    private struct Artwork: Decodable {
        let assetName: String
        let referenceCanvas: ReferenceCanvas?
        let alignmentStarIDs: [Int]
    }

    /// The original canvas's offset and uniform size within an image with transparent padding.
    private struct ReferenceCanvas: Decodable {
        let x: Double
        let y: Double
        let scale: Double

        var fitsImage: Bool {
            x >= 0 && y >= 0 && scale > 0 && x + scale <= 1 && y + scale <= 1
        }
    }

    let assetName: String
    let figure: ConstellationFigure
    let requiredStarIDs: Set<Int>
    let alignmentStarIDs: [Int]
    var id: String { figure.id }

    static func load() -> [Self] {
        let patterns = GardenConstellationConnection.loadFigures()
        guard let url = try? SkyAssets.url("zodiac-artwork", extension: "json"),
              let data = try? Data(contentsOf: url),
              let artwork = try? JSONDecoder().decode([String: Artwork].self, from: data) else { return [] }
        return ((try? ConstellationFigure.load()) ?? []).compactMap { figure in
            guard codes.contains(figure.id), let pattern = patterns[figure.id],
                  let asset = artwork[figure.id], !asset.assetName.isEmpty else { return nil }
            let required = Set(pattern.segments.flatMap { $0 })
            guard !required.isEmpty else { return nil }
            guard let canvas = asset.referenceCanvas else {
                return Self(assetName: asset.assetName, figure: figure, requiredStarIDs: required,
                            alignmentStarIDs: asset.alignmentStarIDs)
            }
            guard canvas.fitsImage else { return nil }
            let definition = figure.definition
            let anchors = definition.anchors.map { anchor in
                ConstellationFigure.Anchor(
                    pixel: [canvas.x * definition.size[0] + canvas.scale * anchor.pixel[0],
                            canvas.y * definition.size[1] + canvas.scale * anchor.pixel[1]],
                    ra_deg: anchor.ra_deg, dec_deg: anchor.dec_deg)
            }
            let padded = ConstellationFigure(id: figure.id,
                definition: .init(file: definition.file, size: definition.size, anchors: anchors), center: figure.center)
            return Self(assetName: asset.assetName, figure: padded, requiredStarIDs: required,
                        alignmentStarIDs: asset.alignmentStarIDs)
        }
    }

    static func unlocked(_ figures: [Self], collected: Set<Int>) -> [Self] {
        figures.filter { !$0.requiredStarIDs.isEmpty && $0.requiredStarIDs.isSubset(of: collected) }
    }

    /// The garden and AR supply their own projection, including gyro roll and zoom.
    static func project(_ figures: [Self], basis: simd_double3x3?, size: CGSize, forward: SIMD3<Double>,
                        point: (SIMD3<Double>) -> CGPoint?) -> [ProjectedConstellationFigure] {
        guard let basis, size.width > 0, size.height > 0 else { return [] }
        return figures.compactMap { item in
            let figure = item.figure
            guard (basis * figure.center).z > 0 else { return nil }
            let directions = figure.definition.anchors.map { Refraction.apparent(basis * $0.equatorial) }
            // Keep the existing distance from the camera plane as a safety limit.
            let depth = directions.map { simd_dot(forward, $0) }.min() ?? 0
            guard depth > 0.6 else { return nil }
            let targets = directions.compactMap(point)
            // Measure the extra deformation from the camera angle against a centered view.
            // Preserve the exact anchor fit and fade the artwork before the distortion is pronounced.
            let stretch = cameraStretch(directions: directions, targets: targets)
            let shapeVisibility = min(1, (1.28 - stretch) / (1.28 - 1.10))
            guard shapeVisibility > 0 else { return nil }
            let fade = min(shapeVisibility, (depth - 0.6) / 0.24)
            let sources = figure.definition.anchors.map { CGPoint(x: $0.pixel[0], y: $0.pixel[1]) }
            guard let transform = ConstellationFigureProjection.affine(source: sources, target: targets) else { return nil }
            let bounds = CGRect(x: 0, y: 0, width: figure.definition.size[0], height: figure.definition.size[1]).applying(transform)
            guard bounds.intersects(CGRect(origin: .zero, size: size)),
                bounds.width < size.width * 8, bounds.height < size.height * 8 else { return nil }
            return ProjectedConstellationFigure(figure: figure, transform: transform, opacity: 0.64 * fade * fade * (3 - 2 * fade))
        }
    }

    /// Ratio of the two principal stretches. Translation, zoom and camera roll do not affect it.
    private static func cameraStretch(directions: [SIMD3<Double>], targets: [CGPoint]) -> Double {
        guard directions.count == 3, targets.count == 3 else { return .infinity }
        let center = simd_normalize(directions.reduce(SIMD3<Double>.zero, +))
        let right = simd_normalize(simd_cross(center, directions[0]))
        let up = simd_cross(right, center)
        let centered = directions.map { direction -> CGPoint in
            let scale = 512 / simd_dot(direction, center)
            return CGPoint(x: simd_dot(direction, right) * scale, y: simd_dot(direction, up) * scale)
        }
        guard let transform = ConstellationFigureProjection.affine(source: centered, target: targets) else {
            return .infinity
        }
        let (a, b, c, d) = (transform.a, transform.b, transform.c, transform.d)
        let area = abs(a * d - b * c)
        guard area > 0 else { return .infinity }
        // For singular values s1 >= s2, this is s1/s2 + s2/s1.
        let sum = max(2, (a * a + b * b + c * c + d * d) / area)
        return Double((sum + sqrt((sum - 2) * (sum + 2))) / 2)
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
