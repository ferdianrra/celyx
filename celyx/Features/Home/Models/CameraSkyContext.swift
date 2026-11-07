import CoreVideo
import Foundation
import simd

/// Rejects positive foreground evidence. A compact light alone cannot prove that
/// it is astronomical, so catalog matching must never stand in for this check.
nonisolated enum CameraSkyContext {
    static func hasNearbySurface(direction: SIMD3<Float>,origin: SIMD3<Float>,features: [SIMD3<Float>]) -> Bool {
        var support = 0
        for feature in features {
            let offset = feature-origin, distance = simd_length(offset)
            guard distance > 0.2, distance < 80,
                  simd_dot(offset/distance,direction) > cos(0.8 * Float.pi/180) else { continue }
            support += 1
            if support >= 3 { return true }
        }
        return false
    }

    static func permits(_ point: CGPoint,in image: CVPixelBuffer,isDisc: Bool = false) -> Bool {
        guard CVPixelBufferGetPlaneCount(image) > 0 else { return false }
        CVPixelBufferLockBaseAddress(image,.readOnly)
        defer { CVPixelBufferUnlockBaseAddress(image,.readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(image,0) else { return false }
        let bytes = base.assumingMemoryBound(to:UInt8.self)
        let width = CVPixelBufferGetWidthOfPlane(image,0), height = CVPixelBufferGetHeightOfPlane(image,0)
        let row = CVPixelBufferGetBytesPerRowOfPlane(image,0)
        let cx = Int(point.x*Double(width)), cy = Int(point.y*Double(height))
        let radius = max(24,min(72,width/30)), step = max(2,radius/12)
        guard cx-radius >= 0, cy-radius >= 0, cx+radius < width, cy+radius < height else { return false }
        func value(_ x: Int,_ y: Int) -> Int { Int(bytes[y*row+x]) }
        var differences: [Int] = []
        for y in stride(from:cy-radius,through:cy+radius,by:step) {
            for x in stride(from:cx-radius,through:cx+radius-1,by:step)
                where hypot(Double(x-cx),Double(y-cy)) > Double(radius)*0.25 {
                differences.append(abs(value(x+1,y)-value(x,y)))
            }
        }
        differences.sort()
        let edgeThreshold = max(6,(differences.isEmpty ? 0 : differences[differences.count/2])*5)
        var edges = 0, samples = 0, longest = 0
        var inner: [Int] = [], outer: [Int] = []
        for y in stride(from:cy-radius+step,through:cy+radius-step,by:step) {
            var run = 0
            for x in stride(from:cx-radius+step,through:cx+radius-step,by:step) {
                let distance = hypot(Double(x-cx),Double(y-cy))
                guard distance > Double(radius)*0.25 else { run = 0; continue }
                let gradient = max(abs(value(x+step,y)-value(x-step,y)),abs(value(x,y+step)-value(x,y-step)))
                if gradient >= edgeThreshold { edges += 1; run += 1; longest = max(longest,run) }
                else { run = 0 }
                samples += 1
                if distance < Double(radius)*0.5 { inner.append(value(x,y)) }
                if distance > Double(radius)*0.8 { outer.append(value(x,y)) }
            }
        }
        // Roof/window edges and textured structures, excluding the star's own core.
        if samples > 0, Double(edges)/Double(samples) > 0.16 || longest >= 10 { return false }
        // A large illuminated halo is characteristic of a nearby light fixture.
        inner.sort(); outer.sort()
        if !isDisc, !inner.isEmpty, !outer.isEmpty, inner[inner.count/2]-outer[outer.count/2] > 18 { return false }
        return true
    }
}
