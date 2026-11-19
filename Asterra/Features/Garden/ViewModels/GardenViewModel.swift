import AVFoundation
import Observation
import SwiftUI

/// Places collected objects and owns garden camera gestures and sensor lifecycle.
@MainActor @Observable
final class GardenViewModel {
    let model: HomeViewModel
    var camera: NightSeaCamera
    private(set) var usesGyro = true
    private var raisedSince: TimeInterval?
    private var lastPhoneDirection: SIMD3<Double>?
    private var touchReferenceDirection: SIMD3<Double>?

    var placed: [GardenPlacedObject] = []
    private let constellationFigures = GardenConstellationConnection.loadFigures()
    private(set) var constellationConnections: [GardenConstellationConnection] = []
    private let zodiacFigures = GardenZodiacFigure.load()
    private(set) var completedZodiacFigures: [GardenZodiacFigure] = []
    #if DEBUG
    private var showsDemoConstellations = false
    @ObservationIgnored private lazy var demoConstellationStarIDs = zodiacFigures
        .reduce(into: Set<Int>()) { $0.formUnion($1.requiredStarIDs) }
    #endif
    /// Temporary demo placement stays in the sky until its sheet closes.
    var demo: WormholeDemo?
    var moon: (direction: SIMD3<Double>, illumination: Double)?
    var equatorial: simd_double3x3?
    var gpsLocation: ObserverLocation?
    /// Created once when the garden starts (not on every view update).
    var motion: MotionService?
    var gyroLive = false
    var dragStart: (azimuth: Double, altitude: Double)?
    /// Translation already consumed when the current drag (re)started, e.g. after a pinch.
    private var dragBaseline = CGSize.zero
    /// Focal length (points) when the pinch began: one unit for both gyro and touch mode, so a
    /// mode switch during the pinch cannot make the zoom jump.
    var zoomStart: Double?
    /// Last garden size seen by a gesture; converts the touch zoom when the gyro takes over.
    private var viewSize = CGSize.zero
    /// Smooth motion: the zoom eases toward the pinch's goal, a released drag glides on.
    private var zoomGoal: (focal: Double, anchor: CGPoint)?
    private var glide: SIMD2<Double>?          // azimuth, altitude in rad/s
    private var motionTask: Task<Void, Never>?
    /// Keeps the pinhole projection while another camera drives the view (capture handover,
    /// onboarding focus), so hand-offs never jump between projections.
    var projectionLocked = false {
        didSet { if projectionLocked != oldValue { updateProjection() } }
    }
    var selected: GardenCollectionItem?
    var reduceMotion = false

    static let fallbackLocation = ObserverLocation(
        latitude: -6.2, longitude: 106.85, isManual: true)  // Jakarta
    private var location: ObserverLocation { gpsLocation ?? model.location ?? Self.fallbackLocation }

    init(model: HomeViewModel, camera: NightSeaCamera = NightSeaCamera()) {
        self.model = model
        self.camera = camera
        constellationConnections = GardenConstellationConnection.resolve(
            figures: constellationFigures, items: model.collectionItems)
        completedZodiacFigures = GardenZodiacFigure.unlocked(zodiacFigures, collected: Set(model.collected.keys))
    }

    func resetCamera() {
        if camera.orientation == nil {
            camera.azimuth = 0
            camera.altitude = 18 * .pi / 180
        }
        camera.fieldOfView = 72
        camera.zoom = 1
        updateProjection()
    }

    // MARK: Projection

    /// The projection the view should have: the stereographic dome only for the wide touch view.
    var projectionTarget: Double {
        guard !projectionLocked, !usesGyro, camera.orientation == nil, camera.focalOverride == nil else { return 0 }
        return GardenZoomLimits.domeBlend(fieldOfView: camera.fieldOfView)
    }

    /// Eases toward `projectionTarget` (immediately with Reduce Motion).
    func updateProjection() {
        let target = projectionTarget
        guard abs(target - camera.stereographic) > 1e-4 else { return }
        if reduceMotion { camera.stereographic = target } else { runMotion() }
    }

    // MARK: Placement

