import AVFoundation
import Observation
import SwiftUI

/// Places collected objects and owns garden camera gestures and sensor lifecycle.
@MainActor @Observable
final class GardenViewModel {
    let model: HomeViewModel
    var camera: NightSeaCamera
    private var usesGyro = true

    var placed: [GardenPlacedObject] = []
    /// Decorative background star field (not tappable, no labels).
    var background: [NightSeaObject] = []
    /// Debug replay: the demo object stays in the sky until its sheet closes (never saved).
    var demo: WormholeDemo?
    var moon: (direction: SIMD3<Double>, illumination: Double)?
    var equatorial: simd_double3x3?
    var gpsLocation: ObserverLocation?
    /// Created once when the garden starts (not on every view update).
    var motion: MotionService?
    var gyroLive = false
    var gyroMessage: String?
    var gyroStage: MotionCalibrationStage = .location
    var gyroProgress: Double = 0
    var offset = (azimuth: 0.0, altitude: 0.0)
    var dragStart: (azimuth: Double, altitude: Double)?
    var zoomStart: Double?
    var selected: GardenCollectionItem?
    var reduceMotion = false

    static let fallbackLocation = ObserverLocation(
        latitude: -6.2, longitude: 106.85, isManual: true)  // Jakarta
    private var location: ObserverLocation { gpsLocation ?? model.location ?? Self.fallbackLocation }

    init(model: HomeViewModel, camera: NightSeaCamera = NightSeaCamera()) {
        self.model = model
        self.camera = camera
    }

    func resetCamera() {
        offset = (0, 0)
        if camera.orientation == nil {
            camera.azimuth = 0
            camera.altitude = 18 * .pi / 180
        }
        camera.fieldOfView = 72
        camera.zoom = 1
    }

    // MARK: Placement

    func place() {
        let scene = Self.placement(
            items: model.collectionItems, location: location, catalogue: model.stars,
            excluding: demo.map { [$0.item.id] } ?? [])
        background = scene.background
        placed = scene.placed
        if let demo, !placed.contains(where: { $0.id == demo.item.id }) {
            placed.append(GardenPlacedObject(item: demo.item, object: demo.object))
        }
        moon = scene.moon
        equatorial = scene.equatorial
    }

    /// Every collected object at its real (refracted) position for this place and time, plus the
    /// decorative background star field.
    static func placement(
        items: [GardenCollectionItem], location: ObserverLocation, date: Date = Date(),
        catalogue: [CatalogStar] = [], excluding extra: Set<Int> = []
    ) -> (
        placed: [GardenPlacedObject], moon: (direction: SIMD3<Double>, illumination: Double)?,
        equatorial: simd_double3x3, background: [NightSeaObject]
    ) {
        let sky = AstronomyService.snapshot(date: date, location: location)
        var result: [GardenPlacedObject] = []
        var moonState: (direction: SIMD3<Double>, illumination: Double)?
        for item in items {
            let star = item.star
            let geometric: SIMD3<Double>
            let kind: NightSeaObject.Kind
            let radius: Double
            let color: SIMD3<Double>
            if star.isSun {
                geometric = sky.sunDirection
                kind = .sun
                radius = 46
                color = SIMD3(1, 0.82, 0.52)
            } else if star.isMoon {
                geometric = sky.moonDirection
                kind = .moon
                radius = 38
                color = SIMD3(0.88, 0.91, 1)
                moonState = (Refraction.apparent(geometric), sky.moonIllumination)
            } else if star.isPlanet {
                guard let planet = sky.planets.first(where: { $0.star.id == star.id }) else { continue }
                geometric = planet.direction
                kind = .planet
                radius = min(5.2, max(2, 3.4 - 0.5 * planet.star.mag)) * 6
                color = star.rgb
            } else {
                geometric = sky.direction(ra: star.ra_deg, dec: star.dec_deg)
                kind = .star
                radius = NightSeaObject.starRadius(magnitude: star.mag) * 1.3
                color = star.rgb
            }
            result.append(
                GardenPlacedObject(
                    item: item,
                    object: NightSeaObject(
                        id: star.id, direction: Refraction.apparent(geometric),
                        radius: radius, color: color, kind: kind)))
        }
        // Decorative star field (the kit's HYG layer to mag 6.2), toned down in the shader so it never reads as a
        // collected star: smaller, dimmer, no spikes, glow only for the very brightest, faint dust beyond mag 5.
        let collected = Set(items.map(\.star.id)).union(extra)
        let background = catalogue.lazy
            .filter { $0.mag <= Self.backgroundLimit && !collected.contains($0.id) && !$0.isSolarSystemBody }
            .compactMap { star -> NightSeaObject? in
                let direction = Refraction.apparent(sky.direction(ra: star.ra_deg, dec: star.dec_deg))
                guard direction.z > -0.01 else { return nil }
                return NightSeaObject(id: -star.id - 1, direction: direction, radius: star.mag, color: star.rgb, kind: .background)
            }
        return (result, moonState, sky.basis, Array(background))
    }
    static let backgroundLimit = 6.2

