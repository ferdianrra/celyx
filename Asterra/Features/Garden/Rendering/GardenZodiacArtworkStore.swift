import CoreGraphics
import CoreImage
import Foundation
import ImageIO

nonisolated struct GardenZodiacArtwork: Sendable {
    let image: CGImage
    let glow: CGImage?
}

/// Decode once away from the main actor; keep both the artwork and its pre-rendered glow.
actor GardenZodiacArtworkStore {
    static let shared = GardenZodiacArtworkStore()
    private var cache: [URL: GardenZodiacArtwork] = [:]
    private lazy var context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])

    func load(_ url: URL) -> GardenZodiacArtwork? {
        if let cached = cache[url] { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary)
        else { return nil }
        let input = CIImage(cgImage: image)
        let blurred = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 4])
            .cropped(to: input.extent)
        let artwork = GardenZodiacArtwork(image: image, glow: context.createCGImage(blurred, from: input.extent))
        cache[url] = artwork
        return artwork
    }
}