    #if DEBUG
    func setDemoConstellations(_ enabled: Bool) {
        guard showsDemoConstellations != enabled else { return }
        showsDemoConstellations = enabled
        place()
    }
    #endif

    func place() {
        let location = location
        let date = Date()
        var items = model.collectionItems
        var previewIDs: Set<Int> = []
        #if DEBUG
        if showsDemoConstellations {
            previewIDs = demoConstellationStarIDs.subtracting(model.collected.keys)
            if let demo { previewIDs.remove(demo.item.id) }
            items += model.stars.compactMap { star in
                guard previewIDs.contains(star.id) else { return nil }
                return GardenCollectionItem(star: star, record: CollectedStar(
                    id: star.id, date: date, latitude: location.latitude, longitude: location.longitude))
            }
        }
        #endif
        let scene = Self.placement(items: items, location: location, date: date, previewStarIDs: previewIDs)
        placed = scene.placed
        applyPlacement(moon: scene.moon, equatorial: scene.equatorial, items: items)
    }

    /// Use the exact positions already rendered in the wormhole for the landing.
    func place(using scene: WormholeScene) {
        var collectedObjects: [Int: NightSeaObject] = [:]
        for object in scene.objects {
            collectedObjects[object.id] = object
        }
        placed = model.collectionItems.compactMap { item in
            collectedObjects[item.id].map { GardenPlacedObject(item: item, object: $0) }
        }
        applyPlacement(moon: scene.moon, equatorial: scene.equatorial, items: model.collectionItems)
    }

    private func applyPlacement(moon: (direction: SIMD3<Double>, illumination: Double)?,
                                equatorial: simd_double3x3?, items: [GardenCollectionItem]) {
        if let demo {
            placed.removeAll { $0.id == demo.item.id }
            placed.append(GardenPlacedObject(item: demo.item, object: demo.object))
        }
        self.moon = moon
        self.equatorial = equatorial
        constellationConnections = GardenConstellationConnection.resolve(
            figures: constellationFigures, items: items)
        completedZodiacFigures = GardenZodiacFigure.unlocked(zodiacFigures, collected: Set(items.map(\.id)))
    }

