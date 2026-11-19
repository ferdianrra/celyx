import Foundation
import simd

struct NightSeaCamera: Equatable {
    /// Radians, from north toward east (drag mode).
    var azimuth: Double = 150 * .pi/180
    /// Radians above the horizon (drag mode).
    var altitude: Double = 18 * .pi/180
    /// Degrees (drag mode).
    var fieldOfView: Double = 72
    /// Device attitude: maps camera axes (x right, y up, z back) to [east, north, up].
    var orientation: simd_quatd?
    /// Back camera field of view along the sensor's long side, degrees.
    var cameraFieldOfView: Double = 69
    /// Pinch zoom on top of the real field of view.
    var zoom: Double = 1
    /// Exact focal length in points (wormhole handover), overriding the two modes above.
    var focalOverride: Double?
    /// Optical centre height as a fraction of the screen (wormhole handover).
    var centerYFraction: Double?
    /// Projection blend: 0 = pinhole (gyro window, live camera, wormhole), 1 = stereographic, the
    /// planetarium "dome" of the wide touch view. Both agree at the centre, so zooming in converges.
    /// Mirrored by `projectDir`/`rayDir` in NightSeaShader.txt (passed as forward.w).
    var stereographic: Double = 0

    var forward: SIMD3<Double> {
        if let orientation { return -orientation.act(SIMD3(0,0,1)) }
        return SIMD3(sin(azimuth)*cos(altitude),cos(azimuth)*cos(altitude),sin(altitude))
    }
    var right: SIMD3<Double> {
        if let orientation { return orientation.act(SIMD3(1,0,0)) }
        return SIMD3(cos(azimuth),-sin(azimuth),0)
    }
    var up: SIMD3<Double> {
        if let orientation { return orientation.act(SIMD3(0,1,0)) }
        return simd_cross(right,forward)
    }
    /// Compass heading of the view, radians.
    var heading: Double { let f = forward; return atan2(f.x,f.y) }

    func focalLength(in size: CGSize) -> Double {
        if let focalOverride { return focalOverride }
        guard orientation != nil else { return Double(min(size.width,size.height))*0.62/tan(fieldOfView * .pi/360) }
        // Aspect-fill a 4:3 sensor onto the screen, like the camera preview does.
        let long = Double(max(size.width,size.height)), short = Double(min(size.width,size.height))
        let halfLong = tan(cameraFieldOfView * .pi/360)
        let focal = long/short >= 4.0/3 ? (long/2)/halfLong : (short/2)/(halfLong*3/4)
        return focal*zoom
    }
    func center(in size: CGSize) -> CGPoint {
        CGPoint(x:size.width/2,y:size.height*(centerYFraction ?? (orientation == nil ? 0.47 : 0.5)))
    }

    /// Screen point (in points) of a horizon direction [east, north, up], or nil when behind the camera.
    func project(_ direction: SIMD3<Double>,in size: CGSize) -> CGPoint? {
        let f = forward, r = right, u = up
        let z = simd_dot(direction,f)
        let focal = focalLength(in:size), c = center(in:size)
        guard stereographic > 0 else {
            guard z >= 0.06 else { return nil }
            return CGPoint(x:c.x+simd_dot(direction,r)/z*focal,y:c.y-simd_dot(direction,u)/z*focal)
        }
        let lx = simd_dot(direction,r), ly = simd_dot(direction,u)
        let lateral = hypot(lx,ly)
        let theta = atan2(lateral,z)
        guard theta < Self.maxAngle(stereographic) else { return nil }
        guard lateral > 1e-12 else { return c }
        let q = Self.radius(angle:theta,blend:stereographic)*focal
        return CGPoint(x:c.x+lx/lateral*q,y:c.y-ly/lateral*q)
    }

    /// The view direction through a screen point (the inverse of `project`).
    func direction(at point: CGPoint,in size: CGSize) -> SIMD3<Double> {
        let focal = focalLength(in:size), c = center(in:size)
        let ox = (point.x-c.x)/focal, oy = (c.y-point.y)/focal
        guard stereographic > 0 else { return simd_normalize(forward+ox*right+oy*up) }
        let q = hypot(ox,oy)
        guard q > 1e-12 else { return forward }
        let theta = Self.angle(radius:q,blend:stereographic)
        return simd_normalize(cos(theta)*forward+sin(theta)*((ox/q)*right+(oy/q)*up))
    }

    /// Off-axis angle → normalized screen radius: tan θ (pinhole) blended with 2·tan(θ/2)
    /// (stereographic). Solved from `angle(radius:)`, which has the closed form.
    static func radius(angle theta: Double,blend s: Double) -> Double {
        var q = (1-s)*tan(min(theta,1.5))+s*2*tan(theta/2)
        for _ in 0..<6 {
            let error = angle(radius:q,blend:s)-theta
            let slope = (1-s)/(1+q*q)+s/(1+q*q/4)
            q = max(0,q-error/slope)
        }
        return q
    }

    /// Normalized screen radius → off-axis angle (radians).
    static func angle(radius q: Double,blend s: Double) -> Double { (1-s)*atan(q)+s*2*atan(q/2) }

    /// Widest off-axis angle still drawn: the pinhole's 86.6° (z ≥ 0.06) up to 149° stereographic.
    static func maxAngle(_ s: Double) -> Double { 1.5108+1.0892*s }
}
