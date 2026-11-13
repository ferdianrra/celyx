import CoreGraphics
import CoreVideo
import Foundation
import simd

nonisolated struct CameraLightPoint: Sendable {
    let point: CGPoint  // normalized unrotated camera-image coordinates
    let bounds: CGRect
    let contrast: Double
    var isDisc = false
}
struct CameraLightAnnotation: Identifiable {
    let id: Int
    let point: CGPoint
    let size: CGSize
    var issue: CameraIdentificationIssue = .stabilizing
}
struct CameraOpticalTrack {
    let id: Int
    let hits: Int
    let direction: SIMD3<Float>
    let size: CGSize
    let time: TimeInterval
    var isDisc = false
    var screenPoint: CGPoint? = nil
    var firstSeen: TimeInterval = 0
}
struct CameraStarAnnotation: Identifiable {
    let star: CatalogStar
    let point: CGPoint
    let size: CGSize
    var estimatedSeparation: Double? = nil
    var sourceDirection: SIMD3<Float>? = nil
    var observedAt: TimeInterval? = nil
    var id: Int { star.id }
}

/// Catalog projections and optical observations stay separate: a projection is not evidence of visibility.
struct CameraMappedObject: Identifiable {
    let star: CatalogStar
    let point: CGPoint
    var likelyVisible = false
    var id: Int { star.id }
}

// Retain one read-only camera buffer while the worker analyzes it. No mutable pixel access escapes.
nonisolated struct CameraAnalysisBuffer: @unchecked Sendable {
    let value: CVPixelBuffer
}

struct CameraSkyPrediction: Identifiable {
    let direction: SIMD3<Float>
    let star: CatalogStar
    let guide: SkyFinderProjection
    var id: Int { star.id }
}

struct CameraAimTarget {
    let object: CameraMappedObject
    let detection: CameraStarAnnotation?
    var id: Int { object.id }
}

