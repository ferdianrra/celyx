import CoreGraphics
import CoreImage
import Foundation
import UIKit

nonisolated struct GardenZodiacArtwork: Sendable {
    let image: CGImage
    let glow: CGImage?
}

/// Decode once away from the main actor; keep both the artwork and its pre-rendered glow.
actor GardenZodiacArtworkStore {
    static let shared = GardenZodiacArtworkStore()
    private lazy var context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])

    private var assetCache: [String: GardenZodiacArtwork] = [:]

    func load(assetNamed name: String) async -> GardenZodiacArtwork? {
        if let cached = assetCache[name] { return cached }
        // Asset catalogs are resolved once on the main actor; resizing and glow remain off-main.
        let source = await MainActor.run { UIImage(named: name)?.cgImage }
        if let cached = assetCache[name] { return cached }
        guard let source else { return nil }
        let scale = min(1, 512 / CGFloat(max(source.width, source.height)))
        let width = max(1, Int((CGFloat(source.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(source.height) * scale).rounded()))
        // Bake a regular RGBA bitmap so Core Animation and snapshot rendering share the same pixels.
        guard let bitmap = CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        bitmap.interpolationQuality = .high
        bitmap.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = bitmap.makeImage() else { return nil }
        let artwork = prepare(image)
        assetCache[name] = artwork
        return artwork
    }

    private func prepare(_ image: CGImage) -> GardenZodiacArtwork {
        let input = CIImage(cgImage: image)
        let blurred = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 4])
            .cropped(to: input.extent)
        return GardenZodiacArtwork(image: image, glow: context.createCGImage(blurred, from: input.extent))
    }

}
