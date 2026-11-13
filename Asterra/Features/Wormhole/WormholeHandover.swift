//  WormholeHandover.swift
//  State of one camera → Night Sea handover: the frozen camera frame, the clock, and the
//  camera the Night Sea is seen through at every instant (so the wormhole and the garden match).

import SwiftUI
import QuartzCore
import simd

/// The camera frame frozen at the moment the collect succeeded, oriented and cropped like the screen.
struct WormholeFreeze {
    /// Frozen camera image (nil on the Simulator or when the camera has no frame yet).
    var image: CGImage?
    /// Screen size in points.
    var size: CGSize
    /// Camera axes (x right, y up, z back) → horizon frame [east, north, up].
    var orientation: simd_quatd
    /// Pinhole focal length in points (matches the live camera preview, zoom included).
    var focal: Double

    /// Builds the orientation from an AR view matrix (with the interface rotation applied)
    /// and the alignment that maps horizon directions into the sensor world.
    static func make(image: CGImage?,size: CGSize,view: simd_float4x4,projection: simd_float4x4,alignment: simd_quatf) -> WormholeFreeze {
        let inverse = simd_inverse(view)
        func horizon(_ c: SIMD4<Float>) -> SIMD3<Double> {
            SkyFinderProjection.horizonDirection(alignment.inverse.act(SIMD3(c.x,c.y,c.z)))
        }
        let right = horizon(inverse.columns.0), up = horizon(inverse.columns.1), back = horizon(inverse.columns.2)
        let focal = Double(projection.columns.1.y)*Double(size.height)/2
        return WormholeFreeze(image:image,size:size,orientation:Self.orientation(forward:-back,right:right,up:up),focal:focal)
    }

    /// No camera frame (Simulator / debug): a calm view to the south-east, 30° up.
    static func placeholder(size: CGSize) -> WormholeFreeze {
        var camera = NightSeaCamera()
        camera.azimuth = 135 * .pi/180; camera.altitude = 30 * .pi/180
        let focal = Double(max(size.width,size.height))/2/tan(34.5 * .pi/180)
        return WormholeFreeze(image:nil,size:size,orientation:orientation(forward:camera.forward,right:camera.right,up:camera.up),focal:focal)
    }

    static func orientation(forward: SIMD3<Double>,right: SIMD3<Double>,up: SIMD3<Double>) -> simd_quatd {
        let back = simd_normalize(-forward)
        let r = simd_normalize(right-back*simd_dot(right,back))
        let u = simd_cross(back,r)
        _ = up
        return simd_normalize(simd_quatd(simd_double3x3(columns:(r,u,back))))
    }
}

extension SkyFinderProjection {
    /// Inverse of `worldDirection`: sensor world direction → horizon [east, north, up].
    static func horizonDirection(_ world: SIMD3<Float>) -> SIMD3<Double> {
        let c = SkyCalibration.arCos, s = SkyCalibration.arSin
        let east1 = Double(world.x), up = Double(world.y), north1 = -Double(world.z)
        return simd_normalize(SIMD3(east1*c+north1*s,-east1*s+north1*c,up))
    }
}

@MainActor @Observable
final class WormholeHandover: Identifiable {
    enum Phase: Int, Comparable {
        /// Wormhole over the frozen camera frame.
        case wormhole
        /// Landed (T_LAND): the view locks onto the collected star; the garden renders underneath (hidden).
        case landed
        /// The Night Sea has taken over (the camera layer is gone); still looking at the star.
        case reframe
        /// The landed star/constellation is framed before revealing its new artwork.
        case focusing
        case revealing
        /// Blend to the latest live gyro / touch camera before presenting the album.
        case releasing
        case presenting
        case done
        static func < (a: Phase,b: Phase) -> Bool { a.rawValue < b.rawValue }
    }

