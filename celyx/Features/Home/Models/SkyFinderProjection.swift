import Foundation
import CoreGraphics
import simd

struct SkyFinderProjection {
    let point: CGPoint?
    let arrow: CGVector
    let separation: Double
    var isAligned: Bool { separation <= 3 }

    // Astronomy: east, north, up. ARKit gravityAndHeading: east, up, south.
    static func worldDirection(_ horizon: SIMD3<Double>) -> SIMD3<Float> {
        SIMD3(Float(horizon.x),Float(horizon.z),Float(-horizon.y))
    }

    static func project(direction: SIMD3<Float>, view: simd_float4x4,
                        projection: simd_float4x4, size: CGSize) -> SkyFinderProjection {
        let transformed = view * SIMD4(direction.x,direction.y,direction.z,0)
        let local = simd_normalize(SIMD3(transformed.x,transformed.y,transformed.z))
        let separation = Double(acos(min(1,max(-1,-local.z)))) * 180 / .pi
        let clip = projection * SIMD4(local.x*1000,local.y*1000,local.z*1000,1)
        var point: CGPoint?
        if local.z < 0, clip.w > 0 {
            let x = Double(clip.x/clip.w), y = Double(clip.y/clip.w)
            if abs(x) <= 1, abs(y) <= 1 {
                point = CGPoint(x:(x+1)*size.width/2,y:(1-y)*size.height/2)
            }
        }
        // Keep the shortest turn direction even when the target is behind the camera.
        var arrow = SIMD2(Double(local.x),Double(-local.y))
        if simd_length(arrow) < 0.0001 { arrow = SIMD2(1,0) }
        arrow = simd_normalize(arrow)
        return SkyFinderProjection(point:point,arrow:CGVector(dx:arrow.x,dy:arrow.y),separation:separation)
    }
}