    /// The Night Sea as the wormhole should show it.
    static func wormholeScene(model: HomeViewModel, newID: Int?, demo: WormholeDemo? = nil) -> WormholeScene {
        let scene = placement(
            items: model.collectionItems, location: model.location ?? fallbackLocation, catalogue: model.stars,
            excluding: demo.map { [$0.object.id] } ?? [])
        var objects = scene.background + scene.placed.map(\.object)
        if let demo {
            objects.removeAll { $0.id == demo.object.id }
            objects.append(demo.object)
        }
        return WormholeScene(objects: objects, newID: newID, moon: scene.moon, equatorial: scene.equatorial)
    }

    // MARK: Gyro

    func startGyro(usesGyro: Bool) {
        self.usesGyro = usesGyro
        motion?.stop()
        let service = motion ?? MotionService()
        motion = service
        camera.cameraFieldOfView = Self.backCameraFieldOfView
        service.onLocation = { [weak self] fix in
            self?.gpsLocation = fix
            self?.place()
        }
        service.onCalibration = { [weak self] ready, progress, message, stage in
            guard let self, self.usesGyro else { return }
            self.gyroLive = ready
            self.gyroStage = stage
            self.gyroProgress = progress
            self.gyroMessage = ready ? nil : message
            if !ready { self.preserveTouchView() }
        }
        service.onAttitude = { [weak self] attitude in
            guard let self, self.usesGyro else { return }
            self.follow(attitude)
        }
        if usesGyro {
            gyroLive = false
            gyroMessage = "Preparing gyro. You can still drag the sky."
            gyroStage = .location
            gyroProgress = 0
            service.start { _, _, _ in }
        } else {
            gyroLive = false
            gyroMessage = nil
            preserveTouchView()
            service.startLocationUpdates()
        }
    }
    func stopGyro() {
        motion?.stop()
        gyroLive = false
        gyroMessage = nil
        preserveTouchView()
    }
    private func preserveTouchView() {
        guard camera.orientation != nil else { return }
        let direction = camera.forward
        camera.azimuth = atan2(direction.x, direction.y)
        camera.altitude = asin(min(1, max(-1, direction.z)))
        camera.orientation = nil
    }
    /// Phone attitude -> camera orientation, plus the user's drag offset (turn left/right, tilt up/down).
    private func follow(_ attitude: simd_double3x3) {
        var sensor = simd_quatd(attitude)
        // Calibrated compass error (see SkyCalibration): turn the sensor's north to true north.
        let correction = SkyCalibration.motionHeadingOffset
        if correction != 0 { sensor = simd_quatd(angle: -correction, axis: SIMD3(0, 0, 1)) * sensor }
        // A few degrees of extra upward tilt by default, so the horizon rests lower and the sky dominates.
        let tilt = offset.altitude + Self.restingTilt
        if offset.azimuth != 0 || tilt != 0 {
            let yaw = simd_quatd(angle: -offset.azimuth, axis: SIMD3(0, 0, 1))  // around the world's vertical
            let pitch = simd_quatd(angle: tilt, axis: SIMD3(1, 0, 0))  // around the phone's own right axis
            sensor = yaw * sensor * pitch
        }
        guard let current = camera.orientation, !reduceMotion else {
            camera.orientation = sensor
            return
        }
        // Light smoothing against sensor jitter; still follows the phone within a few frames.
        camera.orientation = simd_slerp(current, sensor, 0.45)
    }
    /// Default upward tilt of the gyro view (radians).
    private static let restingTilt = 4 * Double.pi / 180
    /// Horizontal (long-side) field of view of the back wide camera, used for the 1:1 window.
    private static let backCameraFieldOfView: Double = {
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        else { return 69 }
        let fov = Double(device.activeFormat.videoFieldOfView)
        return fov > 20 && fov < 130 ? fov : 69
    }()

    // MARK: Gestures

    func drag(_ translation: CGSize, in size: CGSize) {
        if dragStart == nil {
            dragStart = camera.orientation != nil ? offset : (camera.azimuth, camera.altitude)
        }
        guard let start = dragStart else { return }
        // Degrees per point of the current view, so the sky follows the finger.
        let k =
            camera.orientation != nil
            ? 1 / camera.focalLength(in: size)
            : camera.fieldOfView / Double(min(size.width, size.height)) * 1.15 * .pi / 180
        let azimuth = start.azimuth - translation.width * k
        if camera.orientation != nil {
            offset = (
                atan2(sin(azimuth), cos(azimuth)),
                min(60 * .pi / 180, max(-60 * .pi / 180, start.altitude + translation.height * k))
            )
        } else {
            camera.azimuth = azimuth
            camera.altitude = min(
                88 * .pi / 180, max(-35 * .pi / 180, start.altitude + translation.height * k))
        }
    }
    /// Selects the tapped collected object; false when the tap hit no object.
    @discardableResult func tap(at point: CGPoint, in size: CGSize) -> Bool {
        let hits = placed.compactMap { entry -> (GardenPlacedObject, CGFloat)? in
            guard entry.object.isAboveHorizon, let p = camera.project(entry.object.direction, in: size)
            else { return nil }
            let distance = hypot(p.x - point.x, p.y - point.y)
            return distance <= max(36, entry.object.radius * 0.6) ? (entry, distance) : nil
        }
        guard let hit = hits.min(by: { $0.1 < $1.1 }) else { return false }
        selected = hit.0.item
        return true
    }
}
