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
    /// Every limit fades the artwork out gradually (it never pops): the camera-plane distance
    /// (`depthLimit`, relaxed for the garden's stereographic dome), uneven stretch, sinking below the
    /// horizon, and growing far larger than the screen at deep zoom.
    static func project(_ figures: [Self], basis: simd_double3x3?, size: CGSize, forward: SIMD3<Double>,
                        depthLimit: Double = 0.6,
                        point: (SIMD3<Double>) -> CGPoint?) -> [ProjectedConstellationFigure] {
        guard let basis, size.width > 0, size.height > 0 else { return [] }
        func smooth(_ x: Double) -> Double { let t = min(1, max(0, x)); return t * t * (3 - 2 * t) }
        return figures.compactMap { item in
            let figure = item.figure
            // The centre may dip a little below the horizon while the figure fades; the sky mask
            // softens the horizon itself.
            let centerAltitude = (basis * figure.center).z
            let horizonFade = (centerAltitude + 0.08) / 0.12
            guard horizonFade > 0 else { return nil }
            let directions = figure.definition.anchors.map { Refraction.apparent(basis * $0.equatorial) }
            // Keep a distance from the camera plane as a safety limit.
            let depth = directions.map { simd_dot(forward, $0) }.min() ?? 0
            guard depth > depthLimit else { return nil }
            let targets = directions.compactMap(point)
            // Measure the extra deformation from the camera angle against a centered view.
            // Preserve the exact anchor fit and fade the artwork before the distortion is pronounced.
            let stretch = cameraStretch(directions: directions, targets: targets)
            let shapeVisibility = min(1, (1.28 - stretch) / (1.28 - 1.10))
            guard shapeVisibility > 0 else { return nil }
            let sources = figure.definition.anchors.map { CGPoint(x: $0.pixel[0], y: $0.pixel[1]) }
            guard let transform = ConstellationFigureProjection.affine(source: sources, target: targets) else { return nil }
            let bounds = CGRect(x: 0, y: 0, width: figure.definition.size[0], height: figure.definition.size[1]).applying(transform)
            let oversize = max(bounds.width / size.width, bounds.height / size.height)
            guard bounds.intersects(CGRect(origin: .zero, size: size)), oversize < 8 else { return nil }
            let fade = min(shapeVisibility, (depth - depthLimit) / 0.24, horizonFade, (8 - oversize) / 5)
            return ProjectedConstellationFigure(figure: figure, transform: transform, opacity: 0.64 * smooth(fade))
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

    /// Soft horizon mask for the artwork: a small alpha image (stretched with linear filtering)
    /// that is clear below the real horizon and fades in over ~2° above it. Sampling the true
    /// height per cell follows phone roll and the curved horizon of the stereographic dome.
    /// `height` is the sine of the altitude at a screen point.
    static func skyMask(size: CGSize, columns: Int = 24, height: (CGPoint) -> Double) -> CGImage? {
        guard size.width > 0, size.height > 0, columns > 1 else { return nil }
        let rows = max(2, Int((Double(columns) * size.height / size.width).rounded()))
        // Premultiplied white: a layer mask only reads the alpha channel.
        var pixels = [UInt8](repeating: 0, count: columns * rows * 4)
        for row in 0..<rows {
            for column in 0..<columns {
                let point = CGPoint(x: (Double(column) + 0.5) / Double(columns) * size.width,
                                    y: (Double(row) + 0.5) / Double(rows) * size.height)
                let t = min(1, max(0, height(point) / horizonBand))
                let value = UInt8((t * t * (3 - 2 * t) * 255).rounded())
                let i = (row * columns + column) * 4
                pixels[i] = value; pixels[i + 1] = value; pixels[i + 2] = value; pixels[i + 3] = value
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: columns, height: rows, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: columns * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Altitude band (sine, ~2°) over which artwork fades in above the horizon.
    static let horizonBand = 0.035

}
