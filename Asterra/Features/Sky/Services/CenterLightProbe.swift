import CoreVideo
import Foundation

/// Measures brightness in the centre of a camera frame (luma plane), mapped from the on-screen circle.
nonisolated enum CenterLightProbe {
    struct Sample {
        let peak: Double
        let saturatedFraction: Double
        let surroundingMedian: Double
    }

    static func measure(_ buffer: CVPixelBuffer, viewSize: CGSize, radius: CGFloat) -> Sample? {
        guard CVPixelBufferGetPlaneCount(buffer) >= 1 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        // The preview is aspect-filled and rotated; the frame centre is the screen centre.
        let long = Double(max(width, height))
        let short = Double(min(width, height))
        let scale = max(
            long / Double(max(viewSize.height, viewSize.width)),
            short / Double(min(viewSize.width, viewSize.height)))
        let r = max(4, Double(radius) * scale)
        let cx = width / 2
        let cy = height / 2
        let outer = Int(r * 3)
        var peak = 0.0
        var core = 0
        var saturated = 0
        var ring: [UInt8] = []
        ring.reserveCapacity(4096)
        let step = max(1, Int(r / 20))
        for dy in stride(from: -outer, through: outer, by: step) {
            let y = cy + dy
            guard y >= 0, y < height else { continue }
            let row = pixels + y * rowBytes
            for dx in stride(from: -outer, through: outer, by: step) {
                let x = cx + dx
                guard x >= 0, x < width else { continue }
                let distance = (Double(dx * dx + dy * dy)).squareRoot()
                let value = row[x]
                if distance <= r {
                    core += 1
                    peak = max(peak, Double(value))
                    if value >= 235 { saturated += 1 }
                } else if distance >= r * 2 && distance <= r * 3 {
                    ring.append(value)
                }
            }
        }
        guard core > 0, !ring.isEmpty else { return nil }
        ring.sort()
        return Sample(
            peak: peak, saturatedFraction: Double(saturated) / Double(core),
            surroundingMedian: Double(ring[ring.count / 2]))
    }
}

/// Glass hint capsule used at the bottom of the camera screens.