    let id = UUID()
    let freeze: WormholeFreeze
    /// Collected star's screen point (points).
    let star: CGPoint
    /// Collected object, for the sheet (nil in a debug replay without a collection).
    let itemID: Int?
    /// The Night Sea seen through the hole.
    let scene: WormholeScene
    /// Temporary simulated placement that lights up at landing; the collection record is saved separately.
    let demo: WormholeDemo?
    /// Wall clock of the collect success.
    let start: CFTimeInterval
    /// T_LAND (ms): the hole covers the whole screen. Every impact cue fires here.
    let landing: Double
    var cross: Double { landing+WormholeTimeline.crossDelay }

    private(set) var phase: Phase = .wormhole
    /// Set when the sheet should spring in.
    private(set) var showsSheet = false
    /// Beginning of the smooth return to the live camera.
    private var releaseAt: Double?
    @ObservationIgnored private var focusPose: NightSeaCamera?
    var focusStart: Double { landing + WormholeTimeline.flyEnd + 560 }
    var revealAt: Double { focusStart + 800 }
    var returnAt: Double { revealAt + 2700 }
    static let returnDuration: Double = 1100
    var revealIsVisible: Bool { phase >= .revealing }

    /// Night Sea field of view (kit convention: focal = 0.62·min(W,H)/tan(fov/2)) of the frozen camera.
    let baseFieldOfView: Double

    /// The garden's own camera to hand back to (kept current by the garden while releasing).
    @ObservationIgnored var target: NightSeaCamera?
    @ObservationIgnored var liveCamera: NightSeaCamera?

    init(freeze: WormholeFreeze,star: CGPoint,itemID: Int?,scene: WormholeScene,demo: WormholeDemo? = nil) {
        self.freeze = freeze
        self.scene = scene
        self.demo = demo
        self.star = star
        self.itemID = itemID
        start = CACurrentMediaTime()
        landing = WormholeTimeline.landing(size:freeze.size,star:star)
        baseFieldOfView = 2*atan(0.62*Double(min(freeze.size.width,freeze.size.height))/freeze.focal)*180 / .pi
    }

    /// ms since the collect succeeded.
    func tt(_ now: CFTimeInterval = CACurrentMediaTime()) -> Double { (now-start)*1000 }

    func frame(_ tt: Double) -> WormholeTimeline.Frame {
        WormholeTimeline.frame(tt,size:freeze.size,star:star,landing:landing)
    }

    /// No sheet is requested until placement, focus, reveal, hold, and live-camera return finish.
    /// The optional wait closure lets tests verify ordering without wall-clock sleeps.
    func run(reduceMotion: Bool = false, waitUntil: ((Double) async throws -> Void)? = nil) async {
        func wait(_ ms: Double) async throws {
            if let waitUntil { try await waitUntil(ms) }
            else {
                let delay = ms - tt()
                if delay > 0 { try await Task.sleep(for: .milliseconds(delay)) }
            }
            try Task.checkCancellation()
        }
        do {
            if !reduceMotion { try await wait(landing) }
            phase = .landed
            if !reduceMotion { try await wait(cross) }
            phase = .reframe
            if !reduceMotion { try await wait(focusStart) }
            phase = .focusing
            if !reduceMotion { try await wait(revealAt) }
            phase = .revealing
            try await wait(reduceMotion ? tt() + 700 : returnAt)
            beginRelease()
            if !reduceMotion { try await wait(releaseAt! + Self.returnDuration) }
            phase = .presenting
            if !reduceMotion { try await wait(tt() + 350) }
            if itemID != nil { showsSheet = true } else { finish() }
        } catch { finish() }
    }

    func beginRelease() {
        guard phase < .releasing else { return }
        releaseAt = tt(); phase = .releasing
    }

    func finish() { showsSheet = false; phase = .done }

