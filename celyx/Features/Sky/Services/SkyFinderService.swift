import UIKit
import AVFoundation
import CoreImage
import CoreLocation
import Observation
import simd

@MainActor @Observable
final class SkyFinderService: NSObject, SkyCaptureSessionDelegate, CLLocationManagerDelegate {
    enum Status: Equatable {
        case preparing, requestingPermission, tracking
        case limited(String)
        case unavailable(String)
        case denied(String)
    }
    private(set) var status: Status = .preparing
    private(set) var projection: SkyFinderProjection?
    private(set) var altitude: Double?
    let alignment: CameraSkyAlignment
    var session: SkyCaptureSession { alignment.session }
    private let locationManager = CLLocationManager()
    private let star: CatalogStar?
    private let catalogue: [CatalogStar]
    private let showsPredictions: Bool
    private(set) var predictions: [CameraSkyPrediction] = []
    private(set) var annotations: [CameraStarAnnotation] = []
    private(set) var viewableObjects: [StarObservation] = []
    private(set) var visibilityLimit: Double = 0
    private var visibilityFilters = VisibilityFilters()
    private var visibilityQuality: SkyQuality = .city
    private var visibilityAtmosphere = Atmosphere()
    @ObservationIgnored private var likelyVisibleIDs: Set<Int> = []
    @ObservationIgnored private var lastOverlayTime: TimeInterval = -1
    @ObservationIgnored private var detectionGeneration = 0
    @ObservationIgnored private var detectionTask: Task<Void, Never>?
    @ObservationIgnored private var pointStack = CameraPointStack()
    @ObservationIgnored private var pinnedPointStack = CameraPointStack()
    private(set) var pointScanProgress: Double = 0
    private(set) var automaticMapping = CameraAutomaticMappingProgress()
    @ObservationIgnored private var automaticMappingTask: Task<Void, Never>?
    @ObservationIgnored private var mappingConsensus = SkyPatternConsensus()
    @ObservationIgnored private var lastMappingAttempt: TimeInterval = -1
    var isMappingSky: Bool { alignment.requiresCalibration && automaticMapping.isSearching }
    var automaticMappingMessage: String { automaticMapping.message }
    private(set) var isDetectingOnDemand = false
    @ObservationIgnored private var detectionFeedbackTask: Task<Void, Never>?
    var canRequestDetection: Bool {
        running && hasStartedSession && hasLocationFix && status == .tracking && !isAdjustingCamera
            && pinnedLight != nil && retainedCaptureAnnotation == nil
    }
    private(set) var pinnedLight: CameraLightPin?
    private var retainedCapture: RetainedStarCapture?
    @ObservationIgnored private var lastCaptureCacheTime: TimeInterval = -1
    var retainedCaptureAnnotation: CameraStarAnnotation? {
        guard running, !isAdjustingCamera,
            let retainedCapture, retainedCapture.generation == alignment.generation
        else { return nil }
        guard let frame = session.currentFrame, let direction = retainedCapture.annotation.sourceDirection
        else { return nil }
        if status != .tracking {
            guard case .limited = status else { return nil }
            switch frame.camera.trackingState {
            case .limited(.insufficientFeatures), .limited(.excessiveMotion): break
            default: return nil
            }
        }
        let guide = SkyFinderProjection.project(
            direction: direction,
            view: frame.camera.viewMatrix(viewRotationAngle: viewRotationAngle),
            projection: screenProjection(frame), size: viewport)
        let center = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        guard CameraTargetSelection.keepsRetainedTarget(at: guide.point, center: center) else { return nil }
        if let pin = pinnedLight, !pin.isSameSource(direction),
            CameraTargetSelection.beginsNewSource(
                previousPoint: guide.point,
                newPoint: pinnedLightGuide?.point ?? CGPoint(x: -1000, y: -1000), center: center,
                observations: pin.observationCount)
        {
            return nil
        }
        let saved = retainedCapture.annotation
        guard let point = guide.point else { return nil }
        return CameraStarAnnotation(
            star: saved.star, point: point, size: saved.size,
            estimatedSeparation: saved.estimatedSeparation, sourceDirection: saved.sourceDirection,
            observedAt: saved.observedAt)
    }
    private var reticleGate = CameraReticleGate()
    private(set) var isScanningNewLight = false
    private(set) var newLightIssue: CameraIdentificationIssue?
    @ObservationIgnored private var lastWideScan: TimeInterval = -1
    private(set) var isGatheringInitialLight = false
    private var initialSearchStartedAt: TimeInterval?
    @ObservationIgnored private var lastPinAssessment: TimeInterval = -1
    @ObservationIgnored private var pendingDetection:
        (
            sources: [CameraLightPoint], time: TimeInterval,
            transform: CGAffineTransform, view: simd_float4x4, projection: simd_float4x4, size: CGSize
        )?
    @ObservationIgnored private var trackMatches: [Int: CameraCandidateMatch] = [:]
    @ObservationIgnored private var trackIssues: [Int: CameraIdentificationIssue] = [:]

    func updateVisibility(
        quality: SkyQuality, atmosphere: Atmosphere, filters: VisibilityFilters = .init()
    ) {
        guard
            visibilityFilters != filters || visibilityQuality != quality
                || visibilityAtmosphere != atmosphere || sky == nil
        else { return }
        visibilityFilters = filters
        visibilityQuality = quality
        visibilityAtmosphere = atmosphere
        sky = nil
    }
    private func refreshVisibility(_ sky: SkySnapshot) {
        viewableObjects = VisibilityEstimator.visibleObjects(
            stars: catalogue, sky: sky, quality: visibilityQuality, atmosphere: visibilityAtmosphere,
            filters: visibilityFilters)
        // Solar discs need their own daytime/phase rules, rather than the star darkness limit.
        for (star, direction) in scanDirections where star.isSolarDisc && direction.z > 0 {
            let clear = !visibilityFilters.clouds || (visibilityAtmosphere.cloudCover ?? 0) < 75
            let moonLit = sky.moonIllumination > 0.05 && sky.sunAltitude < -6
            if clear && (star.isSun || moonLit) {
                viewableObjects.append(
                    StarObservation(
                        star: star, direction: direction,
                        dimmedMagnitude: star.mag, likelyVisible: true, reason: "Above the horizon"))
            }
        }
        viewableObjects.sort {
            $0.dimmedMagnitude == $1.dimmedMagnitude
                ? $0.id < $1.id : $0.dimmedMagnitude < $1.dimmedMagnitude
        }
        likelyVisibleIDs = Set(viewableObjects.map(\.id))
    }
    private func discardPendingDetection() {
        predictions = []
        automaticMappingTask?.cancel()
        automaticMappingTask = nil
        mappingConsensus.reset()
        lastMappingAttempt = -1
        pointStack.reset()
        pinnedPointStack.reset()
        pointScanProgress = 0
        detectionGeneration += 1
        pendingDetection = nil
        trackMatches = [:]
        trackIssues = [:]
    }

    /// Catalog positions for the center reticle, separate from optical detection evidence.
    /// Collect still requires a matching camera observation before saving an object.
    var mappedObjects: [CameraMappedObject] {
        guard status == .tracking, !alignment.requiresCalibration,
            viewport.width > 0, viewport.height > 0, let frame = session.currentFrame
        else { return [] }
        let view = frame.camera.viewMatrix(viewRotationAngle: viewRotationAngle)
        let projection = screenProjection(frame)
        return scanDirections.compactMap { star, direction in
            let guide = SkyFinderProjection.project(
                direction: alignedDirection(direction),
                view: view, projection: projection, size: viewport)
            guard let point = guide.point else { return nil }
            return CameraMappedObject(
                star: star, point: point, likelyVisible: likelyVisibleIDs.contains(star.id))
        }
    }

    /// Bright bodies (Sun, Moon, planets) that are up right now, with the angle in degrees between each
    /// one's real direction (GPS + clock) and where the camera is pointing. Uses the angle rather than a
    /// screen point so a few degrees of compass error doesn't stop you aiming at a big, obvious disc.
    func brightBodiesNearAim() -> [(star: CatalogStar, separation: Double)] {
        guard !alignment.requiresCalibration, status == .tracking, let back = previousForward else {
            return []
        }
        let aim = simd_normalize(-back)
        return scanDirections.compactMap { star, direction in
            guard star.isSolarSystemBody else { return nil }
            let world = simd_normalize(SkyFinderProjection.worldDirection(direction))
            let separation = Double(acos(min(1, max(-1, simd_dot(aim, world))))) * 180 / .pi
            return (star, separation)
        }
    }

