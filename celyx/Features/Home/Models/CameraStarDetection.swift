import Foundation
import CoreVideo
import CoreGraphics
import simd

nonisolated struct CameraLightPoint: Sendable {
    let point: CGPoint // normalized unrotated camera-image coordinates
    let bounds: CGRect
    let contrast: Double
    var isDisc = false
}
struct CameraLightAnnotation: Identifiable {
    let id: Int
    let point: CGPoint
    let size: CGSize
}
struct CameraOpticalTrack {
    let id: Int
    let hits: Int
    let direction: SIMD3<Float>
    let size: CGSize
    let time: TimeInterval
    var isDisc = false
}
struct CameraStarAnnotation: Identifiable {
    let star: CatalogStar
    let point: CGPoint
    let size: CGSize
    var estimatedSeparation: Double? = nil
    var sourceDirection: SIMD3<Float>? = nil
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

struct CameraAimTarget {
    let object: CameraMappedObject
    let detection: CameraStarAnnotation?
    var id: Int { object.id }
}

nonisolated enum CameraStarDetector {
    // Compact high-contrast sources only. Extended lights and isolated hot pixels are rejected.
    static func detect(in image: CVPixelBuffer,zoom: Double = 1) -> [CameraLightPoint] {
        let format = CVPixelBufferGetPixelFormatType(image)
        guard format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
              CVPixelBufferIsPlanar(image), CVPixelBufferGetPlaneCount(image) > 0 else { return [] }
        CVPixelBufferLockBaseAddress(image,.readOnly)
        defer { CVPixelBufferUnlockBaseAddress(image,.readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(image,0) else { return [] }
        let bytes = base.assumingMemoryBound(to:UInt8.self)
        let width = CVPixelBufferGetWidthOfPlane(image,0), height = CVPixelBufferGetHeightOfPlane(image,0)
        let row = CVPixelBufferGetBytesPerRowOfPlane(image,0)
        let radius = min(15,max(6,Int(6*sqrt(max(1,zoom)))))
        let ringRadius = radius+1
        let margin = ringRadius+3
        let maxArea = Int(45*min(5,max(1,zoom)))
        let maxDiameter = Int(12*sqrt(max(1,zoom)))
        guard width > margin*2, height > margin*2 else { return [] }
        // Reject ordinary sensor grain cheaply before doing per-source component analysis.
        var histogram = [Int](repeating:0,count:256)
        var samples = 0
        for y in stride(from:0,to:height,by:16) {
            for x in stride(from:0,to:width,by:16) { histogram[Int(bytes[y*row+x])] += 1; samples += 1 }
        }
        func medianBin(_ bins: [Int]) -> Int {
            var total = 0
            for value in 0..<256 { total += bins[value]; if total >= max(1,samples/2) { return value } }
            return 0
        }
        let globalBackground = medianBin(histogram)
        var noiseHistogram = [Int](repeating:0,count:256)
        for value in 0..<256 { noiseHistogram[abs(value-globalBackground)] += histogram[value] }
        let globalNoise = max(0.8,Double(medianBin(noiseHistogram))*1.4826)
        let minimumPeak = max(10,globalBackground+Int(max(4,globalNoise*3)))
        var result: [CameraLightPoint] = []
        for y in stride(from:margin,to:height-margin,by:3) {
            for x in stride(from:margin,to:width-margin,by:3) {
                var px = x, py = y, peak = 0
                for dy in 0..<3 { for dx in 0..<3 {
                    let value = Int(bytes[(y+dy)*row+x+dx])
                    if value > peak { peak = value; px = x+dx; py = y+dy }
                } }
                guard peak >= minimumPeak else { continue }
                let normalized = CGPoint(x:Double(px)/Double(width),y:Double(py)/Double(height))
                guard !result.contains(where:{ hypot(($0.point.x-normalized.x)*Double(width),($0.point.y-normalized.y)*Double(height)) < 10 }) else { continue }
                var ring: [Double] = []
                for dy in [-ringRadius,0,ringRadius] { for dx in [-ringRadius,0,ringRadius] where dx != 0 || dy != 0 {
                    ring.append(Double(bytes[(py+dy)*row+px+dx]))
                } }
                let sorted = ring.sorted()
                let background = (sorted[3]+sorted[4])/2
                let deviations = ring.map { abs($0-background) }.sorted()
                let deviation = max(0.8,(deviations[3]+deviations[4])/2*1.4826)
                let contrast = Double(peak)-background
                guard background < 185, contrast > max(4,deviation*4) else { continue }
                let threshold = background+max(2,max(deviation*2,contrast*0.28))
                var queue = [(px,py)], visited: Set<Int> = [py*width+px]
                var cursor = 0, count = 0, sum = 0.0, sx = 0.0, sy = 0.0
                var minX = px, maxX = px, minY = py, maxY = py
                while cursor < queue.count && queue.count <= maxArea+10 {
                    let (cx,cy) = queue[cursor]; cursor += 1
                    let weight = Double(bytes[cy*row+cx])-background
                    count += 1; sum += weight; sx += Double(cx)*weight; sy += Double(cy)*weight
                    minX = min(minX,cx); maxX = max(maxX,cx); minY = min(minY,cy); maxY = max(maxY,cy)
                    for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = cx+dx, ny = cy+dy
                        guard abs(nx-px) <= radius, abs(ny-py) <= radius else { continue }
                        let key = ny*width+nx
                        guard !visited.contains(key), Double(bytes[ny*row+nx]) >= threshold else { continue }
                        visited.insert(key); queue.append((nx,ny))
                    } }
                }
                let bw = maxX-minX+1, bh = maxY-minY+1
                guard count >= 2, count <= maxArea, bw < maxDiameter, bh < maxDiameter,
                      Double(max(bw,bh))/Double(max(1,min(bw,bh))) <= 2.5, sum > 0 else { continue }
                result.append(CameraLightPoint(point:CGPoint(x:sx/sum/Double(width),y:sy/sum/Double(height)),
                    bounds:CGRect(x:Double(minX)/Double(width),y:Double(minY)/Double(height),width:Double(bw)/Double(width),height:Double(bh)/Double(height)),
                    contrast:Double(peak)-background))
                if result.count > 200 {
                    result.sort { $0.contrast > $1.contrast }
                    result.removeSubrange(80...)
                }
            }
        }
        return result.sorted { $0.contrast > $1.contrast }.prefix(50).map { $0 }
    }
    // Larger bright discs (Sun/Moon) do not pass the compact star-point detector.
    static func detectDiscs(in image: CVPixelBuffer) -> [CameraLightPoint] {
        let format = CVPixelBufferGetPixelFormatType(image)
        guard format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
              CVPixelBufferIsPlanar(image), CVPixelBufferGetPlaneCount(image) > 0 else { return [] }
        CVPixelBufferLockBaseAddress(image,.readOnly)
        defer { CVPixelBufferUnlockBaseAddress(image,.readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(image,0) else { return [] }
        let bytes = base.assumingMemoryBound(to:UInt8.self)
        let width = CVPixelBufferGetWidthOfPlane(image,0), height = CVPixelBufferGetHeightOfPlane(image,0)
        let row = CVPixelBufferGetBytesPerRowOfPlane(image,0)
        let step = max(3,max(width,height)/320)
        let w = width/step, h = height/step
        guard w > 4, h > 4 else { return [] }
        var values = [Int](repeating:0,count:w*h)
        for y in 0..<h { for x in 0..<w { values[y*w+x] = Int(bytes[y*step*row+x*step]) } }
        let sorted = values.sorted()
        let background = sorted[sorted.count/2]
        let threshold = max(160,background+30)
        guard threshold < 250 else { return [] }
        var visited = [Bool](repeating:false,count:w*h)
        var result: [CameraLightPoint] = []
        for start in values.indices where !visited[start] && values[start] >= threshold {
            var queue = [start], cursor = 0
            visited[start] = true
            var minX = start%w, maxX = minX, minY = start/w, maxY = minY
            var sum = 0.0, sx = 0.0, sy = 0.0, peak = 0
            while cursor < queue.count {
                let index = queue[cursor]; cursor += 1
                let x = index%w, y = index/w, weight = Double(values[index]-background)
                sum += weight; sx += Double(x)*weight; sy += Double(y)*weight; peak = max(peak,values[index])
                minX = min(minX,x); maxX = max(maxX,x); minY = min(minY,y); maxY = max(maxY,y)
                for (dx,dy) in [(1,0),(-1,0),(0,1),(0,-1)] {
                    let nx = x+dx, ny = y+dy
                    guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
                    let next = ny*w+nx
                    if !visited[next] && values[next] >= threshold { visited[next] = true; queue.append(next) }
                }
            }
            let bw = maxX-minX+1, bh = maxY-minY+1
            guard queue.count >= 3, queue.count < w*h/12, sum > 0,
                  minX > 0, minY > 0, maxX < w-1, maxY < h-1,
                  Double(max(bw,bh))/Double(min(bw,bh)) < 2,
                  Double(queue.count)/Double(bw*bh) > 0.35 else { continue }
            result.append(CameraLightPoint(point:CGPoint(x:(sx/sum+0.5)*Double(step)/Double(width),y:(sy/sum+0.5)*Double(step)/Double(height)),
                bounds:CGRect(x:Double(minX*step)/Double(width),y:Double(minY*step)/Double(height),width:Double(bw*step)/Double(width),height:Double(bh*step)/Double(height)),contrast:Double(peak-background),isDisc:true))
        }
        return result.sorted { $0.contrast > $1.contrast }.prefix(8).map { $0 }
    }

}
