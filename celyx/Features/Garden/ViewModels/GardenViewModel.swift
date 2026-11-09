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

    private static let fallbackLocation = ObserverLocation(
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
        let sky = AstronomyService.snapshot(date: Date(), location: location)
        var result: [GardenPlacedObject] = []
        var moonState: (direction: SIMD3<Double>, illumination: Double)?
        for item in model.collectionItems {
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
                radius = min(5, max(0.8, 3.0 - 0.55 * star.mag)) * 7
                color = star.rgb
            }
            result.append(
                GardenPlacedObject(
                    item: item,
                    object: NightSeaObject(
                        id: star.id, direction: Refraction.apparent(geometric),
                        radius: radius, color: color, kind: kind)))
        }
        placed = result
        moon = moonState
        equatorial = sky.basis
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
        if offset.azimuth != 0 || offset.altitude != 0 {
            let yaw = simd_quatd(angle: -offset.azimuth, axis: SIMD3(0, 0, 1))  // around the world's vertical
            let pitch = simd_quatd(angle: offset.altitude, axis: SIMD3(1, 0, 0))  // around the phone's own right axis
            sensor = yaw * sensor * pitch
        }
        guard let current = camera.orientation, !reduceMotion else {
            camera.orientation = sensor
            return
        }
        // Light smoothing against sensor jitter; still follows the phone within a few frames.
        camera.orientation = simd_slerp(current, sensor, 0.45)
    }
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
    func tap(at point: CGPoint, in size: CGSize) {
        let hits = placed.compactMap { entry -> (GardenPlacedObject, CGFloat)? in
            guard entry.object.isAboveHorizon, let p = camera.project(entry.object.direction, in: size)
            else { return nil }
            let distance = hypot(p.x - point.x, p.y - point.y)
            return distance <= max(36, entry.object.radius * 0.6) ? (entry, distance) : nil
        }
        if let hit = hits.min(by: { $0.1 < $1.1 }) { selected = hit.0.item }
    }
}