    /// Fit collected neighbors (or the completed pattern) inside a comfortable screen margin.
    func configureFocus(directions: [SIMD3<Double>]) {
        let points = directions.isEmpty ? [starDirection] : directions
        let sum = points.reduce(SIMD3<Double>.zero, +)
        let forward = simd_length(sum) > 0.001 ? simd_normalize(sum) : starDirection
        var right = simd_cross(forward, SIMD3<Double>(0, 0, 1))
        if simd_length(right) < 0.001 { right = freeze.orientation.act(SIMD3(1, 0, 0)) }
        right = simd_normalize(right)
        let up = simd_cross(right, forward)
        var focal = focal(forFieldOfView: 28)
        for point in points {
            let z = max(0.06, simd_dot(point, forward))
            let x = abs(simd_dot(point, right)) / z, y = abs(simd_dot(point, up)) / z
            if x > 0.001 { focal = min(focal, Double(freeze.size.width) * 0.34 / x) }
            if y > 0.001 { focal = min(focal, Double(freeze.size.height) * 0.34 / y) }
        }
        var camera = NightSeaCamera()
        camera.orientation = WormholeFreeze.orientation(forward: forward, right: right, up: up)
        camera.focalOverride = max(self.focal(forFieldOfView: 110), focal)
        focusPose = camera
    }

    // MARK: Camera

    struct Pinhole {
        var orientation: simd_quatd
        var focal: Double
        var centerY: Double
        /// Frozen camera image: sample at centre + (p - centre)·scale + shift (points).
        var imageScale: Double
        var imageShift: CGVector
    }

    private func focal(forFieldOfView fov: Double) -> Double {
        0.62*Double(min(freeze.size.width,freeze.size.height))/tan(max(5,min(170,fov)) * .pi/360)
    }

    /// The collected star's direction [east, north, up] (falls back to where the frozen camera looked).
    @ObservationIgnored lazy var starDirection: SIMD3<Double> = {
        scene.objects.first { $0.id == scene.newID }?.direction ?? freeze.orientation.act(SIMD3(0,0,-1))
    }()

    /// Upright camera looking straight at the collected star.
    @ObservationIgnored private lazy var starView: simd_quatd = {
        let f = simd_normalize(starDirection)
        var right = simd_cross(f,SIMD3(0,0,1))
        if simd_length(right) < 1e-3 { right = freeze.orientation.act(SIMD3(1,0,0)) }
        right = simd_normalize(right)
        return WormholeFreeze.orientation(forward:f,right:right,up:simd_cross(right,f))
    }()

    /// The camera the Night Sea is seen through: frozen pose + hand sway (until T_LAND) + fov pull, then from
    /// T_LAND it locks and eases onto the collected star (gyro ignored); the landing shake rides on top and dies
    /// out on the star. It then frames the connected stars, reveals the artwork, and blends back to
    /// the live garden camera before the album is presented.
    func pinhole(_ tt: Double,frame f: WormholeTimeline.Frame) -> Pinhole {
        let t = tt/1000
        let jitter = tt >= landing ? 0 : f.jitter
        let swayYaw = jitter*(0.6*sin(t*1.7)+0.4*sin(t*2.9+1.3))
        let swayPitch = jitter*(0.5*sin(t*1.3+0.7)+0.5*sin(t*2.3+2.1))
        let az = (0.10*f.shake+swayYaw) * .pi/180, alt = (-0.32*f.shake+swayPitch) * .pi/180
        let ease = WormholeTimeline.reframe
        let lock = ease(WormholeTimeline.seg(tt,landing,landing+WormholeTimeline.landingDuration))
        let base = lock > 0 ? simd_slerp(freeze.orientation,starView,lock) : freeze.orientation
        // Flying in: a touch wide and from slightly below at the crossing, gliding forward and up onto the star.
        let flight = WormholeTimeline.flight(tt,landing:landing)
        let glide = alt+flight.pitch * .pi/180
        let shaken = simd_quatd(angle:-az,axis:SIMD3(0,0,1))*base*simd_quatd(angle:glide,axis:SIMD3(1,0,0))
        let fov = WormholeTimeline.mix(baseFieldOfView,WormholeTimeline.landingFieldOfView,lock)+f.pull+flight.fov
        let pinFocal = focal(forFieldOfView:fov)
        let centerY = 0.5
        var result = Pinhole(orientation:shaken,focal:pinFocal,centerY:centerY,imageScale:freeze.focal/pinFocal,
                             imageShift:CGVector(dx:freeze.focal*az,dy:-freeze.focal*alt))
        if let focusPose {
            let focus = ease(WormholeTimeline.seg(tt, focusStart, revealAt))
            result.orientation = simd_slerp(result.orientation, Self.orientation(of: focusPose), focus)
            result.focal = exp(WormholeTimeline.mix(log(result.focal), log(focusPose.focalLength(in: freeze.size)), focus))
        }
        guard let releaseAt, let goal = target else { return result }
        let r = ease(WormholeTimeline.seg(tt,releaseAt,releaseAt+Self.returnDuration))
        let goalFocal = goal.focalLength(in:freeze.size)
        let goalFov = 2*atan(0.62*Double(min(freeze.size.width,freeze.size.height))/goalFocal)*180 / .pi
        result.orientation = simd_slerp(result.orientation,Self.orientation(of:goal),r)
        result.focal = exp(WormholeTimeline.mix(log(result.focal), log(focal(forFieldOfView: goalFov)), r))
        result.centerY = WormholeTimeline.mix(centerY,goal.center(in:CGSize(width:1,height:1)).y,r)
        return result
    }