    func aimTarget(pinnedID: Int? = nil) -> CameraAimTarget? {
        guard !alignment.requiresCalibration, status == .tracking, !isAdjustingCamera, !scannerPaused
        else { return nil }
        let center = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        // The observed light takes precedence over its compass-derived catalog position.
        let objects = annotations.map {
            CameraMappedObject(
                star: $0.star, point: $0.point, likelyVisible: likelyVisibleIDs.contains($0.id))
        }
        let object: CameraMappedObject?
        if let pinnedID {
            object = objects.first(where: { $0.id == pinnedID })
        } else {
            let nearby = objects.filter {
                hypot($0.point.x - center.x, $0.point.y - center.y) <= min(viewport.width, viewport.height)
                    * 0.35
            }
            let observed = nearby.filter { object in annotations.contains(where: { $0.id == object.id }) }
            object = (observed.isEmpty ? nearby : observed)
                .min {
                    hypot($0.point.x - center.x, $0.point.y - center.y)
                        < hypot($1.point.x - center.x, $1.point.y - center.y)
                }
        }
        guard let object else { return nil }
        return CameraAimTarget(
            object: object, detection: annotations.first(where: { $0.id == object.id }))
    }
    private(set) var unidentifiedLights: [CameraLightAnnotation] = []
    private(set) var detectedLightCount = 0
    private(set) var cameraHeadingAccuracy: Double?
    private var opticalTracks: [CameraOpticalTrack] = []
    private var nextOpticalID = 0
    private(set) var skyDate: Date?
    var scannerPaused = false
    var observerLocation: ObserverLocation? { hasLocationFix ? location : nil }
    private var candidateHistory: [Int: (starID: Int, hits: Int)] = [:]
    private var lastDetectionTime: TimeInterval = -1
    private var previousForward: SIMD3<Float>?
    private var scanDirections: [(CatalogStar, SIMD3<Double>)] = []
    private(set) var exposureBias: Double = 0
    private(set) var cameraZoom: Double = 1
    private(set) var minimumExposure: Double = 0
    private(set) var maximumExposure: Double = 0
    private(set) var focusLocked = false
    private(set) var minimumZoom: Double = 1
    private(set) var maximumZoom: Double = CameraZoom.maximum
    private(set) var cameraControlMessage: String?
    private var captureDevice: AVCaptureDevice?
    private var originalExposure: Float?
    private var exposureDragStart: Double?
    private var exposurePresentation = CameraExposurePresentation()
    @ObservationIgnored private var exposureHideTask: Task<Void, Never>?
    private var originalLowLightBoost: Bool?
    private var originalFocusMode: AVCaptureDevice.FocusMode?
    private var originalExposureMode: AVCaptureDevice.ExposureMode?
    private var originalFocusRange: AVCaptureDevice.AutoFocusRangeRestriction?
    private var originalFocusPoint: CGPoint?
    private var originalExposurePoint: CGPoint?
    private var imageDisplayTransform = CGAffineTransform.identity
    private var focusSearchRegion: CGRect?
    private var focusSearchUntil: TimeInterval = 0
    private var controlsPrepared = false
    @ObservationIgnored private var lastFrameTime: TimeInterval = 0
    private var cameraSettling = CameraControlSettling()
    private var location: ObserverLocation
    private var hasLocationFix = false
    private var viewport = CGSize.zero
    private var orientation: UIInterfaceOrientation = .portrait
    private var running = false
    private var hasStartedSession = false
    private var frameStartedAt: TimeInterval = 0
    var isCameraRunning: Bool { hasStartedSession }
    var hasReferenceAlignment: Bool { alignment.reference != nil && !alignment.requiresCalibration }
    var isPinnedLightCentered: Bool {
        reticleGate.centeredID == pinnedLight?.match?.star.id && reticleGate.centeredID != nil
    }
    private(set) var isAdjustingCamera = false
    var pinnedLightGuide: SkyFinderProjection? {
        guard status == .tracking, lastFrameTime > 0, hasStartedSession,
            let pin = pinnedLight, let frame = session.currentFrame,
            viewport.width > 0, viewport.height > 0
        else { return nil }
        if alignment.requiresCalibration, lastFrameTime - pin.lastSeen >= 2 { return nil }
        switch frame.camera.trackingState {
        case .normal, .limited(.insufficientFeatures), .limited(.excessiveMotion): break
        default: return nil
        }
        return SkyFinderProjection.project(
            direction: pin.direction,
            view: frame.camera.viewMatrix(viewRotationAngle: viewRotationAngle),
            projection: screenProjection(frame), size: viewport)
    }
    var isRecognizingPinnedLight: Bool {
        status == .tracking && !isAdjustingCamera
            && (pinnedLight?.isRecognizing(at: lastFrameTime) ?? false)
    }
    var reacquiredPinnedAnnotation: CameraStarAnnotation? {
        guard status == .tracking, !isAdjustingCamera,
            let pin = pinnedLight, pin.isDetected(at: lastFrameTime), let match = pin.match,
            let point = pinnedLightGuide?.point,
            hypot(point.x - viewport.width / 2, point.y - viewport.height / 2) <= 28
        else { return nil }
        return CameraStarAnnotation(
            star: match.star, point: point, size: CGSize(width: 18, height: 18),
            estimatedSeparation: match.separation, sourceDirection: pin.direction,
            observedAt: pin.confirmedAt)
    }
    var canCaptureReference: Bool {
        guard status == .tracking, !isAdjustingCamera, let pin = pinnedLight,
            let point = pinnedLightGuide?.point
        else { return false }
        return pin.canUseAsReference(
            at: lastFrameTime,
            distance: hypot(point.x - viewport.width / 2, point.y - viewport.height / 2))
    }
    func captureFirstReference() -> CameraReferenceCapture? {
        guard canCaptureReference, let pin = pinnedLight else { return nil }
        let date = Date()
        let sky = AstronomyService.snapshot(date: date, location: location)
        let altitude = asin(Double(pin.direction.y)) * 180 / .pi
        let candidates = catalogue.filter { !$0.isSolarSystemBody && $0.mag <= 5.5 }.compactMap {
            star -> CalibrationCandidate? in
            let d = Refraction.apparent(sky.direction(ra: star.ra_deg, dec: star.dec_deg))
            let candidate = CalibrationCandidate(
                star: star, direction: SIMD3(Float(d.x), Float(d.z), Float(-d.y)))
            return candidate.altitude > 5 && candidate.altitude < 83
                && abs(candidate.altitude - altitude) <= 3 ? candidate : nil
        }.sorted {
            simd_dot(
                alignedDirection(
                    SIMD3(Double($0.direction.x), Double(-$0.direction.z), Double($0.direction.y))),
                pin.direction)
                > simd_dot(
                    alignedDirection(
                        SIMD3(Double($1.direction.x), Double(-$1.direction.z), Double($1.direction.y))),
                    pin.direction)
        }
        return CameraReferenceCapture(
            generation: alignment.generation, direction: pin.direction, date: date, location: location,
            candidates: candidates)
    }
    @discardableResult
    func confirmFirstReference(_ capture: CameraReferenceCapture, star: CatalogStar) -> Bool {
        guard status == .tracking, !isAdjustingCamera,
            let frame = session.currentFrame, case .normal = frame.camera.trackingState,
            capture.generation == alignment.generation, abs(capture.date.timeIntervalSinceNow) < 120,
            capture.candidates.contains(where: { $0.id == star.id })
        else { return false }
        let sky = AstronomyService.snapshot(date: capture.date, location: capture.location)
        let d = Refraction.apparent(sky.direction(ra: star.ra_deg, dec: star.dec_deg))
        let expected = SIMD3(Float(d.x), Float(d.z), Float(-d.y))
        guard running, hasStartedSession,
            let rotation = CalibrationReference.localRotation(
                expected: expected, observed: capture.direction,
                existingOffset: SkyCalibration.arHeadingOffset)
        else { return false }
        alignment.save(
            rotation: rotation,
            reference: star.title, date: Date(), location: capture.location)
        discardPendingDetection()
        opticalTracks = []
        candidateHistory = [:]
        annotations = []
        unidentifiedLights = []
        skyDate = nil
        self.sky = nil
        var pin = CameraLightPin(direction: capture.direction, time: lastFrameTime, observations: 2)
        pin.identify(using: CameraCandidateMatch(star: star, separation: 0, score: 0))
        pinnedLight = pin
        lastPinAssessment = -1
        updateReticleGate()
        return true
    }
    private func updateReticleGate() {
        let distance = pinnedLightGuide?.point.map {
            hypot($0.x - viewport.width / 2, $0.y - viewport.height / 2)
        }
        reticleGate.update(
            id: pinnedLight?.match?.star.id, distance: distance.map { Double($0) },
            enabled: pinnedLight?.isIdentified == true)
    }
    /// Request fresh optical analysis and catalog matching without changing the sensor world.
    @discardableResult
    func requestDetection() -> Bool {
        guard canRequestDetection, !isDetectingOnDemand else { return false }
        lastDetectionTime = -1
        lastWideScan = -1
        lastPinAssessment = -1
        lastMappingAttempt = -1
        sky = nil
        isDetectingOnDemand = true
        detectionFeedbackTask?.cancel()
        detectionFeedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self?.isDetectingOnDemand = false
            self?.detectionFeedbackTask = nil
        }
        return true
    }

    func clearPinnedLight(clearCapture: Bool = true) {
        if clearCapture {
            detectionFeedbackTask?.cancel()
            detectionFeedbackTask = nil
            isDetectingOnDemand = false
            retainedCapture = nil
            lastCaptureCacheTime = -1
        }
        pinnedLight = nil
        pinnedPointStack.reset()
        lastPinAssessment = -1
        initialSearchStartedAt = nil
        isGatheringInitialLight = false
        reticleGate.reset()
        isScanningNewLight = false
        newLightIssue = nil
    }
    var exposureControlVisible: Bool {
        exposurePresentation.isVisible(at: ProcessInfo.processInfo.systemUptime)
    }
    func setExposureEditing(_ editing: Bool) {
        exposureHideTask?.cancel()
        if editing {
            exposurePresentation.begin()
            return
        }
        exposurePresentation.end(at: ProcessInfo.processInfo.systemUptime)
        exposureHideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1300))
            guard !Task.isCancelled else { return }
            self?.exposurePresentation.reset()
        }
    }
    private var sky: SkySnapshot?
    /// Sun altitude (degrees) at the current GPS position and time, or nil before the first fix.
    var sunAltitude: Double? { sky?.sunAltitude }
    private var lastSnapshot = Date.distantPast
    private let photoContext = CIContext(options: [.cacheIntermediates: false])

    init(
        star: CatalogStar? = nil, location: ObserverLocation? = nil, catalogue: [CatalogStar] = [],
        showsPredictions: Bool = false, alignment: CameraSkyAlignment? = nil
    ) {
        self.alignment = alignment ?? CameraSkyAlignment()
        self.showsPredictions = showsPredictions
        self.star = star
        self.catalogue = catalogue.sorted { $0.mag < $1.mag }
        self.location = location ?? ObserverLocation(latitude: 0, longitude: 0)
        super.init()
        locationManager.delegate = self
    }

    private func screenProjection(_ frame: SkyCaptureFrame) -> simd_float4x4 {
        CameraZoom.projection(
            frame.camera.projectionMatrix(
                viewRotationAngle: viewRotationAngle,
                viewportSize: viewport, zNear: 0.01, zFar: 2000), zoom: cameraZoom)
    }
    private func screenImageTransform(_ frame: SkyCaptureFrame) -> CGAffineTransform {
        frame.displayTransform(viewRotationAngle: viewRotationAngle, viewportSize: viewport)
            .concatenating(CameraZoom.normalizedTransform(cameraZoom))
    }
    private func alignedDirection(_ horizon: SIMD3<Double>) -> SIMD3<Float> {
        if alignment.requiresCalibration {
            // A previous sensor world's saved compass correction cannot seed a new estimate.
            return SIMD3(Float(horizon.x), Float(horizon.z), Float(-horizon.y))
        }
        return alignment.correct(SkyFinderProjection.worldDirection(horizon))
    }
    func captureAlignmentFrame() -> CameraAlignmentFrame? {
        guard running, status == .tracking, hasLocationFix, !isAdjustingCamera,
            let frame = session.currentFrame, viewport.width > 0, viewport.height > 0
        else { return nil }
        let orientation: CGImagePropertyOrientation =
            switch self.orientation {
            case .landscapeRight: .up
            case .landscapeLeft: .down
            case .portraitUpsideDown: .left
            default: .right
            }
        let source = CIImage(cvPixelBuffer: frame.capturedImage).oriented(orientation)
        let crop = CameraZoom.imageCrop(extent: source.extent, viewport: viewport, zoom: cameraZoom)
        guard let image = photoContext.createCGImage(source, from: crop) else { return nil }
        return CameraAlignmentFrame(
            generation: alignment.generation, image: UIImage(cgImage: image), size: viewport,
            date: Date(), location: location,
            view: frame.camera.viewMatrix(viewRotationAngle: viewRotationAngle),
            projection: screenProjection(frame))
    }
    func applyAlignment(frame: CameraAlignmentFrame, star: CatalogStar, point: CGPoint) -> Bool {
        guard frame.generation == alignment.generation, abs(frame.date.timeIntervalSinceNow) < 120
        else { return false }
        let sky = AstronomyService.snapshot(date: frame.date, location: frame.location)
        let horizon =
            star.isSun
            ? sky.sunDirection
            : star.isMoon
                ? sky.moonDirection
                : sky.planets.first(where: { $0.star.id == star.id })?.direction
                    ?? sky.direction(ra: star.ra_deg, dec: star.dec_deg)
        guard horizon.z > 0, point.x >= 0, point.y >= 0, point.x <= frame.size.width,
            point.y <= frame.size.height
        else { return false }
        let clip = SIMD4<Float>(
            Float(point.x / frame.size.width * 2 - 1), Float(1 - point.y / frame.size.height * 2), 1, 1)
        let camera = simd_inverse(frame.projection) * clip
        let local = simd_normalize(SIMD3(camera.x, camera.y, camera.z))
        let world = simd_inverse(frame.view) * SIMD4(local.x, local.y, local.z, 0)
        let observed = simd_normalize(SIMD3(world.x, world.y, world.z))
        let expected = SkyFinderProjection.worldDirection(horizon)
        guard simd_dot(expected, observed) > cos(30 * Float.pi / 180) else { return false }
        alignment.save(
            rotation: simd_quatf(from: expected, to: observed), reference: star.title, date: frame.date,
            location: frame.location)
        clearPinnedLight()
        invalidateCameraMatches()
        projection = nil
        return true
    }
    /// Wormhole handover: the current frame oriented and cropped like the screen, plus the camera pose
    /// in the horizon frame. No tracking guards, so it also works for the indoor debug replay.
    func wormholeFreeze() -> WormholeFreeze? {
        guard let frame = session.currentFrame, viewport.width > 0, viewport.height > 0 else { return nil }
        let imageOrientation: CGImagePropertyOrientation = switch orientation {
        case .landscapeRight: .up
        case .landscapeLeft: .down
        case .portraitUpsideDown: .left
        default: .right
        }
        let source = CIImage(cvPixelBuffer:frame.capturedImage).oriented(imageOrientation)
        let crop = CameraZoom.imageCrop(extent:source.extent,viewport:viewport,zoom:cameraZoom)
        let image = photoContext.createCGImage(source,from:crop)
        return WormholeFreeze.make(image:image,size:viewport,view:frame.camera.viewMatrix(viewRotationAngle:viewRotationAngle),
                                   projection:screenProjection(frame),alignment:alignment.rotation)
    }
    #if DEBUG
    /// Demo sky: the camera's forward direction in the sensor world right now.
    func demoForwardWorld() -> SIMD3<Float>? {
        guard let frame = session.currentFrame else { return nil }
        let back = frame.camera.transform.columns.2
        return simd_normalize(-SIMD3(back.x,back.y,back.z))
    }
    /// Demo sky: where a fixed AR-world direction appears on screen (point, or an arrow when off screen).
    func demoProjection(world direction: SIMD3<Float>) -> SkyFinderProjection? {
        guard let frame = session.currentFrame, viewport.width > 0, viewport.height > 0 else { return nil }
        return SkyFinderProjection.project(direction:direction,view:frame.camera.viewMatrix(viewRotationAngle:viewRotationAngle),
                                           projection:screenProjection(frame),size:viewport)
    }
    #endif

    func clearAlignment() { resetTrackingForCalibration() }
    func resetTrackingForCalibration() {
        clearPinnedLight()
        alignment.clear()
        invalidateCameraMatches()
        projection = nil
        sky = nil
        hasStartedSession = false
        if running && hasLocationFix { runSession() }
    }
    func suspendForBackground() {
        alignment.enterBackground()
        stop()
    }
    func restartAfterScreenshot() {
        // Screenshots can lead into the editor or app switcher. Never reuse that map.
        guard running else { return }
        resetTrackingForCalibration()
    }
    var targetMarker: CameraSkyPrediction? {
        guard !alignment.requiresCalibration, status == .tracking, let star, let sky, let projection
        else { return nil }
        let horizon =
            star.isSun
            ? sky.sunDirection
            : star.isMoon
                ? sky.moonDirection
                : sky.planets.first(where: { $0.star.id == star.id })?.direction
                    ?? sky.direction(ra: star.ra_deg, dec: star.dec_deg)
        guard horizon.z > 0 else { return nil }
        return CameraSkyPrediction(direction: alignedDirection(horizon), star: star, guide: projection)
    }
    func captureObservation(annotation: CameraStarAnnotation, identificationNote: String?)
        -> CameraObservationDraft?
    {
        if let ready = retainedCaptureAnnotation, ready.id == annotation.id, let retainedCapture {
            let source = CIImage(cgImage: retainedCapture.image)
            let image = StarCaptureEnhancement.process(source)
            guard let rendered = photoContext.createCGImage(image, from: source.extent) else {
                return nil
            }
            return CameraObservationDraft(
                star: ready.star, image: UIImage(cgImage: rendered),
                date: retainedCapture.date, location: retainedCapture.location,
                identificationNote: (identificationNote ?? "")
                    + " Photo enhanced from the recognized camera frame.")
        }
        guard running, let frame = session.currentFrame, case .normal = frame.camera.trackingState,
            hasLocationFix, viewport.width > 0, viewport.height > 0
        else { return nil }
        guard !alignment.requiresCalibration else { return nil }
        if !annotation.star.isSolarSystemBody {
            let verifiedAnnotation = annotations.contains {
                $0.id == annotation.id && $0.observedAt == annotation.observedAt && $0.sourceDirection != nil
            }
            let verifiedPin = pinnedLight?.observedMatch(at: frame.timestamp)?.star.id == annotation.id
            guard annotation.sourceDirection != nil, annotation.observedAt != nil,
                  verifiedAnnotation || verifiedPin else { return nil }
        }
        if let observedAt = annotation.observedAt,
            frame.timestamp - observedAt < 0 || frame.timestamp - observedAt >= 0.65
        {
            return nil
        }
        let imageOrientation: CGImagePropertyOrientation
        switch orientation {
        case .landscapeRight: imageOrientation = .up
        case .landscapeLeft: imageOrientation = .down
        case .portraitUpsideDown: imageOrientation = .left
        default: imageOrientation = .right
        }
        let source = CIImage(cvPixelBuffer: frame.capturedImage).oriented(imageOrientation)
        let crop = CameraZoom.imageCrop(extent: source.extent, viewport: viewport, zoom: cameraZoom)
        let output = annotation.star.isSolarSystemBody ? source : StarCaptureEnhancement.process(source)
        guard let cgImage = photoContext.createCGImage(output, from: crop) else { return nil }
        // Check this exact frame, but keep UI markers out of the saved photograph.
        if let direction = annotation.sourceDirection {
            let projected = SkyFinderProjection.project(
                direction: direction,
                view: frame.camera.viewMatrix(viewRotationAngle: viewRotationAngle),
                projection: screenProjection(frame), size: viewport)
            guard projected.point != nil else { return nil }
        }
        let photo = UIImage(cgImage: cgImage)
        return CameraObservationDraft(
            star: annotation.star, image: photo, date: Date(), location: location,
            identificationNote: identificationNote)
    }

    func updateViewport(size: CGSize, orientation: UIInterfaceOrientation) {
        if viewport != size || self.orientation != orientation {
            focusSearchRegion = nil
            focusSearchUntil = 0
            discardPendingDetection()
            annotations = []
            unidentifiedLights = []
            opticalTracks = []
            candidateHistory = [:]
            lastDetectionTime = -1
        }
        viewport = size
        self.orientation = orientation
    }

    func start() async {
        guard !AppPreviewData.isRunning else {
            status = .unavailable("Live camera is available on an iPhone.")
            return
        }
        guard !running else { return }
        running = true
        guard SkyCaptureSession.isSupported else {
            status = .unavailable("Sky Camera isn’t supported on this device.")
            return
        }
        status = .requestingPermission
        let authorized: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: authorized = true
        case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
        default: authorized = false
        }
        guard running else { return }
        guard authorized else {
            status = .denied("Allow camera access in Settings to explore the sky.")
            return
        }
        authorizeLocation()
    }

    private func authorizeLocation() {
        guard running else { return }
        guard CLLocationManager.locationServicesEnabled() else {
            status = .denied("Turn on Location Services so we can line up the sky.")
            return
        }
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            if !hasLocationFix { status = .limited("Finding your spot under the sky…") }
            locationManager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                locationManager.headingFilter = kCLHeadingFilterNone
                locationManager.startUpdatingHeading()
            }
            if hasLocationFix { runSession() }
        case .notDetermined: locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            status = .denied("Allow location access in Settings so we can find north.")
        @unknown default: status = .denied("Location access isn’t available yet.")
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard running, AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            alignment.pause(reason: "Location access changed. Restart and align the sky again.")
            hasStartedSession = false
            hasLocationFix = false
            projection = nil
        }
        authorizeLocation()
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard running, let fix = locations.last, fix.horizontalAccuracy >= 0,
            abs(fix.timestamp.timeIntervalSinceNow) < 120
        else { return }
        location = ObserverLocation(
            latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude,
            elevation: fix.altitude, accuracy: fix.horizontalAccuracy)
        if alignment.validateLocation(location) {
            invalidateCameraMatches()
            projection = nil
            hasStartedSession = false
        }
        hasLocationFix = true
        sky = nil
        runSession()
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard running else { return }
        if (error as? CLError)?.code == .locationUnknown { return }
        alignment.pause(reason: "Location tracking stopped. Restart and align the sky again.")
        hasStartedSession = false
        hasLocationFix = false
        projection = nil
        status = .denied("We can’t find your location yet. Check location access or try an open area.")
    }
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { true }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
        cameraHeadingAccuracy =
            heading.trueHeading >= 0 && heading.headingAccuracy >= 0 ? heading.headingAccuracy : nil
    }
    func recalibrateCameraDirection() {
        discardPendingDetection()
        annotations = []
        unidentifiedLights = []
        candidateHistory = [:]
        opticalTracks = []
        lastDetectionTime = -1
        if running && hasLocationFix {
            hasStartedSession = false
            runSession()
        }
    }
    private var viewRotationAngle: CGFloat {
        switch orientation {
        case .landscapeRight: 0
        case .landscapeLeft: 180
        case .portraitUpsideDown: 270
        default: 90
        }
    }
    private func runSession() {
        guard !hasStartedSession else { return }
        hasStartedSession = true
        cameraSettling.reset()
        isAdjustingCamera = false
        lastFrameTime = 0
        automaticMapping = CameraAutomaticMappingProgress()
        frameStartedAt = ProcessInfo.processInfo.systemUptime
        clearPinnedLight()
        session.delegate = self

        alignment.run()
    }

    private func prepareCameraControls() {
        guard !controlsPrepared else { return }
        guard let device = session.captureDevice else { return }
        controlsPrepared = true
        captureDevice = device
        originalExposure = device.exposureTargetBias
        originalFocusMode = device.focusMode
        originalExposureMode = device.exposureMode
        originalFocusPoint = device.focusPointOfInterest
        originalExposurePoint = device.exposurePointOfInterest
        cameraControlMessage = nil
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isLowLightBoostSupported {
                originalLowLightBoost = device.automaticallyEnablesLowLightBoostWhenAvailable
                device.automaticallyEnablesLowLightBoostWhenAvailable = true
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isFocusModeSupported(.locked), device.isLockingFocusWithCustomLensPositionSupported {
                device.setFocusModeLocked(lensPosition: 1, completionHandler: nil)
            }
            if device.isAutoFocusRangeRestrictionSupported {
                originalFocusRange = device.autoFocusRangeRestriction
                device.autoFocusRangeRestriction = .far
            }
        } catch { cameraControlMessage = "The camera’s still getting ready. Try again in a moment." }
        minimumExposure =
            Double(max(-3, device.minExposureTargetBias))
        maximumExposure =
            Double(min(3, device.maxExposureTargetBias))
        exposureBias = Double(device.exposureTargetBias)
        if maximumExposure <= minimumExposure {
            cameraControlMessage = "Brightness controls aren’t available in this camera mode."
        }

    }
    private func invalidateCameraMatches() {
        discardPendingDetection()
        annotations = []
        unidentifiedLights = []
        candidateHistory = [:]
        opticalTracks = []
        detectedLightCount = 0
        lastDetectionTime = -1
        cameraSettling.begin(at: ProcessInfo.processInfo.systemUptime)
        isAdjustingCamera = true
    }
    func setExposure(_ requested: Double) {
        guard let device = captureDevice, maximumExposure > minimumExposure else { return }
        let value = Float(min(maximumExposure, max(minimumExposure, requested)))
        guard abs(Double(value) - exposureBias) >= 0.02 else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.exposureMode == .custom, device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.setExposureTargetBias(
                min(device.maxExposureTargetBias, max(device.minExposureTargetBias, value)),
                completionHandler: nil)
            exposureBias = Double(value)
            cameraControlMessage = nil
            invalidateCameraMatches()
        } catch {
            cameraControlMessage = "We couldn’t change the brightness. Try again. Coba lagi sebentar."
        }
    }
    func dragExposure(translation: CGFloat, ended: Bool) {
        if exposureDragStart == nil {
            exposureDragStart = exposureBias
            setExposureEditing(true)
        }
        if maximumExposure > minimumExposure {
            setExposure(
                CameraExposureGesture.value(
                    start: exposureDragStart ?? exposureBias, translation: Double(translation),
                    viewportHeight: Double(viewport.height), minimum: minimumExposure,
                    maximum: maximumExposure)
            )
        }
        if ended {
            exposureDragStart = nil
            setExposureEditing(false)
        }
    }
    func setZoom(_ requested: Double, animated _: Bool = false) {
        let value = CameraZoom.clamped(requested)
        guard abs(value - cameraZoom) > 0.001 else { return }
        // Apply the crop atomically to the preview and all matching coordinate math.
        cameraZoom = value
        focusSearchRegion = nil
        focusSearchUntil = 0
        invalidateCameraMatches()
        if let frame = session.currentFrame, viewport.width > 0, viewport.height > 0 {
            imageDisplayTransform = screenImageTransform(frame)
        }
    }
    @discardableResult
    func focus(at point: CGPoint, locked: Bool = false) -> Bool {
        guard let device = captureDevice, viewport.width > 0, viewport.height > 0 else { return false }
        let imagePoint = CGPoint(x: point.x / viewport.width, y: point.y / viewport.height).applying(
            imageDisplayTransform.inverted())
        let capturePoint = CGPoint(x: min(1, max(0, imagePoint.x)), y: min(1, max(0, imagePoint.y)))
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if locked {
                if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
                if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
            } else {
                if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .far }
                if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = capturePoint }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = capturePoint
                }
                if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
            }
            focusLocked = locked
            // Convert the visible focus box to the same unrotated coordinates as the detector.
            let region = CGRect(
                x: (point.x - 32) / viewport.width, y: (point.y - 32) / viewport.height,
                width: 64 / viewport.width, height: 64 / viewport.height
            ).applying(imageDisplayTransform.inverted())
            focusSearchRegion = region.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            focusSearchUntil = lastFrameTime + 4
            invalidateCameraMatches()
            return true
        } catch {
            cameraControlMessage = "We couldn’t adjust focus. Try again."
            return false
        }
    }
    func resetCameraControls() {
        _ = focus(at: CGPoint(x: viewport.width / 2, y: viewport.height / 2))
        setExposure(0)
        setZoom(minimumZoom)
    }
    private func restoreCameraControls() {
        if let device = captureDevice {
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if let originalExposure {
                    device.setExposureTargetBias(
                        min(
                            device.maxExposureTargetBias, max(device.minExposureTargetBias, originalExposure)),
                        completionHandler: nil)
                }
                if let originalLowLightBoost, device.isLowLightBoostSupported {
                    device.automaticallyEnablesLowLightBoostWhenAvailable = originalLowLightBoost
                }
                if let originalFocusRange, device.isAutoFocusRangeRestrictionSupported {
                    device.autoFocusRangeRestriction = originalFocusRange
                }
                if let originalFocusPoint, device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = originalFocusPoint
                }
                if let originalExposurePoint, device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = originalExposurePoint
                }
                if let originalFocusMode, device.isFocusModeSupported(originalFocusMode) {
                    device.focusMode = originalFocusMode
                }
                if let originalExposureMode, device.isExposureModeSupported(originalExposureMode) {
                    device.exposureMode = originalExposureMode
                }
            } catch { /* The session may already have released the capture device. */  }
        }
        captureDevice = nil
        originalExposure = nil
        controlsPrepared = false
        exposureDragStart = nil
        exposureHideTask?.cancel()
        exposureHideTask = nil
        exposurePresentation.reset()
        minimumExposure = 0
        maximumExposure = 0
        minimumZoom = 1
        maximumZoom = CameraZoom.maximum
        originalLowLightBoost = nil
        originalFocusMode = nil
        originalExposureMode = nil
        originalFocusRange = nil
        originalFocusPoint = nil
        originalExposurePoint = nil
        focusLocked = false
        exposureBias = 0
        cameraZoom = 1
    }
    func stop() {
        discardPendingDetection()
        viewableObjects = []
        lastOverlayTime = -1
        lastWideScan = -1
        if session.delegate === self {
            restoreCameraControls()
            alignment.pause(
                reason: "The camera stopped. Confirm a reference star to rebuild the sky map.")
            session.delegate = nil
        }
        running = false
        hasStartedSession = false
        exposureHideTask?.cancel()
        exposureHideTask = nil
        exposurePresentation.reset()
        exposureDragStart = nil
        cameraSettling.reset()
        isAdjustingCamera = false
        clearPinnedLight()
        focusSearchRegion = nil
        focusSearchUntil = 0
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        hasLocationFix = false
        projection = nil
        annotations = []
        unidentifiedLights = []
        candidateHistory = [:]
        opticalTracks = []
        detectedLightCount = 0
        cameraHeadingAccuracy = nil
        lastDetectionTime = -1
        previousForward = nil
        status = .preparing
    }
    func session(_ session: SkyCaptureSession, didUpdate frame: SkyCaptureFrame) {
        guard running, hasStartedSession, hasLocationFix, frame.timestamp >= frameStartedAt else {
            return
        }
        if lastFrameTime > 0, frame.timestamp - lastFrameTime > 2.5 {
            resetTrackingForCalibration()
            return
        }
        lastFrameTime = frame.timestamp
        isAdjustingCamera = cameraSettling.isActive(at: ProcessInfo.processInfo.systemUptime)
        if star == nil {
            prepareCameraControls()
            if viewport.width > 0, viewport.height > 0 {
                imageDisplayTransform = screenImageTransform(frame)
            }
        }
        switch frame.camera.trackingState {
        case .normal: if status != .tracking { status = .tracking }
        case .limited(let reason):
            // Hide the guide while tracking is weak, but keep its ray through a brief hiccup.
            discardPendingDetection()
            annotations = []
            unidentifiedLights = []
            candidateHistory = [:]
            opticalTracks = []
            let message: String
            switch reason {
            case .initializing: message = "Waiting for motion sensors…"
            case .insufficientFeatures:
                message = "Waiting for camera orientation…"
            case .excessiveMotion: message = "Hold steady to avoid blurring faint stars."
            case .relocalizing:
                resetTrackingForCalibration()
                return
            @unknown default: message = "Hold your phone steady while orientation recovers."
            }
            status = .limited(message)
            projection = nil
            return
        case .notAvailable:
            discardPendingDetection()
            annotations = []
            unidentifiedLights = []
            candidateHistory = [:]
            opticalTracks = []
            status = .limited("Finding the camera’s direction…")
            projection = nil
            return
        }
        let now = Date()
        if sky == nil || now.timeIntervalSince(lastSnapshot) >= 1 {
            sky = AstronomyService.snapshot(date: now, location: location)
            lastSnapshot = now
            skyDate = now
            if star == nil, let sky {
                // Apparent positions: what the camera sees is lifted by atmospheric refraction.
                scanDirections = catalogue.compactMap { star in
                    let direction = Refraction.apparent(sky.direction(ra: star.ra_deg, dec: star.dec_deg))
                    return direction.z > 0 ? (star, direction) : nil
                }
                scanDirections += sky.planets.filter { $0.direction.z > sin(5 * .pi / 180) }.map {
                    ($0.star, Refraction.apparent($0.direction))
                }
                scanDirections += [
                    (CatalogStar.sun, sky.sunDirection), (CatalogStar.moon, sky.moonDirection),
                ]
                .map { ($0.0, Refraction.apparent($0.1)) }.filter { $0.1.z > 0 }
                refreshVisibility(sky)
            }
        }
        guard let sky, viewport.width > 0, viewport.height > 0 else { return }
        if alignment.requiresCalibration, star != nil || showsPredictions {
            clearPinnedLight()
            discardPendingDetection()
            projection = nil
            annotations = []
            unidentifiedLights = []
            return
        }
        updateReticleGate()
        guard let star else {
            // Keep camera preview native-rate; publish the AR overlay at most 30 times/sec.
            guard lastOverlayTime < 0 || frame.timestamp - lastOverlayTime >= 1.0 / 30 else { return }
            lastOverlayTime = frame.timestamp
            scan(frame: frame, sky: sky)
            retainRecognizedFrame(frame)
            return
        }
        let horizon = Refraction.apparent(
            star.isSun
                ? sky.sunDirection
                : star.isMoon
                    ? sky.moonDirection
                    : sky.planets.first(where: { $0.star.id == star.id })?.direction
                        ?? sky.direction(ra: star.ra_deg, dec: star.dec_deg))
        altitude = asin(min(1, max(-1, horizon.z))) * 180 / .pi
        guard horizon.z > 0 else {
            projection = nil
            return
        }
        projection = SkyFinderProjection.project(
            direction: alignedDirection(horizon),
            view: frame.camera.viewMatrix(viewRotationAngle: viewRotationAngle),
            projection: screenProjection(frame), size: viewport)
    }
    private func scan(frame: SkyCaptureFrame, sky: SkySnapshot) {
        if initialSearchStartedAt == nil { initialSearchStartedAt = frame.timestamp }
        isGatheringInitialLight = frame.timestamp - (initialSearchStartedAt ?? frame.timestamp) < 6
        guard !isAdjustingCamera, !scannerPaused else {
            discardPendingDetection()
            annotations = []
            unidentifiedLights = []
            candidateHistory = [:]
            opticalTracks = []
            detectedLightCount = 0
            return
        }
        let forward4 = frame.camera.transform.columns.2
        let forward = SIMD3(forward4.x, forward4.y, forward4.z)
        // Optical rays are already motion-compensated into this sensor world. Turning
        // the camera must not erase their identities or restart every track.
        previousForward = forward
        let view = frame.camera.viewMatrix(viewRotationAngle: viewRotationAngle)
        let projectionMatrix = screenProjection(frame)
        func projectLight(_ direction: SIMD3<Float>) -> CGPoint? {
            // Projection alone avoids normalizing and computing acos for every catalog dot.
            let local = view * SIMD4(direction.x, direction.y, direction.z, 0)
            guard local.z < 0 else { return nil }
            let clip = projectionMatrix * SIMD4(local.x * 1000, local.y * 1000, local.z * 1000, 1)
            guard clip.w > 0 else { return nil }
            let x = CGFloat(clip.x / clip.w)
            let y = CGFloat(clip.y / clip.w)
            guard abs(x) <= 1, abs(y) <= 1 else { return nil }
            return CGPoint(x: (x + 1) * viewport.width / 2, y: (1 - y) * viewport.height / 2)
        }
        if showsPredictions {
            if alignment.reference != nil || cameraHeadingAccuracy.map({ $0 >= 0 && $0 <= 25 }) == true {
                predictions = viewableObjects.filter { !$0.star.isSolarDisc }.map {
                    CameraSkyPrediction(
                        direction: alignedDirection($0.direction), star: $0.star,
                        guide: SkyFinderProjection.project(
                            direction: alignedDirection($0.direction),
                            view: view, projection: projectionMatrix, size: viewport))
                }
            } else {
                predictions = []
            }
            return
        }
        // The collecting camera only annotates optically detected sources.
        // Catalog directions remain internal inputs to identification, never a visual AR layer.
        let time = frame.timestamp
        // One analysis in flight; never queue camera frames or block the main actor on pixels.
        if detectionTask == nil, lastDetectionTime < 0 || time - lastDetectionTime >= 0.12 {
            lastDetectionTime = time
            let buffer = CameraAnalysisBuffer(value: frame.capturedImage)
            let zoom = cameraZoom
            if focusSearchRegion != nil, time > focusSearchUntil {
                focusSearchRegion = nil
                pointStack.reset()
            }
            let focusRegion = time <= focusSearchUntil ? focusSearchRegion : nil
            let generation = detectionGeneration
            let transform = screenImageTransform(frame)
            let size = viewport
            let intrinsics = frame.camera.intrinsics
            let pose = frame.camera.transform
            let aimAltitude = asin(min(1, max(-1, Double(-pose.columns.2.y)))) * 180 / .pi
            let stackEnabled = CameraPointStack.isEligible(
                sunAltitude: sky.sunAltitude, aimAltitude: aimAltitude)
            let previousStack = pointStack
            let previousPinnedStack = pinnedPointStack
            // Convert the reticle's neighborhood back into native, unrotated image pixels.
            let focusedPoint = focusRegion.map { CGPoint(x: $0.midX, y: $0.midY).applying(transform) }
            let scanPoint =
                focusedPoint.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
                ?? CGPoint(x: size.width / 2, y: size.height / 2)
            let centerRegion = CGRect(
                x: (scanPoint.x - 48) / size.width, y: (scanPoint.y - 48) / size.height,
                width: 96 / size.width, height: 96 / size.height
            ).applying(transform.inverted())
            let broadScanInterval = alignment.requiresCalibration ? 0.25 : 0.7
            let broadScan = lastWideScan < 0 || time - lastWideScan >= broadScanInterval
            if broadScan { lastWideScan = time }
            let pinnedRegion = pinnedLightGuide?.point.flatMap { point -> CGRect? in
                guard hypot(point.x - scanPoint.x, point.y - scanPoint.y) > 48 else { return nil }
                return CGRect(
                    x: (point.x - 48) / size.width, y: (point.y - 48) / size.height,
                    width: 96 / size.width, height: 96 / size.height
                ).applying(transform.inverted())
            }
            detectionTask = Task { @MainActor [weak self] in
                let result = await Task.detached(priority: .userInitiated) {
                    var stack = previousStack
                    var pinnedStack = previousPinnedStack
                    // Inspect the aimed-at light first; background context runs less often.
                    var sources = CameraStarDetector.detect(
                        in: buffer.value, zoom: zoom, focusRegion: focusRegion ?? centerRegion)
                    if broadScan {
                        sources +=
                            CameraStarDetector.detectDiscs(in: buffer.value)
                            + CameraStarDetector.detect(in: buffer.value, zoom: zoom)
                    }
                    if stackEnabled {
                        sources += stack.detect(
                            in: buffer.value, intrinsics: intrinsics, pose: pose, time: time,
                            region: centerRegion
                        )
                        if let pinnedRegion {
                            sources += pinnedStack.detect(
                                in: buffer.value, intrinsics: intrinsics, pose: pose, time: time,
                                region: pinnedRegion)
                        } else {
                            pinnedStack.reset()
                        }
                    } else {
                        stack.reset()
                        pinnedStack.reset()
                    }
                    sources = sources.filter {
                        CameraSkyContext.permits($0.point, in: buffer.value, isDisc: $0.isDisc)
                    }
                    return (sources, stack, pinnedStack)
                }.value
                guard let self else { return }
                self.detectionTask = nil
                guard self.running, !self.scannerPaused, generation == self.detectionGeneration else {
                    return
                }
                self.pointStack = result.1
                self.pointScanProgress = result.1.progress
                self.pinnedPointStack = result.2
                self.pendingDetection = (result.0, time, transform, view, projectionMatrix, size)
            }
        }
        let result = pendingDetection
        pendingDetection = nil
        let didDetect = result.map { time - $0.time >= 0 && time - $0.time < 0.8 } ?? false
        if didDetect, let result {
            // Unproject with the analyzed frame's pose, then project into the current frame.
            // Using the new pose to interpret old pixels would make markers drift when panning.
            let inverseProjection = simd_inverse(result.projection)
            let inverseView = simd_inverse(result.view)
            let lights = result.sources.compactMap { light -> (CGPoint, CGSize, Bool, SIMD3<Float>)? in
                let normalized = light.point.applying(result.transform)
                guard normalized.x > 0, normalized.x < 1, normalized.y > 0, normalized.y < 1 else {
                    return nil
                }
                let clip = SIMD4<Float>(Float(normalized.x * 2 - 1), Float(1 - normalized.y * 2), 1, 1)
                let camera = inverseProjection * clip
                let local = simd_normalize(SIMD3(camera.x, camera.y, camera.z))
                let world = inverseView * SIMD4(local.x, local.y, local.z, 0)
                let ray = simd_normalize(SIMD3(world.x, world.y, world.z))
                guard let point = projectLight(ray) else { return nil }
                let bounds = light.bounds.applying(result.transform)
                return (
                    point,
                    CGSize(
                        width: max(5, min(14, abs(bounds.width) * result.size.width + 3)),
                        height: max(5, min(14, abs(bounds.height) * result.size.height + 3))), light.isDisc,
                    ray
                )
            }
            detectedLightCount = lights.count
            var tracks: [CameraOpticalTrack] = []
            var usedTracks: Set<Int> = []
            for light in lights {
                // Several peaks can belong to the same blurred source, especially at high zoom.
                guard
                    !tracks.contains(where: { track in
                        guard let point = projectLight(track.direction) else { return false }
                        return hypot(point.x - light.0.x, point.y - light.0.y) < 16
                    })
                else { continue }
                var previous = opticalTracks.filter { !usedTracks.contains($0.id) && time - $0.time < 0.9 }
                    .compactMap { track -> (CameraOpticalTrack, Double)? in
                        guard let point = projectLight(track.direction) else { return nil }
                        return (track, hypot(point.x - light.0.x, point.y - light.0.y))
                    }.filter { $0.1 < min(22, max(12, 10 * sqrt(cameraZoom))) }.min { $0.1 < $1.1 }?.0
                if previous == nil, lights.count == 1 {
                    let recent = opticalTracks.filter {
                        !usedTracks.contains($0.id) && $0.hits >= 2 && time - $0.time <= 0.25
                    }
                    if recent.count == 1, let same = recent.first,
                        CameraTargetSelection.continuesSingleSource(
                            previousPoint: same.screenPoint, point: light.0, gap: time - same.time)
                    {
                        previous = same
                    }
                }
                if let old = previous, time - old.time > 0.35 { previous = nil }
                let id: Int
                if let previous {
                    id = previous.id
                    usedTracks.insert(id)
                } else {
                    nextOpticalID += 1
                    id = nextOpticalID
                }
                tracks.append(
                    CameraOpticalTrack(
                        id: id, hits: (previous?.hits ?? 0) + 1, direction: light.3, size: light.1,
                        time: time,
                        isDisc: light.2, screenPoint: light.0, firstSeen: previous?.firstSeen ?? time))
            }
            // A faint source may disappear for one analysis pass as exposure/noise changes.
            // Retain its track briefly instead of restarting confirmation from zero.
            tracks += opticalTracks.filter { !usedTracks.contains($0.id) && time - $0.time < 0.9 }
            opticalTracks = tracks
        }
        if alignment.requiresCalibration {
            automaticMapping.update(
                at: time,
                lightCount: opticalTracks.filter {
                    time - $0.time < 0.65 && $0.hits >= 2 && !$0.isDisc
                        && $0.direction.y > sin(8 * Float.pi / 180)
                        && $0.direction.y < sin(83 * Float.pi / 180)
                }.count)
            if let match = pinnedLight?.match, retainedCapture?.annotation.id != match.star.id {
                clearPinnedLight(clearCapture: false)
            }
            // Recovery still detects real light, but never supplies a guessed catalog identity.
            annotations = []
            predictions = []
            unidentifiedLights = []
            trackMatches = [:]
            trackIssues = [:]
            candidateHistory = [:]
            if didDetect {
                let fresh = opticalTracks.filter {
                    $0.time == time && $0.hits >= 2 && !$0.isDisc && $0.direction.y > 0
                }
                let centered = fresh.compactMap { track -> (CameraOpticalTrack, Double)? in
                    guard let point = projectLight(track.direction) else { return nil }
                    let distance = hypot(point.x - viewport.width / 2, point.y - viewport.height / 2)
                    return distance <= 28 ? (track, distance) : nil
                }.min { $0.1 < $1.1 }?.0
                if let centered {
                    if pinnedLight?.isSameSource(centered.direction) == true {
                        pinnedLight?.observe(
                            direction: centered.direction, time: centered.time, opticalID: centered.id)
                    } else {
                        pinnedLight = CameraLightPin(
                            direction: centered.direction, time: centered.time,
                            observations: centered.hits, opticalID: centered.id)
                    }
                } else if let returning = fresh.first(where: {
                    pinnedLight?.isSameSource($0.direction) == true
                }) {
                    pinnedLight?.observe(
                        direction: returning.direction, time: returning.time, opticalID: returning.id)
                }
                // A remembered direction is not a newly detected source in this recovery flow.
                if let pin = pinnedLight, time - pin.lastSeen >= 2 {
                    clearPinnedLight(clearCapture: false)
                }
                attemptAutomaticMapping(at: time, project: projectLight)
            }
            return
        }
        let angularCandidates =
            didDetect
            ? scanDirections.filter { $0.0.mag <= 6.5 }.map { ($0.0, alignedDirection($0.1)) } : []
        if didDetect {
            trackMatches = [:]
            trackIssues = [:]
        }
        var visible: [CameraStarAnnotation] = []
        var unknown: [CameraLightAnnotation] = []
        var nextHistory: [Int: (starID: Int, hits: Int)] = [:]
        for track in opticalTracks.sorted(by: { $0.hits == $1.hits ? $0.id < $1.id : $0.hits > $1.hits }
        ) where time - track.time < 0.65 {
            guard let point = projectLight(track.direction), point.y < viewport.height - 90 else {
                continue
            }
            var match: CameraCandidateMatch?
            var issue = trackIssues[track.id] ?? .stabilizing
            if didDetect {
                // A manual reference supplies direction independently of the compass accuracy report.
                let assessment = assessCameraCandidate(
                    direction: track.direction, isDisc: track.isDisc,
                    candidates: angularCandidates, hasOpticalEvidence: track.hits >= 2)
                match = assessment.match
                issue = assessment.issue
                trackMatches[track.id] = match
                trackIssues[track.id] = issue
            } else {
                match = trackMatches[track.id]
            }
            let previous = candidateHistory[track.id]
            if let match {
                let observedThisPass = didDetect && track.time == time
                let hits =
                    observedThisPass
                    ? (previous?.starID == match.star.id ? (previous?.hits ?? 0) + 1 : 1)
                    : (previous?.starID == match.star.id ? previous?.hits ?? 0 : 0)
                nextHistory[track.id] = (match.star.id, hits)
                if CameraIdentityPolicy.hasPersistentEvidence(
                    hits: track.hits, firstSeen: track.firstSeen, lastSeen: track.time),
                    hits >= 3, visible.count < 8,
                    !visible.contains(where: {
                        $0.star.id == match.star.id || hypot($0.point.x - point.x, $0.point.y - point.y) < 90
                    }),
                    !unknown.contains(where: { hypot($0.point.x - point.x, $0.point.y - point.y) < 90 })
                {
                    visible.append(
                        CameraStarAnnotation(
                            star: match.star, point: point, size: track.size,
                            estimatedSeparation: match.separation, sourceDirection: track.direction,
                            observedAt: track.time))
                    continue
                }
            }
            if track.hits >= 2, unknown.count < 8,
                !visible.contains(where: { hypot($0.point.x - point.x, $0.point.y - point.y) < 90 }),
                !unknown.contains(where: { hypot($0.point.x - point.x, $0.point.y - point.y) < 90 })
            {
                unknown.append(
                    CameraLightAnnotation(id: track.id, point: point, size: track.size, issue: issue))
            }
        }
        candidateHistory = nextHistory
        annotations = visible
        unidentifiedLights = unknown
        updatePinnedLight(at: time, didDetect: didDetect, sky: sky, project: projectLight)
    }

    private struct RetainedStarCapture {
        let generation: Int
        let annotation: CameraStarAnnotation
        let image: CGImage
        let contrast: Double
        let date: Date
        let location: ObserverLocation
    }
    private func retainRecognizedFrame(_ frame: SkyCaptureFrame) {
        guard status == .tracking, !isAdjustingCamera, !scannerPaused,
            let pin = pinnedLight, let match = pin.observedMatch(at: frame.timestamp),
            !match.star.isSolarSystemBody,
            retainedCapture?.annotation.id != match.star.id || lastCaptureCacheTime < 0
                || frame.timestamp - lastCaptureCacheTime >= 0.25,
            viewport.width > 0, viewport.height > 0,
            let point = SkyFinderProjection.project(
                direction: pin.direction,
                view: frame.camera.viewMatrix(viewRotationAngle: viewRotationAngle),
                projection: screenProjection(frame), size: viewport
            ).point
        else { return }
        let annotation = CameraStarAnnotation(
            star: match.star, point: point, size: CGSize(width: 18, height: 18),
            estimatedSeparation: match.separation, sourceDirection: pin.direction, observedAt: pin.lastSeen)
        lastCaptureCacheTime = frame.timestamp
        let normalized = CGPoint(
            x: annotation.point.x / viewport.width, y: annotation.point.y / viewport.height
        )
        .applying(imageDisplayTransform.inverted())
        let contrast = StarCaptureEnhancement.contrast(in: frame.capturedImage, at: normalized)
        if let previous = retainedCapture, previous.generation == alignment.generation,
            previous.annotation.id == annotation.id, previous.contrast >= contrast
        {
            pinnedLight?.identify(using: match)
            return
        }
        let rotation: CGImagePropertyOrientation =
            switch orientation {
            case .landscapeRight: .up
            case .landscapeLeft: .down
            case .portraitUpsideDown: .left
            default: .right
            }
        let source = CIImage(cvPixelBuffer: frame.capturedImage).oriented(rotation)
        let crop = CameraZoom.imageCrop(extent: source.extent, viewport: viewport, zoom: cameraZoom)
        guard let image = photoContext.createCGImage(source, from: crop) else { return }
        retainedCapture = RetainedStarCapture(
            generation: alignment.generation, annotation: annotation,
            image: image, contrast: contrast, date: Date(), location: location)
        pinnedLight?.identify(using: match)
    }

    private func attemptAutomaticMapping(
        at time: TimeInterval,
        project: (SIMD3<Float>) -> CGPoint?
    ) {
        guard automaticMappingTask == nil, lastMappingAttempt < 0 || time - lastMappingAttempt >= 0.25
        else { return }
        let tracks = opticalTracks.filter { time - $0.time < 0.65 && $0.hits >= 2 && !$0.isDisc }
        guard tracks.count >= SkyPatternMatcher.minimumAutomaticPatternStars,
            let anchor = tracks.filter({ track in
                guard let point = project(track.direction) else { return false }
                return hypot(point.x - viewport.width / 2, point.y - viewport.height / 2) <= 28
            }).min(by: {
                simd_dot($0.direction, pinnedLight?.direction ?? $0.direction)
                    > simd_dot($1.direction, pinnedLight?.direction ?? $1.direction)
            })
        else {
            _ = mappingConsensus.add(nil, at: time)
            return
        }
        let observations = tracks.sorted { $0.id == anchor.id && $1.id != anchor.id }.map {
            CalibrationObservation(id: $0.id, direction: $0.direction)
        }
        let candidates = scanDirections.filter { !$0.0.isSolarSystemBody && $0.0.mag <= 5.5 }.map {
            star, d in
            CalibrationCatalogPoint(
                id: star.id, direction: SIMD3(Float(d.x), Float(d.z), Float(-d.y)), magnitude: star.mag)
        }
        let token = detectionGeneration
        let world = alignment.generation
        let prior = SkyCalibration.arHeadingOffset
        lastMappingAttempt = time
        automaticMappingTask = Task { @MainActor [weak self] in
            let solution = await Task.detached(priority: .userInitiated) {
                SkyPatternMatcher.solve(
                    observations: observations, catalogue: candidates, anchorID: anchor.id, priorOffset: prior
                )
            }.value
            guard let self, !Task.isCancelled, self.running,
                token == self.detectionGeneration, world == self.alignment.generation
            else { return }
            self.automaticMappingTask = nil
            guard self.status == .tracking, self.lastFrameTime - time < 0.65 else {
                self.mappingConsensus.reset()
                return
            }
            let progress = self.mappingConsensus.add(solution, at: time)
            guard progress >= 1, let solution,
                let star = self.catalogue.first(where: { $0.id == solution.anchorStarID })
            else { return }
            self.alignment.save(
                rotation: simd_quatf(angle: Float(solution.headingOffset - prior), axis: SIMD3(0, 1, 0)),
                reference: "Automatic star pattern", date: Date(), location: self.location)
            self.discardPendingDetection()
            self.opticalTracks = []
            self.annotations = []
            self.unidentifiedLights = []
            self.clearPinnedLight()
            var pin = CameraLightPin(direction: anchor.direction, time: time, observations: anchor.hits)
            pin.identify(
                using: CameraCandidateMatch(star: star, separation: solution.residualDegrees, score: 0))
            self.pinnedLight = pin
        }
    }

    // MARK: Last observed light (independent of the reticle)

    private func assessCameraCandidate(
        direction: SIMD3<Float>, isDisc: Bool,
        candidates: [(CatalogStar, SIMD3<Float>)], hasOpticalEvidence: Bool
    ) -> CameraCandidateAssessment {
        CameraIdentityPolicy.assess(direction: direction, isDisc: isDisc, zoom: cameraZoom,
            hasReferenceAlignment: hasReferenceAlignment, candidates: candidates,
            hasOpticalEvidence: hasOpticalEvidence)
    }

    private func updatePinnedLight(
        at time: TimeInterval, didDetect: Bool, sky: SkySnapshot,
        project: (SIMD3<Float>) -> CGPoint?
    ) {
        var observation: CameraOpticalTrack?
        let focusedPoint =
            time <= focusSearchUntil
            ? focusSearchRegion.map {
                CGPoint(x: $0.midX, y: $0.midY).applying(imageDisplayTransform)
            } : nil
        let center =
            focusedPoint.map { CGPoint(x: $0.x * viewport.width, y: $0.y * viewport.height) }
            ?? CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        if didDetect, sky.sunAltitude < -6 {
            let fresh = opticalTracks.filter { $0.time == time && $0.hits >= 2 && $0.direction.y > 0 }
            // Continue an existing source anywhere in the frame. A different light replaces
            // it only when the user aims near that new source.
            let returning = fresh.filter {
                pinnedLight?.canReacquire(
                    $0.direction, identifiedAs: identifiedMatch(for: $0, at: time), opticalID: $0.id)
                    == true
            }.sorted {
                guard let pin = pinnedLight else { return false }
                return simd_dot(pin.direction, $0.direction) > simd_dot(pin.direction, $1.direction)
            }
            // Prefer the closest optical source, not the first track in detector order.
            // Two competing lights must resolve before either can drag a saved pin.
            let uniqueReturn =
                returning.count < 2
                || simd_dot(returning[0].direction, returning[1].direction) > cos(0.15 * Float.pi / 180)
            if uniqueReturn, let same = returning.first {
                pinnedLight?.observe(
                    direction: same.direction, time: time, identifiedAs: identifiedMatch(for: same, at: time),
                    opticalID: same.id)
                observation = same
            }
            let nearest = fresh.compactMap { track -> (CameraOpticalTrack, Double)? in
                guard let point = project(track.direction) else { return nil }
                let distance = hypot(point.x - center.x, point.y - center.y)
                return distance <= 64 ? (track, distance) : nil
            }.min { $0.1 < $1.1 }?.0
            newLightIssue = nearest.flatMap {
                pinnedLight?.isSameSource($0.direction) == true ? nil : trackIssues[$0.id] ?? .stabilizing
            }
            isScanningNewLight = newLightIssue == .stabilizing
            if let nearest, pinnedLight?.isSameSource(nearest.direction) != true {
                let identified = identifiedMatch(for: nearest, at: time)
                // A deliberate aim at a different observed light starts a new scan.
                // Its old photo stays cached independently of the active optical pin.
                let nextPoint = project(nearest.direction) ?? CGPoint(x: -1000, y: -1000)
                let startsNew = CameraTargetSelection.beginsNewSource(
                    previousPoint: pinnedLight.flatMap { project($0.direction) }, newPoint: nextPoint,
                    center: center, observations: nearest.hits)
                if startsNew
                    || (pinnedLight?.canBeReplaced(by: nearest.direction, identifiedAs: identified) ?? true)
                {
                    pinnedLight = CameraLightPin(
                        direction: nearest.direction, time: time, observations: nearest.hits,
                        opticalID: nearest.id)
                    if let identified { pinnedLight?.identify(using: identified) }
                    pinnedPointStack.reset()
                    lastPinAssessment = -1
                    observation = nearest
                    newLightIssue = nil
                    isScanningNewLight = false
                }
            }
        }
        guard var pin = pinnedLight,
            observation != nil || lastPinAssessment < 0 || time - lastPinAssessment >= 0.2
        else { return }
        lastPinAssessment = time
        let candidates = scanDirections.filter { !$0.0.isSolarDisc && $0.0.mag <= 6.5 }
            .map { ($0.0, alignedDirection($0.1)) }
        let assessment = assessCameraCandidate(
            direction: pin.direction, isDisc: false,
            candidates: candidates, hasOpticalEvidence: pin.observationCount >= 2)
        pin.assess(assessment)
        if let observation, let identified = identifiedMatch(for: observation, at: time) {
            pin.identify(using: identified)
        }
        let point = project(pin.direction)
        let inReticle =
            point.map { hypot($0.x - viewport.width / 2, $0.y - viewport.height / 2) <= 28 } ?? false
        let persistent = observation.map {
            CameraIdentityPolicy.hasPersistentEvidence(hits: $0.hits, firstSeen: $0.firstSeen, lastSeen: $0.time)
        } ?? false
        pin.confirm(assessment, observedAt: persistent ? observation?.time : nil, insideReticle: inReticle)
        pinnedLight = pin
        updateReticleGate()
    }

    private func identifiedMatch(for track: CameraOpticalTrack, at time: TimeInterval)
        -> CameraCandidateMatch?
    {
        guard track.time == time, let match = trackMatches[track.id],
            annotations.contains(where: { annotation in
                annotation.id == match.star.id && annotation.observedAt == time
                    && annotation.sourceDirection.map {
                        simd_dot($0, track.direction) > cos(0.3 * Float.pi / 180)
                    } == true
            })
        else { return nil }
        return match
    }

    func session(_ session: SkyCaptureSession, didFailWithError error: Error) {
        clearPinnedLight()
        alignment.invalidate(reason: "Camera tracking stopped. Restart and calibrate the sky again.")
        discardPendingDetection()
        projection = nil
        annotations = []
        unidentifiedLights = []
        candidateHistory = [:]
        opticalTracks = []
        hasStartedSession = false
        status = .unavailable("The camera stopped: \(error.localizedDescription)")
    }
    func sessionWasInterrupted(_ session: SkyCaptureSession) {
        clearPinnedLight()
        alignment.invalidate(
            reason:
                "Camera tracking was interrupted. Align a known object again before using sky positions.")
        discardPendingDetection()
        projection = nil
        annotations = []
        unidentifiedLights = []
        candidateHistory = [:]
        opticalTracks = []
        status = .limited("Camera paused. Come back to the app to keep looking.")
    }

    func sessionInterruptionEnded(_ session: SkyCaptureSession) {
        hasStartedSession = false
        if running { authorizeLocation() }
    }
}
