import Foundation
import CoreGraphics
import simd

struct SkyFinderProjection {
    let point: CGPoint?
    let arrow: CGVector
    let separation: Double
    var isAligned: Bool { separation <= 3 }

    // Astronomy: east, north, up. ARKit gravityAndHeading: east, up, south.
    // The calibrated compass error is removed here: ARKit's north is turned to true north, so every
    // catalogue position (projection, light matching, crosshair) uses the corrected heading.
    static func worldDirection(_ horizon: SIMD3<Double>) -> SIMD3<Float> {
        // Where ARKit's frame shows an azimuth A, the true azimuth is A + offset: rotate by −offset.
        let c = SkyCalibration.arCos, s = SkyCalibration.arSin
        let east = horizon.x*c-horizon.y*s, north = horizon.x*s+horizon.y*c
        return SIMD3(Float(east),Float(horizon.z),Float(-north))
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

/// Standard atmospheric refraction (Sæmundsson 1986, 10 °C / 1010 hPa).
/// Lifts a geometric horizon direction (east, north, up) to where it actually appears:
/// ~29′ at the horizon, ~5′ at 10°, ~1′ at 45°, 0 at the zenith.
enum Refraction {
    static func arcminutes(trueAltitude h: Double) -> Double {
        guard h > -1.5 else { return 0 }
        let degrees = h+10.3/(h+5.11)
        return max(0,1.02/tan(degrees * .pi/180))
    }
    static func apparent(_ direction: SIMD3<Double>) -> SIMD3<Double> {
        let horizontal = (direction.x*direction.x+direction.y*direction.y).squareRoot()
        guard horizontal > 1e-9 else { return direction }
        let altitude = atan2(direction.z,horizontal)*180 / .pi
        let lifted = (altitude+arcminutes(trueAltitude:altitude)/60) * .pi/180
        let scale = cos(lifted)/horizontal
        return SIMD3(direction.x*scale,direction.y*scale,sin(lifted))
    }
}

/// One centered digital crop shared by the preview, projections, taps and saved photos.
nonisolated enum CameraZoom {
    static let maximum: Double = 10
    static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(maximum,max(1,value)) : 1
    }
    static func normalizedTransform(_ zoom: Double) -> CGAffineTransform {
        let z = clamped(zoom)
        return CGAffineTransform(a:z,b:0,c:0,d:z,tx:(1-z)/2,ty:(1-z)/2)
    }
    static func projection(_ base: simd_float4x4,zoom: Double) -> simd_float4x4 {
        var crop = matrix_identity_float4x4
        crop.columns.0.x = Float(clamped(zoom)); crop.columns.1.y = Float(clamped(zoom))
        return crop*base
    }
    static func imageCrop(extent: CGRect,viewport: CGSize,zoom: Double) -> CGRect {
        let aspect = max(1,viewport.width)/max(1,viewport.height)
        let width = min(extent.width,extent.height*aspect)/clamped(zoom)
        let height = width/aspect
        return CGRect(x:extent.midX-width/2,y:extent.midY-height/2,width:width,height:height)
    }
}
