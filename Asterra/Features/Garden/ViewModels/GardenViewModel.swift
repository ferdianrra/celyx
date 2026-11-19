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
    var zoomStart: Double?
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
        let items = model.collectionItems
        let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        placed = scene.objects.compactMap { object in
            let link = scene.conjunctionMembers[object.id]
            guard let item = itemsByID[link?.itemID ?? object.id] else { return nil }
            return GardenPlacedObject(item: item, object: object, memberName: link?.name)
        }
        applyPlacement(moon: scene.moon, equatorial: scene.equatorial, items: items)
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
            if let event = item.record.skyEvent {
                let sky = SkyEventCatalog.guidance(of: event.target, at: date, location: location)
                if !sky.members.isEmpty {
                    for (index, member) in sky.members.enumerated() {
                        let isMoon = member.name == "Moon"
                        let planet = CatalogStar.planets.first { $0.title == member.name }
                        // The first member keeps the event ID. The second uses a separate range of render IDs.
                        let markerID = index == 0 ? item.id : Int.min - item.id
                        let object = NightSeaObject(id: markerID, direction: member.position.direction,
                            radius: isMoon ? 38 : min(5.2, max(2, 3.4 - 0.5 * (planet?.mag ?? 0))) * 6,
                            color: isMoon ? SIMD3(0.88, 0.91, 1) : planet?.rgb ?? SIMD3(0.69, 0.78, 1),
                            kind: isMoon ? .moon : .planet)
                        result.append(GardenPlacedObject(item: item, object: object, memberName: member.name))
                    }
                    continue
                }
                geometric = sky.position.direction
                kind = .star
                radius = 5
                color = SIMD3(0.69, 0.78, 1)
            } else if star.isSun {
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
                        id: star.id, direction: item.record.skyEvent == nil ? Refraction.apparent(geometric) : geometric,
                        radius: radius, color: color, kind: kind),
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
        let members = scene.placed.compactMap { entry -> (Int, WormholeScene.ConjunctionMember)? in
            guard let name = entry.memberName else { return nil }
            return (entry.id, .init(itemID: entry.item.id, name: name))
        }
        return WormholeScene(objects: objects, newID: newID, moon: scene.moon, equatorial: scene.equatorial,
            conjunctionMembers: Dictionary(uniqueKeysWithValues: members))
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
        service.start(quiet: true) { _, _, _ in }
    }
    func setGyroMode(_ enabled: Bool) {
        guard enabled != usesGyro else { return }
        usesGyro = enabled
        raisedSince = nil
        if !enabled {
            touchReferenceDirection = lastPhoneDirection
            gyroLive = false
            preserveTouchView()
        }
    }
    func stopGyro() {
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
            usesGyro = true
            raisedSince = nil
        }
        gyroLive = true
        follow(attitude)
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
        var sensor = simd_quatd(attitude)
        // Calibrated compass error (see SkyCalibration): turn the sensor's north to true north.
        let correction = SkyCalibration.motionHeadingOffset
        if correction != 0 { sensor = simd_quatd(angle: -correction, axis: SIMD3(0, 0, 1)) * sensor }
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
        if dragStart == nil {
            if camera.orientation != nil {
                // Preserve the apparent zoom and optical centre when the finger takes over.
                let focal = camera.focalLength(in: size)
                camera.fieldOfView = 2 * atan(Double(min(size.width, size.height)) * 0.62 / focal) * 180 / .pi
                camera.centerYFraction = 0.5
            }
            setGyroMode(false)
            preserveTouchView()
            dragStart = (camera.azimuth, camera.altitude)
        }
        guard let start = dragStart else { return }
        let k = camera.fieldOfView / Double(min(size.width, size.height)) * 1.15 * .pi / 180
        camera.azimuth = start.azimuth - translation.width * k
        camera.altitude = min(
            88 * .pi / 180, max(-88 * .pi / 180, start.altitude + translation.height * k))
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
        if !hit.0.isPreview { select(hit.0.selectionItem) }
        return true
    }

    func select(_ item: GardenCollectionItem) {
        // A separately captured body keeps its own album. Event-only bodies open their profile.
        if item.isEventMember, let ownCapture = model.collected[item.star.id] {
            selected = GardenCollectionItem(star: item.star, record: ownCapture)
        } else {
            selected = item
        }
    }
}
