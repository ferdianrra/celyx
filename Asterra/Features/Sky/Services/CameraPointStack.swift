import CoreVideo
import Foundation
import simd

/// A small native-resolution patch, aligned by sensor rotation before averaging.
/// Owned by the serial analysis worker; each result returns its value to the main actor.
nonisolated struct CameraPointStack: Sendable {
    private struct Frame: Sendable {
        let time: TimeInterval
        let pixels: [Float]
    }
    private var frames: [Frame] = []
    private var referencePose = matrix_identity_float4x4
    private var referenceIntrinsics = matrix_identity_float3x3
    private var origin = SIMD2<Float>.zero
    private var width = 0
    private var height = 0
    private var resolution = SIMD2<Int>.zero
    private(set) var progress = 0.0

    mutating func reset() { self = Self() }

    static func isEligible(sunAltitude: Double, aimAltitude: Double) -> Bool {
        sunAltitude.isFinite && aimAltitude.isFinite && sunAltitude < -6 && aimAltitude >= 8
    }

    mutating func detect(
        in image: CVPixelBuffer, intrinsics: simd_float3x3, pose: simd_float4x4,
        time: TimeInterval, region: CGRect
    ) -> [CameraLightPoint] {
        let format = CVPixelBufferGetPixelFormatType(image)
        guard time.isFinite,
            format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            CVPixelBufferIsPlanar(image), CVPixelBufferGetPlaneCount(image) > 0
        else {
            reset()
            return []
        }
        let imageWidth = CVPixelBufferGetWidthOfPlane(image, 0)
        let imageHeight = CVPixelBufferGetHeightOfPlane(image, 0)
        let size = SIMD2(imageWidth, imageHeight)
        let region = region.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard imageWidth > 32, imageHeight > 32, !region.isNull, !region.isEmpty else {
            reset()
            return []
        }
        if let last = frames.last {
            guard time > last.time else { return [] }
            let facing = simd_dot(referencePose.columns.2, pose.columns.2)
            let distance = simd_distance(referencePose.columns.3, pose.columns.3)
            if time - last.time > 0.6 || facing < cos(6 * Float.pi / 180) || distance > 0.08
                || resolution != size
            {
                reset()
            }
        }
        if frames.isEmpty {
            width = min(192, max(32, Int(region.width * Double(imageWidth)))) / 2 * 2
            height = min(192, max(32, Int(region.height * Double(imageHeight)))) / 2 * 2
            origin = SIMD2(
                Float(region.midX * Double(imageWidth)) - Float(width) / 2,
                Float(region.midY * Double(imageHeight)) - Float(height) / 2)
            referencePose = pose
            referenceIntrinsics = intrinsics
            resolution = size
        }
        let flip = simd_float3x3(diagonal: SIMD3<Float>(1, -1, -1))
        func rotation(_ pose: simd_float4x4) -> simd_float3x3 {
            simd_float3x3(
                SIMD3(pose.columns.0.x, pose.columns.0.y, pose.columns.0.z),
                SIMD3(pose.columns.1.x, pose.columns.1.y, pose.columns.1.z),
                SIMD3(pose.columns.2.x, pose.columns.2.y, pose.columns.2.z))
        }
        let warp =
            intrinsics * flip * simd_transpose(rotation(pose)) * rotation(referencePose) * flip
            * simd_inverse(referenceIntrinsics)
        guard let pixels = sample(image, warp: warp) else {
            reset()
            return []
        }
        frames.removeAll { time - $0.time > 1.8 }
        frames.append(Frame(time: time, pixels: pixels))
        if frames.count > 8 { frames.removeFirst(frames.count - 8) }
        progress = min(1, Double(frames.count) / 6)
        guard frames.count >= 6, let averaged = averagedImage() else { return [] }
        let sources = CameraStarDetector.detect(
            in: averaged, focusRegion: CGRect(x: 0, y: 0, width: 1, height: 1), isStacked: true)
        return sources.compactMap { source in
            let x = Float(source.point.x) * Float(width)
            let y = Float(source.point.y) * Float(height)
            guard hasTemporalSupport(x: Int(x.rounded()), y: Int(y.rounded())) else { return nil }
            func project(_ point: CGPoint) -> CGPoint {
                let p =
                    warp
                    * SIMD3(
                        origin.x + Float(point.x) * Float(width), origin.y + Float(point.y) * Float(height), 1
                    )
                return CGPoint(
                    x: Double(p.x / p.z) / Double(imageWidth), y: Double(p.y / p.z) / Double(imageHeight))
            }
            let a = project(source.bounds.origin)
            let b = project(CGPoint(x: source.bounds.maxX, y: source.bounds.maxY))
            return CameraLightPoint(
                point: project(source.point),
                bounds: CGRect(
                    x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)),
                contrast: source.contrast)
        }
    }

    // MARK: Motion-compensated pixels

    private func sample(_ image: CVPixelBuffer, warp: simd_float3x3) -> [Float]? {
        CVPixelBufferLockBaseAddress(image, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(image, 0) else { return nil }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let row = CVPixelBufferGetBytesPerRowOfPlane(image, 0)
        var pixels = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let p = warp * SIMD3(origin.x + Float(x), origin.y + Float(y), 1)
                guard p.z > 0 else { return nil }
                let sx = p.x / p.z
                let sy = p.y / p.z
                guard sx.isFinite, sy.isFinite, sx >= 0, sy >= 0,
                    sx < Float(resolution.x - 1), sy < Float(resolution.y - 1)
                else { return nil }
                let ix = Int(sx)
                let iy = Int(sy)
                let dx = sx - Float(ix)
                let dy = sy - Float(iy)
                let a = Float(bytes[iy * row + ix]) * (1 - dx) + Float(bytes[iy * row + ix + 1]) * dx
                let b =
                    Float(bytes[(iy + 1) * row + ix]) * (1 - dx) + Float(bytes[(iy + 1) * row + ix + 1]) * dx
                pixels[y * width + x] = a * (1 - dy) + b * dy
            }
        }
        return pixels
    }

    private func averagedImage() -> CVPixelBuffer? {
        var image: CVPixelBuffer?
        guard
            CVPixelBufferCreate(
                kCFAllocatorDefault, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                nil, &image) == kCVReturnSuccess, let image
        else { return nil }
        CVPixelBufferLockBaseAddress(image, [])
        defer { CVPixelBufferUnlockBaseAddress(image, []) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(image, 0) else { return nil }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let row = CVPixelBufferGetBytesPerRowOfPlane(image, 0)
        for y in 0..<height {
            for x in 0..<width {
                // A trimmed mean keeps one-frame bright/dark outliers from polluting
                // the stack while retaining independent raw-frame support checks.
                var sum: Float = 0
                var low = Float.greatestFiniteMagnitude
                var high = -Float.greatestFiniteMagnitude
                for frame in frames {
                    let pixel = frame.pixels[y * width + x]
                    sum += pixel; low = min(low, pixel); high = max(high, pixel)
                }
                let value = (sum - low - high) / Float(frames.count - 2)
                bytes[y * row + x] = UInt8(clamping: Int(value.rounded()))
            }
        }
        return image
    }

    /// Overlapping averages do not count as independent sightings: the raw patches must agree.
    private func hasTemporalSupport(x: Int, y: Int) -> Bool {
        guard x >= 7, y >= 7, x < width - 7, y < height - 7 else { return false }
        let signals = frames.map { frame -> Float in
            var signal: Float = 0
            for dy in -1...1 { for dx in -1...1 { signal += frame.pixels[(y + dy) * width + x + dx] } }
            // A close annulus removes a broad glow's pedestal, not just distant sky.
            let ring = [-3, 0, 3].flatMap { dy in
                [-3, 0, 3].compactMap { dx -> Float? in
                    dx == 0 && dy == 0 ? nil : frame.pixels[(y + dy) * width + x + dx]
                }
            }
            return signal / 9 - ring.reduce(0, +) / Float(ring.count)
        }
        guard let latest = signals.last, latest > 1.2,
            signals.reduce(0, +) / Float(signals.count) > 1.5
        else { return false }
        let support = signals.filter { $0 > 1.2 }.count
        return support >= max(4, Int(ceil(Double(frames.count) * 0.65)))
    }
}
