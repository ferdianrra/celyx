import CoreImage
import CoreVideo
import Foundation

/// Photo-only tonal adjustment. Coordinates and black pixels stay unchanged;
/// no catalog markers, synthetic stars, or extra glow are drawn into the image.
nonisolated enum StarCaptureEnhancement {
    static func process(_ image: CIImage) -> CIImage {
        image.applyingFilter("CIExposureAdjust", parameters: ["inputEV": 1.25])
            .applyingFilter("CIGammaAdjust", parameters: ["inputPower": 0.72])
            .cropped(to: image.extent)
    }

    /// Rank actual frames by the light's contrast against its local surroundings.
    static func contrast(in buffer: CVPixelBuffer, at point: CGPoint) -> Double {
        guard point.x.isFinite, point.y.isFinite,
            CVPixelBufferGetPlaneCount(buffer) > 0
        else { return 0 }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return 0 }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let row = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let x = Int(point.x * Double(width))
        let y = Int(point.y * Double(height))
        guard x >= 12, y >= 12, x < width - 12, y < height - 12 else { return 0 }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var peak = 0
        var background: [Int] = []
        for dy in -12...12 {
            for dx in -12...12 {
                let value = Int(bytes[(y + dy) * row + x + dx])
                if abs(dx) <= 3 && abs(dy) <= 3 {
                    peak = max(peak, value)
                } else if dx * dx + dy * dy >= 64 {
                    background.append(value)
                }
            }
        }
        background.sort()
        return Double(max(0, peak - background[background.count / 2]))
    }
}