    /// Where the view rests after landing: on the star, upright, at the landing field of view.
    var restingCamera: NightSeaCamera {
        var camera = NightSeaCamera()
        camera.orientation = starView
        camera.focalOverride = focal(forFieldOfView:WormholeTimeline.landingFieldOfView)
        return camera
    }

    /// The pinhole as a Night Sea camera (what the garden renders during the reframe).
    func camera(_ tt: Double) -> NightSeaCamera {
        let p = pinhole(tt,frame:frame(tt))
        var camera = NightSeaCamera()
        camera.orientation = p.orientation
        camera.focalOverride = p.focal
        camera.centerYFraction = p.centerY
        return camera
    }

    static func orientation(of camera: NightSeaCamera) -> simd_quatd {
        if let orientation = camera.orientation { return orientation }
        return WormholeFreeze.orientation(forward:camera.forward,right:camera.right,up:camera.up)
    }

    /// Focal length (points) that gives the kit field of view `fov` on this screen.
    func focalLength(fieldOfView fov: Double) -> Double { focal(forFieldOfView:fov) }
}

/// Temporary visual placement for an indoor demo capture; its observation is saved separately.
struct WormholeDemo {
    let item: GardenCollectionItem
    let object: NightSeaObject

    /// Places `star` where the frozen camera looks (lifted to at least 15° up so the Night Sea shows it).
    static func make(star: CatalogStar,freeze: WormholeFreeze,location: ObserverLocation?) -> WormholeDemo {
        var direction = freeze.orientation.act(SIMD3<Double>(0,0,-1))
        let minimum = sin(15 * Double.pi/180)
        if direction.z < minimum {
            let flat = simd_normalize(SIMD3(direction.x,direction.y,0)+SIMD3(0,1e-6,0))
            direction = simd_normalize(flat*cos(15 * Double.pi/180)+SIMD3(0,0,minimum))
        }
        let record = CollectedStar(id:star.id,date:Date(),latitude:location?.latitude ?? -6.2,longitude:location?.longitude ?? 106.85,
                                   identificationNote:"Simulated constellation demo capture (debug build).")
        let radius = NightSeaObject.starRadius(magnitude:star.mag)*1.3
        return WormholeDemo(item:GardenCollectionItem(star:star,record:record),
                            object:NightSeaObject(id:star.id,direction:direction,radius:radius,color:star.rgb,kind:.star))
    }
}
