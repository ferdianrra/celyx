import CoreVideo
import Foundation
import simd

/// Rejects positive foreground evidence. A compact light alone cannot prove that
/// it is astronomical, so catalog matching must never stand in for this check.
nonisolated enum CameraSkyContext {
    static func permits(_ point: CGPoint, in image: CVPixelBuffer, isDisc: Bool = false, sourceBounds: CGRect? = nil) -> Bool {
        guard CVPixelBufferGetPlaneCount(image) > 0 else { return false }
        CVPixelBufferLockBaseAddress(image, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(image, 0) else { return false }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let width = CVPixelBufferGetWidthOfPlane(image, 0)
        let height = CVPixelBufferGetHeightOfPlane(image, 0)
        let row = CVPixelBufferGetBytesPerRowOfPlane(image, 0)
        let cx = Int(point.x * Double(width))
        let cy = Int(point.y * Double(height))
        let radius = max(24, min(72, width / 30))
        let step = max(2, radius / 12)
        // A solar disc's own bright rim is not foreground texture. Inspect the
        // surroundings outside its measured extent instead of rejecting that rim.
        let excludedCore = isDisc ? max(Double(radius) * 0.25,
            max((sourceBounds?.width ?? 0) * Double(width), (sourceBounds?.height ?? 0) * Double(height)) * 0.6)
            : Double(radius) * 0.25
        guard cx - radius >= 0, cy - radius >= 0, cx + radius < width, cy + radius < height else {
            return false
        }
        // A resolved disc has already passed the optical shape/core checks.
        // Cloud edges and scattering around a visible solar rim are valid sky;
        // the point-source texture veto would incorrectly erase these detections.
        // The service still requires a matching solar ephemeris and fresh consensus.
        if isDisc, let sourceBounds, sourceBounds.width.isFinite, sourceBounds.height.isFinite,
            sourceBounds.width > 0, sourceBounds.height > 0, sourceBounds.contains(point) { return true }
        func value(_ x: Int, _ y: Int) -> Int { Int(bytes[y * row + x]) }
        var differences: [Int] = []
        for y in stride(from: cy - radius, through: cy + radius, by: step) {
            for x in stride(from: cx - radius, through: cx + radius - 1, by: step)
            where hypot(Double(x - cx), Double(y - cy)) > excludedCore {
                differences.append(abs(value(x + 1, y) - value(x, y)))
            }
        }
        differences.sort()
        let edgeThreshold = max(6, (differences.isEmpty ? 0 : differences[differences.count / 2]) * 5)
        var edges = 0
        var samples = 0
        var longest = 0
        var inner: [Int] = []
        var outer: [Int] = []
        for y in stride(from: cy - radius + step, through: cy + radius - step, by: step) {
            var run = 0
            for x in stride(from: cx - radius + step, through: cx + radius - step, by: step) {
                let distance = hypot(Double(x - cx), Double(y - cy))
                guard distance > excludedCore else {
                    run = 0
                    continue
                }
                let gradient = max(
                    abs(value(x + step, y) - value(x - step, y)), abs(value(x, y + step) - value(x, y - step))
                )
                if gradient >= edgeThreshold {
                    edges += 1
                    run += 1
                    longest = max(longest, run)
                } else {
                    run = 0
                }
                samples += 1
                if distance < Double(radius) * 0.5 { inner.append(value(x, y)) }
                if distance > Double(radius) * 0.8 { outer.append(value(x, y)) }
            }
        }
        // Roof/window edges and textured structures, excluding the star's own core.
        if samples > 0, Double(edges) / Double(samples) > 0.16 || longest >= 10 { return false }
        // A large illuminated halo is characteristic of a nearby light fixture.
        inner.sort()
        outer.sort()
        if !isDisc, !inner.isEmpty, !outer.isEmpty, inner[inner.count / 2] - outer[outer.count / 2] > 18 {
            return false
        }
        return true
    }
}
