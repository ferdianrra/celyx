import Foundation
import simd

/// One collected object placed in the sky.
struct NightSeaObject: Identifiable, Equatable {
    enum Kind: Float { case star = 0, planet = 1, moon = 2, sun = 3 }
    let id: Int
    let direction: SIMD3<Double>
    /// Stars: core radius in points (the kit's starR, x1.3 for collected).
    /// Planets, Moon, Sun: sprite radius in points (glow included).
    let radius: Double
    let color: SIMD3<Double>
    let kind: Kind
    /// Moon and planets: Sun–body–Earth angle in radians (0 = full), from Astronomy Engine.
    var phaseAngle: Double = 0
    /// Where the Sun is in the horizon frame; the zoomed disk is lit from that side.
    var sunDirection: SIMD3<Double> = SIMD3(0, 0, -1)
    var isAboveHorizon: Bool { direction.z > 0.002 }
    var gpuKind: Float { kind.rawValue }
    /// The kit's star radius (points) for a magnitude; collected stars use it x1.3.
    static func starRadius(magnitude: Double) -> Double { min(5,max(0.8,3.0-0.55*magnitude)) }
}

// MARK: - Zoom

/// Pinch limits for the virtual garden.
enum GardenZoomLimits {
    /// Touch mode field of view, degrees (default 72°): about 144× at the limit.
    static let minFieldOfView = 0.5
    /// Gyro mode magnification over the camera's real field of view.
    static let maxGyroZoom = 20.0
    /// How quickly the zoom eases toward the pinch (per second); higher is snappier.
    static let zoomEase = 14.0
    /// How quickly a released drag slows down (per second).
    static let glideFriction = 4.0
    /// Stars grow at most this much when zoomed, so they stay points of light.
    static let maxStarGrowth = 2.2
    /// Touch view fields of view (degrees) over which the projection turns from pinhole
    /// (zoomed in) to the stereographic dome (wide). Gyro, live camera and handovers stay pinhole.
    static let domeFieldOfView: ClosedRange<Double> = 15...55
    /// How quickly the projection eases between pinhole and dome (per second).
    static let domeEase = 8.0

    /// Stereographic blend for a touch-mode field of view.
    static func domeBlend(fieldOfView: Double) -> Double {
        let t = min(1, max(0, (fieldOfView - domeFieldOfView.lowerBound)
            / (domeFieldOfView.upperBound - domeFieldOfView.lowerBound)))
        return t * t * (3 - 2 * t)
    }
    /// Pinch response: magnification is raised to this power, so the 72°→1.5° range takes
    /// a few pinches instead of many.
    static let pinchExponent = 1.5
    /// Object names fade in between these garden zooms (1 = the default 72° view; the gyro
    /// view starts near 1.7). Zoomed out, the sky stays clean.
    static let labelFadeIn: ClosedRange<Double> = 2.0...2.6

    /// Label opacity for a garden zoom (0 zoomed out, 1 zoomed in).
    static func labelOpacity(zoom: Double) -> Double {
        let t = min(1, max(0, (zoom - labelFadeIn.lowerBound) / (labelFadeIn.upperBound - labelFadeIn.lowerBound)))
        return t * t * (3 - 2 * t)
    }

    /// Drag speed in radians per point: 1:1 with the finger when zoomed in (the sky stays under
    /// it), easing to the original 1.15× at the wide default view.
    static func dragRadiansPerPoint(fieldOfView: Double, focalLength: Double) -> Double {
        let wide = min(1, max(0, (fieldOfView - 10) / 62))
        return (1 + 0.15 * wide) / max(focalLength, 1)
    }
}

/// The garden's zoom relative to the kit's 72° view (1 = default touch view).
/// Mirrors `gbZoom` in GardenBodyShader.txt.
extension NightSeaCamera {
    func gardenZoom(in size: CGSize) -> Double {
        let minSide = Double(min(size.width, size.height))
        guard minSide > 0 else { return 1 }
        let fov = 2 * atan(0.62 * minSide / focalLength(in: size)) * 180 / .pi
        return 72 / max(fov, 0.5)
    }
}

extension NightSeaObject {
    /// How large the object is drawn at a zoom, in points. Mirrors `gardenBodyVertex`.
    struct Apparent: Equatable {
        /// Star core or body disk radius.
        let disk: Double
        /// 0 = the kit's point sprite, 1 = fully resolved disk (photosphere, texture, phase).
        let detail: Double
        /// Distance from the centre to place a label below the object.
        var labelOffset: Double
        /// Tap radius around the centre.
        var hitRadius: Double
    }

    private static func growth(_ zoom: Double, low: Double) -> Double {
        let t = min(1, max(0, (zoom - 2.5) / (12 - 2.5)))
        return low + (1 - low) * t * t * (3 - 2 * t)
    }

    private static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    /// Convenience for the virtual garden's camera.
    func apparent(camera: NightSeaCamera, in size: CGSize) -> Apparent {
        apparent(zoom: camera.gardenZoom(in: size), focalLength: camera.focalLength(in: size),
                 shortSide: Double(min(size.width, size.height)))
    }

    /// `focalLength` in points sets the Moon's and Sun's true 0.27° minimum radius; disks are
    /// capped at 30% of `shortSide` (points), as in the shader.
    func apparent(zoom: Double, focalLength: Double = 0, shortSide: Double = .infinity) -> Apparent {
        // The pre-zoom label and tap sizes the garden has always used.
        let kitScale: Double = kind == .star ? 7.0 / 1.3 : 1.0
        let kitLabel = radius * kitScale * 0.45
        let kitHit = max(36, radius * kitScale * 0.6)
        var disk: Double
        let detail: Double
        if kind == .star {
            // A star stays a point of light: the kit's √zoom growth, capped.
            disk = radius * min(sqrt(max(zoom, 0)), GardenZoomLimits.maxStarGrowth)
            detail = 0
        } else if kind == .planet {
            disk = radius * 0.13 * pow(max(zoom, 1), Self.growth(zoom, low: 0.35))
            detail = Self.smoothstep(4, 14, disk)
        } else {
            disk = max(radius * 0.24 * pow(max(zoom, 1), 0.35), focalLength * 0.004652)
            // The Sun stays a glare until zoomed in; the Moon resolves early.
            detail = kind == .sun ? Self.smoothstep(14, 40, disk) : Self.smoothstep(3, 10, disk)
        }
        disk = min(disk, 0.3 * shortSide)
        // Saturn's rings reach ~2.25 disk radii but are tilted, so ~1.4 clears them below.
        let resolved = disk * (1 + 0.4 * detail)
        return Apparent(disk: disk, detail: detail,
                        labelOffset: max(kitLabel, resolved) + 14,
                        hitRadius: max(kitHit, disk * 1.2))
    }

    /// Texture slice in the renderer's body atlas: Moon, Mercury, Venus, Mars, Jupiter; −1 = none
    /// (stars, the Sun, and Saturn, which is drawn with procedural bands and rings).
    var textureSlice: Float {
        switch id {
        case -2: 0
        case -3: 1
        case -4: 2
        case -5: 3
        case -6: 4
        default: -1
        }
    }

    /// Spin at full zoom (rad/s): slow enough to read the surface. The Moon is tidally locked.
    var spin: Float {
        switch id {
        case -3: 0.03
        case -4: 0.015
        case -5: 0.06
        case -6: 0.1
        case -7: 0.09
        default: 0
        }
    }

    /// On-screen tilt of bands and rings (rad).
    var axialTilt: Float {
        switch id {
        case -2: 0.12
        case -5: 0.44
        case -6: 0.05
        case -7: 0.47
        default: 0
        }
    }
}