    /// Every collected object at its real (refracted) position for this place and time.
    static func placement(
        items: [GardenCollectionItem], location: ObserverLocation, date: Date = Date(),
        previewStarIDs: Set<Int> = []
    ) -> (
        placed: [GardenPlacedObject], moon: (direction: SIMD3<Double>, illumination: Double)?,
        equatorial: simd_double3x3
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
            var phaseAngle = 0.0
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
                // Illuminated fraction k = (1 + cos α) / 2.
                phaseAngle = acos(min(1, max(-1, 2 * sky.moonIllumination - 1)))
            } else if star.isPlanet {
                guard let planet = sky.planets.first(where: { $0.star.id == star.id }) else { continue }
                geometric = planet.direction
                kind = .planet
                radius = min(5.2, max(2, 3.4 - 0.5 * planet.star.mag)) * 6
                color = star.rgb
                phaseAngle = (sky.planetPhaseAngles[star.id] ?? 0) * .pi / 180
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
                        radius: radius, color: color, kind: kind,
                        phaseAngle: phaseAngle, sunDirection: sky.sunDirection),
                    isPreview: previewStarIDs.contains(star.id)))
        }
        return (result, moonState, sky.basis)
    }

    /// The Night Sea as the wormhole should show it.
    static func wormholeScene(model: HomeViewModel, newID: Int?, demo: WormholeDemo? = nil, location: ObserverLocation? = nil) -> WormholeScene {
        let scene = placement(
            items: model.collectionItems, location: location ?? model.location ?? fallbackLocation)
        var objects = scene.placed.map(\.object)
        if let demo {
            objects.removeAll { $0.id == demo.object.id }
            objects.append(demo.object)
        }
        return WormholeScene(objects: objects, newID: newID, moon: scene.moon, equatorial: scene.equatorial)
    }

    // MARK: Gyro

    func startGyro(usesGyro: Bool) {
        motion?.stop()
        let service = motion ?? MotionService()
        motion = service
        camera.cameraFieldOfView = Self.backCameraFieldOfView
        service.onLocation = { [weak self] fix in
            self?.gpsLocation = fix
            self?.place()
        }
        service.onCalibration = { [weak self] ready, _, _, _ in
            guard let self else { return }
            self.gyroLive = ready && self.usesGyro
            // Keep the last rendered pose while direction recovers; this is not a touch-mode switch.
        }
        service.onAttitude = { [weak self] attitude in
            self?.receiveAttitude(attitude, at: ProcessInfo.processInfo.systemUptime)
        }
        // Keep north tracking alive in touch mode so raising the phone needs no new setup.
        setGyroMode(usesGyro)
        updateProjection()
        service.start(quiet: true) { _, _, _ in }
    }
    func setGyroMode(_ enabled: Bool) {
        guard enabled != usesGyro else { return }
        if enabled { carryTouchZoomToGyro() }
        usesGyro = enabled
        raisedSince = nil
        if !enabled {
            touchReferenceDirection = lastPhoneDirection
            gyroLive = false
            preserveTouchView()
        }
        updateProjection()
    }
    func stopGyro() {
        motionTask?.cancel()
        motionTask = nil
        if zoomGoal != nil { settleZoom() }
        glide = nil
        motion?.stop()
        gyroLive = false
        dragStart = nil
        zoomStart = nil
        raisedSince = nil
        touchReferenceDirection = nil
        lastPhoneDirection = nil
        // Freeze the complete projection while another screen opens. Converting to touch mode here
        // changes focal length, optical centre and roll, pulling labels away from the paused Metal sky.
    }
    /// Swiping owns the view until the user deliberately points the phone elsewhere.
    func receiveAttitude(_ attitude: simd_double3x3, at time: TimeInterval) {
        let direction = -attitude.columns.2
        let altitude = asin(min(1, max(-1, direction.z)))
        lastPhoneDirection = direction
        guard dragStart == nil, zoomStart == nil else {
            // Movement while touching must not count toward automatic reactivation.
            touchReferenceDirection = direction
            raisedSince = nil
            return
        }
        if !usesGyro {
            guard altitude >= -8 * .pi / 180, let reference = touchReferenceDirection else {
                touchReferenceDirection = direction
                raisedSince = nil
                return
            }
            // Ignore hand tremor and screen-axis roll; use a change in aim, not attitude.
            let change = acos(min(1, max(-1, simd_dot(reference, direction))))
            guard change >= 5 * .pi / 180 else {
                raisedSince = nil
                return
            }
            if raisedSince == nil { raisedSince = time }
            guard time - (raisedSince ?? time) >= 0.15 else { return }
            carryTouchZoomToGyro()
            usesGyro = true
            raisedSince = nil
        }
        gyroLive = true
        glide = nil
        follow(attitude)
        if camera.stereographic > 0 { updateProjection() }
    }
    /// Keeps the apparent zoom when the gyro takes over from touch (the touch field of view
    /// becomes the gyro magnification), instead of snapping back to 1×.
    private func carryTouchZoomToGyro() {
        guard camera.orientation == nil, viewSize.width > 0, viewSize.height > 0 else { return }
        let touchFocal = camera.focalLength(in: viewSize)
        var gyro = camera
        gyro.orientation = simd_quatd(angle: 0, axis: SIMD3(0, 0, 1))
        gyro.zoom = 1
        camera.zoom = min(GardenZoomLimits.maxGyroZoom, max(0.5, touchFocal / gyro.focalLength(in: viewSize)))
    }

    private func preserveTouchView() {
        guard camera.orientation != nil else { return }
        let direction = camera.forward
        camera.azimuth = atan2(direction.x, direction.y)
        camera.altitude = asin(min(1, max(-1, direction.z)))
        camera.orientation = nil
    }
    /// Follow the real viewing direction without a drag offset or artificial upward tilt.
    private func follow(_ attitude: simd_double3x3) {
        let sensor = simd_quatd(attitude)
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
        guard size.width > 0, size.height > 0 else { return }
        viewSize = size
        // Two fingers belong to the pinch: no panning (and no gyro→touch switch) meanwhile.
        // When one finger stays down afterwards, panning resumes from where the pinch left it.
        if zoomStart != nil {
            dragStart = nil
            return
        }
        if dragStart == nil {
            glide = nil
            dragBaseline = translation
            if camera.orientation != nil {
                // Preserve the apparent zoom and optical centre when the finger takes over.
                let focal = camera.focalLength(in: size)
                camera.fieldOfView = 2 * atan(Double(min(size.width, size.height)) * 0.62 / focal) * 180 / .pi
                camera.centerYFraction = 0.5
            }
            setGyroMode(false)
            preserveTouchView()
            updateProjection()
            dragStart = (camera.azimuth, camera.altitude)
        }
        guard let start = dragStart else { return }
        let k = GardenZoomLimits.dragRadiansPerPoint(
            fieldOfView: camera.fieldOfView, focalLength: camera.focalLength(in: size))
        camera.azimuth = start.azimuth - (translation.width - dragBaseline.width) * k
        camera.altitude = min(
            88 * .pi / 180, max(-88 * .pi / 180, start.altitude + (translation.height - dragBaseline.height) * k))
    }
    /// Pinch zoom in either mode. Gyro: magnification over the real camera view (up to 12×).
    /// Touch: field of view down to 1.5°, zooming toward the pinch.
    func pinch(_ magnification: Double, anchor: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        viewSize = size
        if zoomStart == nil {
            // Continue from where an unfinished ease is heading, so a quick re-pinch never jumps back.
            zoomStart = zoomGoal?.focal ?? camera.focalLength(in: size)
            glide = nil
        }
        let goal = clampedFocal((zoomStart ?? 1) * pow(magnification, GardenZoomLimits.pinchExponent))
        zoomGoal = (goal, anchor)
        if reduceMotion { settleZoom() } else { runMotion() }
    }

    /// A released drag keeps gliding and slows down (touch mode; none with Reduce Motion).
    func endDrag(velocity: CGSize, in size: CGSize) {
        dragStart = nil
        guard !reduceMotion, camera.orientation == nil, zoomStart == nil, size.width > 0 else { return }
        let k = GardenZoomLimits.dragRadiansPerPoint(
            fieldOfView: camera.fieldOfView, focalLength: camera.focalLength(in: size))
        let speed = SIMD2(-velocity.width * k, velocity.height * k)
        // Ignore a resting release (under ~60 pt/s on screen).
        guard simd_length(speed) * camera.focalLength(in: size) > 60 else { return }
        viewSize = size
        glide = speed
        runMotion()
    }

    /// Jumps to the zoom the current ease is heading for.
    func settleZoom() {
        guard let goal = zoomGoal else { return }
        applyFocal(goal.focal, anchor: goal.anchor)
        zoomGoal = nil
    }

    /// One frame of smooth motion; false when nothing is left to animate.
    @discardableResult func advanceMotion(_ dt: Double) -> Bool {
        var active = false
        let dome = projectionTarget
        if abs(dome - camera.stereographic) > 1e-3 {
            camera.stereographic += (dome - camera.stereographic) * (1 - exp(-dt * GardenZoomLimits.domeEase))
            active = true
        } else if camera.stereographic != dome {
            camera.stereographic = dome
        }
        guard viewSize.width > 0, viewSize.height > 0 else { return active }
        if let goal = zoomGoal {
            let current = camera.focalLength(in: viewSize)
            // Ease in log space: every step feels the same at 2× and at 100×.
            let remaining = log(goal.focal / current)
            if abs(remaining) < 0.002 {
                applyFocal(goal.focal, anchor: goal.anchor)
                if zoomStart == nil { zoomGoal = nil }
            } else {
                applyFocal(current * exp(remaining * (1 - exp(-dt * GardenZoomLimits.zoomEase))), anchor: goal.anchor)
                active = true
            }
        }
        if let speed = glide {
            if camera.orientation == nil, dragStart == nil {
                camera.azimuth += speed.x * dt
                camera.altitude = min(88 * .pi / 180, max(-88 * .pi / 180, camera.altitude + speed.y * dt))
                let slowed = speed * exp(-dt * GardenZoomLimits.glideFriction)
                glide = simd_length(slowed) * camera.focalLength(in: viewSize) > 8 ? slowed : nil
            } else {
                glide = nil
            }
            active = active || glide != nil
        }
        return active
    }

    private func runMotion() {
        guard motionTask == nil else { return }
        motionTask = Task { @MainActor [weak self] in
            let clock = ContinuousClock()
            var last = clock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(8))
                let now = clock.now
                let dt = min(0.05, Double((now - last).components.attoseconds) / 1e18 + Double((now - last).components.seconds))
                last = now
                guard let self, self.advanceMotion(dt) else { break }
            }
            self?.motionTask = nil
        }
    }

    /// Clamps a focal length (points) to the zoom range of the current mode.
    private func clampedFocal(_ focal: Double) -> Double {
        if camera.orientation != nil {
            let base = camera.focalLength(in: viewSize) / max(camera.zoom, 1e-6)
            return min(base * GardenZoomLimits.maxGyroZoom, max(base * 0.5, focal))
        }
        let short = Double(min(viewSize.width, viewSize.height))
        func focalLength(at fov: Double) -> Double { 0.62 * short / tan(fov * .pi / 360) }
        return min(focalLength(at: GardenZoomLimits.minFieldOfView), max(focalLength(at: 110), focal))
    }

    private func applyFocal(_ focal: Double, anchor: CGPoint) {
        if camera.orientation != nil {
            let base = camera.focalLength(in: viewSize) / max(camera.zoom, 1e-6)
            camera.zoom = min(GardenZoomLimits.maxGyroZoom, max(0.5, focal / base))
        } else {
            let fov = 2 * atan(0.62 * Double(min(viewSize.width, viewSize.height)) / focal) * 180 / .pi
            zoomTouch(fieldOfView: min(110, max(GardenZoomLimits.minFieldOfView, fov)), anchor: anchor, in: viewSize)
        }
        if reduceMotion { camera.stereographic = projectionTarget }
    }

    /// Touch mode pinch: sets the field of view while the sky under `anchor` (the pinch's
    /// starting point) stays under the fingers.
    func zoomTouch(fieldOfView: Double, anchor: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { camera.fieldOfView = fieldOfView; return }
        let c = camera.center(in: size)
        let pinned = camera.direction(at: anchor, in: size)
        camera.fieldOfView = fieldOfView
        let after = camera.focalLength(in: size)
        let altitude = asin(min(1, max(-1, pinned.z)))
        camera.altitude = min(88 * .pi / 180, max(-88 * .pi / 180,
            altitude - atan((c.y - anchor.y) / after)))
        camera.azimuth = atan2(pinned.x, pinned.y) - atan((anchor.x - c.x) / after) / max(cos(altitude), 0.2)
        // Refine: the estimate above treats the two axes separately; a few corrections pin it.
        for _ in 0..<6 {
            guard let point = camera.project(pinned, in: size) else { break }
            camera.azimuth += (point.x - anchor.x) / after / max(cos(altitude), 0.2)
            camera.altitude = min(88 * .pi / 180, max(-88 * .pi / 180,
                camera.altitude - (point.y - anchor.y) / after))
        }
    }

    /// Selects the tapped collected object; false when the tap hit no object.
    @discardableResult func tap(at point: CGPoint, in size: CGSize) -> Bool {
        let hits = placed.compactMap { entry -> (GardenPlacedObject, CGFloat)? in
            guard entry.object.isAboveHorizon, let p = camera.project(entry.object.direction, in: size)
            else { return nil }
            let distance = hypot(p.x - point.x, p.y - point.y)
            return distance <= entry.object.apparent(camera: camera, in: size).hitRadius ? (entry, distance) : nil
        }
        guard let hit = hits.min(by: { $0.1 < $1.1 }) else { return false }
        if !hit.0.isPreview { selected = hit.0.item }
        return true
    }
}