nonisolated enum CameraStarDetector {
    // Compact high-contrast sources only. Extended lights and isolated hot pixels are rejected.
    static func detect(
        in image: CVPixelBuffer, zoom: Double = 1, focusRegion: CGRect? = nil,
        isStacked: Bool = false
    ) -> [CameraLightPoint] {
        let format = CVPixelBufferGetPixelFormatType(image)
        guard
            format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            CVPixelBufferIsPlanar(image), CVPixelBufferGetPlaneCount(image) > 0
        else { return [] }
        CVPixelBufferLockBaseAddress(image, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(image, 0) else { return [] }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let width = CVPixelBufferGetWidthOfPlane(image, 0)
        let height = CVPixelBufferGetHeightOfPlane(image, 0)
        let row = CVPixelBufferGetBytesPerRowOfPlane(image, 0)
        // Bright planets and mildly defocused stars can have a wider PSF than six
        // pixels. The flood fill must cover that core before judging its compactness.
        let radius = min(20, max(10, Int(10 * sqrt(max(1, zoom)))))
        let ringRadius = radius + 1
        let margin = ringRadius + 3
        let maxArea = Int(45 * min(5, max(1, zoom)))
        let maxDiameter = Int(12 * sqrt(max(1, zoom)))
        guard width > margin * 2, height > margin * 2 else { return [] }
        // Use local contrast: a bright horizon elsewhere must not hide a faint source.
        let search = (focusRegion ?? CGRect(x: 0, y: 0, width: 1, height: 1))
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !search.isNull, !search.isEmpty else { return [] }
        let minSearchX = max(margin, Int(floor(search.minX * Double(width))))
        let minSearchY = max(margin, Int(floor(search.minY * Double(height))))
        let maxSearchX = min(width - margin, Int(ceil(search.maxX * Double(width))))
        let maxSearchY = min(height - margin, Int(ceil(search.maxY * Double(height))))
        var result: [CameraLightPoint] = []
        for y in stride(from: minSearchY, to: maxSearchY, by: 3) {
            for x in stride(from: minSearchX, to: maxSearchX, by: 3) {
                var px = x
                var py = y
                var peak = 0
                for dy in 0..<3 {
                    for dx in 0..<3 {
                        let value = Int(bytes[(y + dy) * row + x + dx])
                        if value > peak {
                            peak = value
                            px = x + dx
                            py = y + dy
                        }
                    }
                }
                guard peak >= 4 else { continue }
                // Four symmetric samples cancel a smooth illumination gradient cheaply.
                let coarseBackground =
                    (Double(bytes[(py - ringRadius) * row + px - ringRadius])
                        + Double(bytes[(py - ringRadius) * row + px + ringRadius])
                        + Double(bytes[(py + ringRadius) * row + px - ringRadius])
                        + Double(bytes[(py + ringRadius) * row + px + ringRadius])) / 4
                guard Double(peak) - coarseBackground >= 2.5 else { continue }
                let normalized = CGPoint(x: Double(px) / Double(width), y: Double(py) / Double(height))
                guard
                    !result.contains(where: {
                        hypot(
                            ($0.point.x - normalized.x) * Double(width),
                            ($0.point.y - normalized.y) * Double(height)) < 10
                    })
                else { continue }
                let focused = focusRegion?.contains(normalized) ?? false
                var ring: [Double] = []
                for dy in [-ringRadius, 0, ringRadius] {
                    for dx in [-ringRadius, 0, ringRadius] where dx != 0 || dy != 0 {
                        ring.append(Double(bytes[(py + dy) * row + px + dx]))
                    }
                }
                let sorted = ring.sorted()
                let background = (sorted[3] + sorted[4]) / 2
                // Fit a local background plane so haze/sky gradients aren't mistaken for noise.
                let slopeX = (-ring[0] + ring[2] - ring[3] + ring[4] - ring[5] + ring[7]) / 6
                let slopeY = (-ring[0] - ring[1] - ring[2] + ring[5] + ring[6] + ring[7]) / 6
                let offsets: [(Double, Double)] = [
                    (-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1),
                ]
                let deviations = zip(ring, offsets).map {
                    abs($0.0 - background - slopeX * $0.1.0 - slopeY * $0.1.1)
                }.sorted()
                let deviation = max(0.8, (deviations[3] + deviations[4]) / 2 * 1.4826)
                let contrast = Double(peak) - background
                guard background < 185, contrast > max(focused ? 3 : 4, deviation * (focused ? 3 : 4))
                else { continue }
                // A real soft point has spatial support around its peak. Averaging the
                // signed 3x3 signal rejects grain riding on a broad glow, even in focus mode.
                var coreSignal = 0.0
                for dy in -1...1 {
                    for dx in -1...1 {
                        coreSignal += Double(bytes[(py + dy) * row + px + dx]) - background
                    }
                }
                // Only a motion-aligned temporal average may use the lower core-signal floor.
                // Its caller also requires support in several independent raw frames.
                guard coreSignal / 9 > max(isStacked ? 1.2 : 3.5, contrast * 0.18) else { continue }
                let threshold = max(focused ? 1.5 : 2, max(deviation * 2, contrast * 0.28))
                func backgroundAt(_ x: Int, _ y: Int) -> Double {
                    background + slopeX * Double(x - px) / Double(ringRadius) + slopeY * Double(y - py)
                        / Double(ringRadius)
                }
                var queue = [(px, py)]
                var visited: Set<Int> = [py * width + px]
                var cursor = 0
                var count = 0
                var sum = 0.0
                var sx = 0.0
                var sy = 0.0
                var minX = px
                var maxX = px
                var minY = py
                var maxY = py
                let areaLimit = focused ? maxArea * 2 : maxArea
                let diameterLimit = focused ? Int(Double(maxDiameter) * 1.5) : maxDiameter
                while cursor < queue.count && queue.count <= areaLimit + 10 {
                    let (cx, cy) = queue[cursor]
                    cursor += 1
                    let weight = Double(bytes[cy * row + cx]) - backgroundAt(cx, cy)
                    count += 1
                    sum += weight
                    sx += Double(cx) * weight
                    sy += Double(cy) * weight
                    minX = min(minX, cx)
                    maxX = max(maxX, cx)
                    minY = min(minY, cy)
                    maxY = max(maxY, cy)
                    for dy in -1...1 {
                        for dx in -1...1 where dx != 0 || dy != 0 {
                            let nx = cx + dx
                            let ny = cy + dy
                            guard abs(nx - px) <= radius, abs(ny - py) <= radius else { continue }
                            let key = ny * width + nx
                            guard !visited.contains(key),
                                Double(bytes[ny * row + nx]) - backgroundAt(nx, ny) >= threshold
                            else { continue }
                            visited.insert(key)
                            queue.append((nx, ny))
                        }
                    }
                }
                let bw = maxX - minX + 1
                let bh = maxY - minY + 1
                guard count >= 2, count <= areaLimit, bw < diameterLimit, bh < diameterLimit,
                    minX > px - radius, maxX < px + radius, minY > py - radius, maxY < py + radius,
                    Double(max(bw, bh)) / Double(max(1, min(bw, bh))) <= 2.5,
                    sum / (deviation * sqrt(Double(count))) >= (focused ? 5 : 6)
                else { continue }
                result.append(
                    CameraLightPoint(
                        point: CGPoint(x: sx / sum / Double(width), y: sy / sum / Double(height)),
                        bounds: CGRect(
                            x: Double(minX) / Double(width), y: Double(minY) / Double(height),
                            width: Double(bw) / Double(width), height: Double(bh) / Double(height)),
                        contrast: Double(peak) - background))
                if result.count > 200 {
                    result.sort { $0.contrast > $1.contrast }
                    result.removeSubrange(80...)
                }
            }
        }
        return result.sorted { $0.contrast > $1.contrast }.prefix(50).map { $0 }
    }
    // Larger bright discs (Sun/Moon) do not pass the compact star-point detector.
    static func detectDiscs(in image: CVPixelBuffer, daylight: Bool = false) -> [CameraLightPoint] {
        let format = CVPixelBufferGetPixelFormatType(image)
        guard
            format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            CVPixelBufferIsPlanar(image), CVPixelBufferGetPlaneCount(image) > 0
        else { return [] }
        CVPixelBufferLockBaseAddress(image, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(image, 0) else { return [] }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let width = CVPixelBufferGetWidthOfPlane(image, 0)
        let height = CVPixelBufferGetHeightOfPlane(image, 0)
        let row = CVPixelBufferGetBytesPerRowOfPlane(image, 0)
        let step = max(3, max(width, height) / 320)
        let w = width / step
        let h = height / step
        guard w > 4, h > 4 else { return [] }
        var values = [Int](repeating: 0, count: w * h)
        // Use one photometric scale: video-range white is 235, not 255.
        // Otherwise a small cloud-filtered solar core merges with its halo at 220.
        let videoRange = format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        for y in 0..<h { for x in 0..<w {
            let raw = Int(bytes[y * step * row + x * step])
            values[y * w + x] = videoRange ? min(255, max(0, (raw - 16) * 255 / 219)) : raw
        } }
        let sorted = values.sorted()
        let background = sorted[sorted.count / 2]
        // A single low threshold joins the Sun to illuminated cloud edges.
        // Resolve the saturated core first, then the lower-contrast lunar disc.
        let peakLevel = sorted[sorted.count - 1]
        let thresholds = Array(Set([peakLevel - 5, peakLevel - 15, peakLevel - 35, max(160, background + 30)]
            .filter { $0 > background && $0 > 0 && $0 <= 250 })).sorted(by: >)
        // Thin cloud attenuates the solar core. Keep both an absolute floor and
        // local scene contrast, instead of demanding nearly clipped white.
        let minimumCore = daylight ? max(180, min(240, background + 25)) : 0
        var result: [CameraLightPoint] = []
        for threshold in thresholds {
            // Distance to the dark boundary separates round bright lobes even when
            // a narrow illuminated cloud edge touches the solar core.
            var distance = values.map { $0 >= threshold ? Float(w + h) : 0 }
            let diagonal: Float = 1.4142136
            for y in 0..<h { for x in 0..<w where distance[y * w + x] > 0 {
                let i = y * w + x
                if x == 0 || y == 0 || x == w - 1 || y == h - 1 { distance[i] = 1; continue }
                distance[i] = min(distance[i], distance[i - 1] + 1, distance[i - w] + 1,
                                  distance[i - w - 1] + diagonal, distance[i - w + 1] + diagonal)
            } }
            for y in stride(from: h - 2, through: 1, by: -1) { for x in stride(from: w - 2, through: 1, by: -1) where distance[y * w + x] > 0 {
                let i = y * w + x
                distance[i] = min(distance[i], distance[i + 1] + 1, distance[i + w] + 1,
                                  distance[i + w - 1] + diagonal, distance[i + w + 1] + diagonal)
            } }
            var visited = [Bool](repeating: false, count: w * h)
            for start in values.indices where !visited[start] && values[start] >= threshold {
                var queue = [start]
                var cursor = 0
                visited[start] = true
                var minX = start % w
                var maxX = minX
                var minY = start / w
                var maxY = minY
                var sum = 0.0
                var sx = 0.0
                var sy = 0.0
                var peak = 0
                while cursor < queue.count {
                    let index = queue[cursor]
                    cursor += 1
                    let x = index % w
                    let y = index / w
                    let weight = Double(values[index] - background)
                    sum += weight
                    sx += Double(x) * weight
                    sy += Double(y) * weight
                    peak = max(peak, values[index])
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let nx = x + dx
                        let ny = y + dy
                        guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
                        let next = ny * w + nx
                        if !visited[next] && values[next] >= threshold {
                            visited[next] = true
                            queue.append(next)
                        }
                    }
                }
                let bw = maxX - minX + 1
                let bh = maxY - minY + 1
                guard queue.count >= 3, sum > 0 else { continue }
                let fill = Double(queue.count) / Double(bw * bh)
                // A filled rectangular window must never be split into a solar core.
                if queue.count >= 16, fill > 0.95 { continue }
                let compact = queue.count < w * h / 12 && minX > 0 && minY > 0 && maxX < w - 1 && maxY < h - 1
                    && Double(max(bw, bh)) / Double(min(bw, bh)) < 1.65 && fill > 0.55
                if !compact {
                    // Local inscribed circles survive a connection to a bright cloud.
                    // Most of their circumference must still have a darker exterior.
                    let peaks = queue.filter { index in
                        let r = distance[index], x = index % w, y = index / w
                        guard values[index] >= minimumCore, r >= (daylight ? 2 : 3), r < Float(min(w, h)) / 5, x > 0, y > 0, x < w - 1, y < h - 1 else { return false }
                        return [-w - 1, -w, -w + 1, -1, 1, w - 1, w, w + 1].allSatisfy { distance[index + $0] <= r }
                    }.sorted { distance[$0] > distance[$1] }
                    for index in peaks {
                        let x = Double(index % w), y = Double(index / w), r = Double(distance[index])
                        var exterior = 0
                        for angle in 0..<32 {
                            let a = Double(angle) * .pi / 16
                            let px = Int((x + cos(a) * r * 1.3).rounded()), py = Int((y + sin(a) * r * 1.3).rounded())
                            if px >= 0, py >= 0, px < w, py < h, values[py * w + px] < threshold { exterior += 1 }
                        }
                        guard exterior >= 18 else { continue }
                        let center = CGPoint(x: (x + 0.5) * Double(step) / Double(width), y: (y + 0.5) * Double(step) / Double(height))
                        guard !result.contains(where: { $0.bounds.contains(center) }) else { continue }
                        result.append(CameraLightPoint(point: center,
                            bounds: CGRect(x: (x - r) * Double(step) / Double(width), y: (y - r) * Double(step) / Double(height),
                                           width: r * 2 * Double(step) / Double(width), height: r * 2 * Double(step) / Double(height)),
                            contrast: Double(values[index] - background), isDisc: true))
                        if result.count >= 32 { break }
                    }
                    continue
                }
                let centerX = min(w - 1, max(0, Int((sx / sum).rounded())))
                let centerY = min(h - 1, max(0, Int((sy / sum).rounded())))
                guard values[centerY * w + centerX] >= minimumCore else { continue }
                let center = CGPoint(x: (sx / sum + 0.5) * Double(step) / Double(width),
                                     y: (sy / sum + 0.5) * Double(step) / Double(height))
                // Several thresholds of the same disc are one optical observation.
                guard !result.contains(where: { $0.bounds.insetBy(dx: -Double(step) / Double(width), dy: -Double(step) / Double(height)).contains(center) }) else { continue }
                result.append(
                    CameraLightPoint(
                        point: CGPoint(
                            x: (sx / sum + 0.5) * Double(step) / Double(width),
                            y: (sy / sum + 0.5) * Double(step) / Double(height)),
                        bounds: CGRect(
                            x: Double(minX * step) / Double(width), y: Double(minY * step) / Double(height),
                            width: Double(bw * step) / Double(width), height: Double(bh * step) / Double(height)),
                        contrast: Double(peak - background), isDisc: true))
            }
        }
        // A broad solar core must not be crowded out by tiny bright cloud specks.
        return result.sorted { $0.contrast * sqrt($0.bounds.width * $0.bounds.height) > $1.contrast * sqrt($1.bounds.width * $1.bounds.height) }.prefix(8).map { $0 }
    }

}
