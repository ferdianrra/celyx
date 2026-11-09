import Foundation
import simd

struct NightSeaCamera: Equatable {
    /// Radians, from north toward east (drag mode).
    var azimuth: Double = 150 * .pi / 180
    /// Radians above the horizon (drag mode).
    var altitude: Double = 18 * .pi / 180
    /// Degrees (drag mode).
    var fieldOfView: Double = 72
    /// Device attitude: maps camera axes (x right, y up, z back) to [east, north, up].
    var orientation: simd_quatd?
    /// Back camera field of view along the sensor's long side, degrees.
    var cameraFieldOfView: Double = 69
    /// Pinch zoom on top of the real field of view.
    var zoom: Double = 1

    var forward: SIMD3<Double> {
        if let orientation { return -orientation.act(SIMD3(0, 0, 1)) }
        return SIMD3(sin(azimuth) * cos(altitude), cos(azimuth) * cos(altitude), sin(altitude))
    }
    var right: SIMD3<Double> {
        if let orientation { return orientation.act(SIMD3(1, 0, 0)) }
        return SIMD3(cos(azimuth), -sin(azimuth), 0)
    }
    var up: SIMD3<Double> {
        if let orientation { return orientation.act(SIMD3(0, 1, 0)) }
        return simd_cross(right, forward)
    }
    /// Compass heading of the view, radians.
    var heading: Double {
        let f = forward
        return atan2(f.x, f.y)
    }

    func focalLength(in size: CGSize) -> Double {
        guard orientation != nil else {
            return Double(min(size.width, size.height)) * 0.62 / tan(fieldOfView * .pi / 360)
        }
        // Aspect-fill a 4:3 sensor onto the screen, like the camera preview does.
        let long = Double(max(size.width, size.height))
        let short = Double(min(size.width, size.height))
        let halfLong = tan(cameraFieldOfView * .pi / 360)
        let focal = long / short >= 4.0 / 3 ? (long / 2) / halfLong : (short / 2) / (halfLong * 3 / 4)
        return focal * zoom
    }
    func center(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height * (orientation == nil ? 0.47 : 0.5))
    }

    /// Screen point (in points) of a horizon direction [east, north, up], or nil when behind the camera.
    func project(_ direction: SIMD3<Double>, in size: CGSize) -> CGPoint? {
        let f = forward
        let r = right
        let u = up
        let z = simd_dot(direction, f)
        guard z >= 0.06 else { return nil }
        let focal = focalLength(in: size)
        let c = center(in: size)
        return CGPoint(
            x: c.x + simd_dot(direction, r) / z * focal, y: c.y - simd_dot(direction, u) / z * focal)
    }
}
