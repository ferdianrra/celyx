import ARKit
import CoreImage
import AVFoundation
import CoreLocation
import Observation
import simd

@MainActor @Observable
final class SkyFinderService: NSObject, ARSessionDelegate, CLLocationManagerDelegate {
    enum Status: Equatable {
        case preparing, requestingPermission, tracking, limited(String), unavailable(String), denied(String)
    }
    private(set) var status: Status = .preparing
    private(set) var projection: SkyFinderProjection?
    private(set) var altitude: Double?
    let alignment: CameraSkyAlignment
    var session: ARSession { alignment.session }
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
    @ObservationIgnored private var detectionTask: Task<Void,Never>?
    @ObservationIgnored private var pendingDetection: (sources:[CameraLightPoint],time:TimeInterval,
        transform:CGAffineTransform,view:simd_float4x4,projection:simd_float4x4,size:CGSize)?
    @ObservationIgnored private var trackMatches: [Int:CameraCandidateMatch] = [:]
    @ObservationIgnored private var trackIssues: [Int:CameraIdentificationIssue] = [:]
    @ObservationIgnored private var confirmedNames: [Int:(match:CameraCandidateMatch,supportedAt:TimeInterval)] = [:]

    func updateVisibility(quality: SkyQuality,atmosphere: Atmosphere,filters: VisibilityFilters = .init()) {
        guard visibilityFilters != filters || visibilityQuality != quality || visibilityAtmosphere != atmosphere || sky == nil else { return }
        visibilityFilters = filters
        visibilityQuality = quality; visibilityAtmosphere = atmosphere
        sky = nil
    }
    private func refreshVisibility(_ sky: SkySnapshot) {
        viewableObjects = VisibilityEstimator.visibleObjects(stars:catalogue,sky:sky,quality:visibilityQuality,atmosphere:visibilityAtmosphere,filters:visibilityFilters)
        // Solar discs need their own daytime/phase rules, rather than the star darkness limit.
        for (star,direction) in scanDirections where star.isSolarDisc && direction.z > 0 {
            let clear = !visibilityFilters.clouds || (visibilityAtmosphere.cloudCover ?? 0) < 75
            let moonLit = sky.moonIllumination > 0.05 && sky.sunAltitude < -6
            if clear && (star.isSun || moonLit) {
                viewableObjects.append(StarObservation(star:star,direction:direction,
                    dimmedMagnitude:star.mag,likelyVisible:true,reason:"Above the horizon"))
            }
        }
        viewableObjects.sort { $0.dimmedMagnitude == $1.dimmedMagnitude ? $0.id < $1.id : $0.dimmedMagnitude < $1.dimmedMagnitude }
        likelyVisibleIDs = Set(viewableObjects.map(\.id))
    }
    private func discardPendingDetection() {
        predictions = []
        detectionGeneration += 1; pendingDetection = nil; trackMatches = [:]; trackIssues = [:]; confirmedNames = [:]
    }

    /// Catalog positions for the center reticle, separate from optical detection evidence.
    /// Collect still requires a matching camera observation before saving an object.
    var mappedObjects: [CameraMappedObject] {
        guard status == .tracking, !alignment.requiresCalibration,
              viewport.width > 0, viewport.height > 0, let frame = session.currentFrame else { return [] }
        let view = frame.camera.viewMatrix(viewRotationAngle:viewRotationAngle)
        let projection = screenProjection(frame)
        return scanDirections.compactMap { star,direction in
            let guide = SkyFinderProjection.project(direction:alignedDirection(direction),
                view:view,projection:projection,size:viewport)
            guard let point = guide.point else { return nil }
            return CameraMappedObject(star:star,point:point,likelyVisible:likelyVisibleIDs.contains(star.id))
        }
    }

    /// Bright bodies (Sun, Moon, planets) that are up right now, with the angle in degrees between each
    /// one's real direction (GPS + clock) and where the camera is pointing. Uses the angle rather than a
    /// screen point so a few degrees of compass error doesn't stop you aiming at a big, obvious disc.
    func brightBodiesNearAim() -> [(star: CatalogStar, separation: Double)] {
        guard status == .tracking, let back = previousForward else { return [] }
        let aim = simd_normalize(-back)
        return scanDirections.compactMap { star, direction in
            guard star.isSolarSystemBody else { return nil }
            let world = simd_normalize(SkyFinderProjection.worldDirection(direction))
            let separation = Double(acos(min(1,max(-1,simd_dot(aim,world))))) * 180 / .pi
            return (star,separation)
        }
    }

    func aimTarget(pinnedID: Int? = nil) -> CameraAimTarget? {
        guard !alignment.requiresCalibration, status == .tracking, !isAdjustingCamera, !scannerPaused else { return nil }
        let center = CGPoint(x:viewport.width/2,y:viewport.height/2)
        // The observed light takes precedence over its compass-derived catalog position.
        let objects = annotations.map { CameraMappedObject(star:$0.star,point:$0.point,likelyVisible:likelyVisibleIDs.contains($0.id)) }
        let object: CameraMappedObject?
        if let pinnedID {
            object = objects.first(where:{ $0.id == pinnedID })
        } else {
            let nearby = objects.filter { hypot($0.point.x-center.x,$0.point.y-center.y) <= min(viewport.width,viewport.height)*0.35 }
            let observed = nearby.filter { object in annotations.contains(where:{ $0.id == object.id }) }
            object = (observed.isEmpty ? nearby : observed)
                .min { hypot($0.point.x-center.x,$0.point.y-center.y) < hypot($1.point.x-center.x,$1.point.y-center.y) }
        }
        guard let object else { return nil }
        return CameraAimTarget(object:object,detection:annotations.first(where:{ $0.id == object.id }))
    }
    private(set) var unidentifiedLights: [CameraLightAnnotation] = []
    private(set) var detectedLightCount = 0
    private(set) var cameraHeadingAccuracy: Double?
    private var opticalTracks: [CameraOpticalTrack] = []
    private var nextOpticalID = 0
    private(set) var skyDate: Date?
    var scannerPaused = false
    var observerLocation: ObserverLocation? { hasLocationFix ? location : nil }
    private var candidateHistory: [Int:(starID:Int,hits:Int)] = [:]
    private var lastDetectionTime: TimeInterval = -1
    private var previousForward: SIMD3<Float>?
    private var scanDirections: [(CatalogStar,SIMD3<Double>)] = []
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
    private var controlsSettleUntil: TimeInterval = 0
    private var location: ObserverLocation
    private var hasLocationFix = false
    private var viewport = CGSize.zero
    private var orientation: UIInterfaceOrientation = .portrait
    private var running = false
    private var hasStartedSession = false
    var isCameraRunning: Bool { hasStartedSession }
    var isAdjustingCamera: Bool { lastFrameTime < controlsSettleUntil }
    private var sky: SkySnapshot?
    /// Sun altitude (degrees) at the current GPS position and time, or nil before the first fix.
    var sunAltitude: Double? { sky?.sunAltitude }
    private var lastSnapshot = Date.distantPast
    private let photoContext = CIContext(options:[.cacheIntermediates:false])

    init(star: CatalogStar? = nil, location: ObserverLocation? = nil, catalogue: [CatalogStar] = [],showsPredictions: Bool = false,alignment: CameraSkyAlignment? = nil) {
        self.alignment = alignment ?? CameraSkyAlignment()
        self.showsPredictions = showsPredictions
        self.star = star; self.catalogue = catalogue.sorted { $0.mag < $1.mag }
        self.location = location ?? ObserverLocation(latitude:0,longitude:0)
        super.init()
        locationManager.delegate = self
    }

    private func screenProjection(_ frame: ARFrame) -> simd_float4x4 {
        CameraZoom.projection(frame.camera.projectionMatrix(viewRotationAngle:viewRotationAngle,
            viewportSize:viewport,zNear:0.01,zFar:2000),zoom:cameraZoom)
    }
    private func screenImageTransform(_ frame: ARFrame) -> CGAffineTransform {
        frame.displayTransform(viewRotationAngle:viewRotationAngle,viewportSize:viewport)
            .concatenating(CameraZoom.normalizedTransform(cameraZoom))
    }
    private func alignedDirection(_ horizon: SIMD3<Double>) -> SIMD3<Float> {
        alignment.correct(SkyFinderProjection.worldDirection(horizon))
    }
    func captureAlignmentFrame() -> CameraAlignmentFrame? {
        guard running, status == .tracking, hasLocationFix, !isAdjustingCamera,
              let frame = session.currentFrame, viewport.width > 0, viewport.height > 0 else { return nil }
        let orientation: CGImagePropertyOrientation = switch self.orientation {
        case .landscapeRight: .up
        case .landscapeLeft: .down
        case .portraitUpsideDown: .left
        default: .right
        }
        let source = CIImage(cvPixelBuffer:frame.capturedImage).oriented(orientation)
        let crop = CameraZoom.imageCrop(extent:source.extent,viewport:viewport,zoom:cameraZoom)
        guard let image = photoContext.createCGImage(source,from:crop) else { return nil }
        return CameraAlignmentFrame(generation:alignment.generation,image:UIImage(cgImage:image),size:viewport,date:Date(),location:location,
            view:frame.camera.viewMatrix(viewRotationAngle:viewRotationAngle),
            projection:screenProjection(frame))
    }
    func applyAlignment(frame: CameraAlignmentFrame,star: CatalogStar,point: CGPoint) -> Bool {
        guard frame.generation == alignment.generation, abs(frame.date.timeIntervalSinceNow) < 120 else { return false }
        let sky = AstronomyService.snapshot(date:frame.date,location:frame.location)
        let horizon = star.isSun ? sky.sunDirection : star.isMoon ? sky.moonDirection : sky.planets.first(where:{ $0.star.id == star.id })?.direction ?? sky.direction(ra:star.ra_deg,dec:star.dec_deg)
        guard horizon.z > 0, point.x >= 0, point.y >= 0, point.x <= frame.size.width, point.y <= frame.size.height else { return false }
        let clip = SIMD4<Float>(Float(point.x/frame.size.width*2-1),Float(1-point.y/frame.size.height*2),1,1)
        let camera = simd_inverse(frame.projection)*clip
        let local = simd_normalize(SIMD3(camera.x,camera.y,camera.z))
        let world = simd_inverse(frame.view)*SIMD4(local.x,local.y,local.z,0)
        let observed = simd_normalize(SIMD3(world.x,world.y,world.z))
        let expected = SkyFinderProjection.worldDirection(horizon)
        guard simd_dot(expected,observed) > cos(30 * Float.pi/180) else { return false }
        alignment.save(rotation:simd_quatf(from:expected,to:observed),reference:star.title,date:frame.date,location:frame.location)
        invalidateCameraMatches(); projection = nil
        return true
    }
    func clearAlignment() { resetTrackingForCalibration() }
    func resetTrackingForCalibration() {
        alignment.clear()
        invalidateCameraMatches(); projection = nil; sky = nil
        hasStartedSession = false
        if running && hasLocationFix { runSession() }
    }
    func suspendForBackground() {
        alignment.enterBackground()
        stop()
    }
    var targetMarker: CameraSkyPrediction? {
        guard !alignment.requiresCalibration, status == .tracking, let star, let sky, let projection else { return nil }
        let horizon = star.isSun ? sky.sunDirection : star.isMoon ? sky.moonDirection
            : sky.planets.first(where:{ $0.star.id == star.id })?.direction ?? sky.direction(ra:star.ra_deg,dec:star.dec_deg)
        guard horizon.z > 0 else { return nil }
        return CameraSkyPrediction(direction:alignedDirection(horizon),star:star,guide:projection)
    }
    func captureObservation(annotation: CameraStarAnnotation,identificationNote: String?) -> CameraObservationDraft? {
        guard !alignment.requiresCalibration, running, let frame = session.currentFrame, case .normal = frame.camera.trackingState,
              hasLocationFix, viewport.width > 0, viewport.height > 0 else { return nil }
        let imageOrientation: CGImagePropertyOrientation
        switch orientation {
        case .landscapeRight: imageOrientation = .up
        case .landscapeLeft: imageOrientation = .down
        case .portraitUpsideDown: imageOrientation = .left
        default: imageOrientation = .right
        }
        let source = CIImage(cvPixelBuffer:frame.capturedImage).oriented(imageOrientation)
        let crop = CameraZoom.imageCrop(extent:source.extent,viewport:viewport,zoom:cameraZoom)
        guard let cgImage = photoContext.createCGImage(source,from:crop) else { return nil }
        // Reproject the observed light into this exact frame, rather than circling the
        // name label (which sits below it) or using a later frame from the detail sheet.
        let point: CGPoint
        if let direction = annotation.sourceDirection {
            let projected = SkyFinderProjection.project(direction:direction,
                view:frame.camera.viewMatrix(viewRotationAngle:viewRotationAngle),
                projection:screenProjection(frame),size:viewport)
            guard let projectedPoint = projected.point else { return nil }
            point = projectedPoint
        } else { point = annotation.point }
        let photo = UIImage(cgImage:cgImage)
        let pixelScale = photo.size.width/viewport.width
        let center = CGPoint(x:point.x*pixelScale,y:point.y*photo.size.height/viewport.height)
        let radius = max(12,max(annotation.size.width,annotation.size.height)/2+6)*pixelScale
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true
        let markedPhoto = UIGraphicsImageRenderer(size:photo.size,format:format).image { renderer in
            photo.draw(at:.zero)
            let ring = UIBezierPath(ovalIn:CGRect(x:center.x-radius,y:center.y-radius,width:radius*2,height:radius*2))
            renderer.cgContext.setShadow(offset:.zero,blur:2*pixelScale,color:UIColor.black.cgColor)
            UIColor.black.withAlphaComponent(0.65).setStroke()
            ring.lineWidth = 3.5*pixelScale; ring.stroke()
            UIColor(red:1,green:0.86,blue:0.35,alpha:1).setStroke()
            ring.lineWidth = 1.5*pixelScale; ring.stroke()
        }
        return CameraObservationDraft(star:annotation.star,image:markedPhoto,date:Date(),location:location,identificationNote:identificationNote)
    }

    func updateViewport(size: CGSize, orientation: UIInterfaceOrientation) {
        if viewport != size || self.orientation != orientation {
            focusSearchRegion = nil; focusSearchUntil = 0
            discardPendingDetection()
            annotations = []; unidentifiedLights = []; opticalTracks = []
            candidateHistory = [:]; lastDetectionTime = -1
        }
        viewport = size; self.orientation = orientation
    }

    func start() async {
        guard !AppPreviewData.isRunning else { status = .unavailable("Live camera is available on an iPhone."); return }
        guard !running else { return }; running = true
        guard AROrientationTrackingConfiguration.isSupported else {
            status = .unavailable("Sky Camera isn’t supported on this device.")
            return
        }
        status = .requestingPermission
        let authorized: Bool
        switch AVCaptureDevice.authorizationStatus(for:.video) {
        case .authorized: authorized = true
        case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for:.video)
        default: authorized = false
        }
        guard running else { return }
        guard authorized else { status = .denied("Allow camera access in Settings to explore the sky."); return }
        authorizeLocation()
    }

    private func authorizeLocation() {
        guard running else { return }
        guard CLLocationManager.locationServicesEnabled() else {
            status = .denied("Turn on Location Services so we can line up the sky."); return
        }
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            if !hasLocationFix { status = .limited("Finding your spot under the sky…") }
            locationManager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() { locationManager.headingFilter = kCLHeadingFilterNone; locationManager.startUpdatingHeading() }
            if hasLocationFix { runSession() }
        case .notDetermined: locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted: status = .denied("Allow location access in Settings so we can find north.")
        @unknown default: status = .denied("Location access isn’t available yet.")
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard running, AVCaptureDevice.authorizationStatus(for:.video) == .authorized else { return }
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            session.pause(); hasStartedSession = false; hasLocationFix = false; projection = nil
        }
        authorizeLocation()
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard running, let fix = locations.last, fix.horizontalAccuracy >= 0,
              abs(fix.timestamp.timeIntervalSinceNow) < 120 else { return }
        location = ObserverLocation(latitude:fix.coordinate.latitude,longitude:fix.coordinate.longitude,
            elevation:fix.altitude,accuracy:fix.horizontalAccuracy)
        if alignment.validateLocation(location) {
            invalidateCameraMatches(); projection = nil; hasStartedSession = false
        }
        hasLocationFix = true; sky = nil
        runSession()
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard running else { return }
        if (error as? CLError)?.code == .locationUnknown { return }
        session.pause(); hasStartedSession = false; hasLocationFix = false
        projection = nil
        status = .denied("We can’t find your location yet. Check location access or try an open area.")
    }
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { true }
    func locationManager(_ manager: CLLocationManager,didUpdateHeading heading: CLHeading) {
        cameraHeadingAccuracy = heading.trueHeading >= 0 && heading.headingAccuracy >= 0 ? heading.headingAccuracy : nil
    }
    func recalibrateCameraDirection() {
        discardPendingDetection()
        annotations = []; unidentifiedLights = []; candidateHistory = [:]; opticalTracks = []
        lastDetectionTime = -1
        if running && hasLocationFix { hasStartedSession = false; runSession() }
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
        session.delegate = self; session.delegateQueue = .main
        let configuration: ARConfiguration
        let formats: [ARConfiguration.VideoFormat]
        if ARWorldTrackingConfiguration.isSupported {
            configuration = ARWorldTrackingConfiguration()
            formats = ARWorldTrackingConfiguration.supportedVideoFormats
        } else {
            configuration = AROrientationTrackingConfiguration()
            formats = AROrientationTrackingConfiguration.supportedVideoFormats
        }
        configuration.worldAlignment = .gravityAndHeading
        // Collect prioritizes low-light capture; AR scene rendering remains native-rate.
        let preferredFPS = star == nil && !showsPredictions ? 30 : 60
        if let wide = formats.first(where:{ $0.captureDeviceType == .builtInWideAngleCamera && $0.framesPerSecond == preferredFPS })
            ?? formats.first(where:{ $0.captureDeviceType == .builtInWideAngleCamera }) {
            configuration.videoFormat = wide
        }
        status = .preparing
        // Share one tracked world frame across camera screens and alignment captures.
        alignment.run(configuration)
    }
    private func prepareCameraControls() {
        guard !controlsPrepared else { return }
        let camera = ARWorldTrackingConfiguration.isSupported
            ? ARWorldTrackingConfiguration.configurableCaptureDeviceForPrimaryCamera
            : AROrientationTrackingConfiguration.configurableCaptureDeviceForPrimaryCamera
        guard let device = camera else {
            cameraControlMessage = "Focus and exposure controls aren’t available in this camera mode. Zoom still works."
            return
        }
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
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isAutoFocusRangeRestrictionSupported {
                originalFocusRange = device.autoFocusRangeRestriction
                device.autoFocusRangeRestriction = .far
            }
        } catch { cameraControlMessage = "The camera’s still getting ready. Try again in a moment." }
        minimumExposure = device.exposureMode == .custom ? 0 : Double(max(-3,device.minExposureTargetBias))
        maximumExposure = device.exposureMode == .custom ? 0 : Double(min(3,device.maxExposureTargetBias))
        exposureBias = Double(device.exposureTargetBias)
        if maximumExposure <= minimumExposure { cameraControlMessage = "Brightness controls aren’t available in this camera mode." }
    }
    private func invalidateCameraMatches() {
        discardPendingDetection()
        annotations = []; unidentifiedLights = []; candidateHistory = [:]; opticalTracks = []; detectedLightCount = 0; lastDetectionTime = -1
        controlsSettleUntil = lastFrameTime+0.8
    }
    func setExposure(_ requested: Double) {
        guard let device = captureDevice, maximumExposure > minimumExposure else { return }
        let value = Float(min(maximumExposure,max(minimumExposure,requested)))
        guard abs(Double(value)-exposureBias) >= 0.02 else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.setExposureTargetBias(min(device.maxExposureTargetBias,max(device.minExposureTargetBias,value)),completionHandler:nil)
            exposureBias = Double(value)
            cameraControlMessage = nil
            invalidateCameraMatches()
        } catch { cameraControlMessage = "We couldn’t change the brightness. Try again. Coba lagi sebentar." }
    }
    func setZoom(_ requested: Double, animated _: Bool = false) {
        let value = CameraZoom.clamped(requested)
        guard abs(value-cameraZoom) > 0.001 else { return }
        // Apply the crop atomically to the preview and all matching coordinate math.
        cameraZoom = value
        focusSearchRegion = nil; focusSearchUntil = 0
        invalidateCameraMatches()
        if let frame = session.currentFrame, viewport.width > 0, viewport.height > 0 {
            imageDisplayTransform = screenImageTransform(frame)
        }
    }
    @discardableResult
    func focus(at point: CGPoint, locked: Bool = false) -> Bool {
        guard let device = captureDevice, viewport.width > 0, viewport.height > 0 else { return false }
        let imagePoint = CGPoint(x:point.x/viewport.width,y:point.y/viewport.height).applying(imageDisplayTransform.inverted())
        let capturePoint = CGPoint(x:min(1,max(0,imagePoint.x)),y:min(1,max(0,imagePoint.y)))
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if locked {
                if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
                if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
            } else {
                if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .far }
                if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = capturePoint }
                if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = capturePoint }
                if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            }
            focusLocked = locked
            // Convert the visible focus box to the same unrotated coordinates as the detector.
            let region = CGRect(x:(point.x-32)/viewport.width,y:(point.y-32)/viewport.height,
                width:64/viewport.width,height:64/viewport.height).applying(imageDisplayTransform.inverted())
            focusSearchRegion = region.intersection(CGRect(x:0,y:0,width:1,height:1))
            focusSearchUntil = lastFrameTime+4
            invalidateCameraMatches()
            return true
        } catch { cameraControlMessage = "We couldn’t adjust focus. Try again."; return false }
    }
    func resetCameraControls() {
        _ = focus(at:CGPoint(x:viewport.width/2,y:viewport.height/2))
        setExposure(0)
        setZoom(minimumZoom)
    }
    private func restoreCameraControls() {
        if let device = captureDevice {
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if let originalExposure {
                    device.setExposureTargetBias(min(device.maxExposureTargetBias,max(device.minExposureTargetBias,originalExposure)),completionHandler:nil)
                }
                if let originalLowLightBoost, device.isLowLightBoostSupported { device.automaticallyEnablesLowLightBoostWhenAvailable = originalLowLightBoost }
                if let originalFocusRange, device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = originalFocusRange }
                if let originalFocusPoint, device.isFocusPointOfInterestSupported { device.focusPointOfInterest = originalFocusPoint }
                if let originalExposurePoint, device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = originalExposurePoint }
                if let originalFocusMode, device.isFocusModeSupported(originalFocusMode) { device.focusMode = originalFocusMode }
                if let originalExposureMode, device.isExposureModeSupported(originalExposureMode) { device.exposureMode = originalExposureMode }
            } catch { /* The session may already have released the capture device. */ }
        }
        captureDevice = nil; originalExposure = nil; controlsPrepared = false
        minimumExposure = 0; maximumExposure = 0; minimumZoom = 1; maximumZoom = CameraZoom.maximum
        originalLowLightBoost = nil; originalFocusMode = nil; originalExposureMode = nil
        originalFocusRange = nil; originalFocusPoint = nil; originalExposurePoint = nil; focusLocked = false
        exposureBias = 0; cameraZoom = 1
    }
    func stop() {
        discardPendingDetection()
        viewableObjects = []
        lastOverlayTime = -1
        if session.delegate === self { restoreCameraControls(); session.pause() }
        running = false; hasStartedSession = false
        focusSearchRegion = nil; focusSearchUntil = 0
        locationManager.stopUpdatingLocation(); locationManager.stopUpdatingHeading(); hasLocationFix = false
        projection = nil; annotations = []; unidentifiedLights = []; candidateHistory = [:]; opticalTracks = []; detectedLightCount = 0
        cameraHeadingAccuracy = nil; lastDetectionTime = -1; previousForward = nil
        status = .preparing
    }
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard running, hasStartedSession, hasLocationFix else { return }
        lastFrameTime = frame.timestamp
        if star == nil {
            prepareCameraControls()
            if viewport.width > 0, viewport.height > 0 {
                imageDisplayTransform = screenImageTransform(frame)
            }
        }
        switch frame.camera.trackingState {
        case .normal: if status != .tracking { status = .tracking }
        case .limited(let reason):
            discardPendingDetection(); annotations = []; unidentifiedLights = []; candidateHistory = [:]; opticalTracks = []
            let message: String
            switch reason {
            case .initializing: message = "Move your phone slowly while AR maps your surroundings."
            case .insufficientFeatures: message = "Point briefly at a textured wall or nearby objects to help AR track."
            case .excessiveMotion: message = "Move your phone more slowly so AR can keep its position."
            case .relocalizing:
                if !alignment.requiresCalibration { alignment.invalidate(reason:"AR lost its previous reference. Reset tracking and align a known object again.") }
                message = "AR lost its previous reference. Reset and calibrate the sky again."
            @unknown default: message = "Hold your phone steady while AR restores tracking."
            }
            status = .limited(message); projection = nil; return
        case .notAvailable: discardPendingDetection(); annotations = []; unidentifiedLights = []; candidateHistory = [:]; opticalTracks = []; status = .limited("Finding the camera’s direction…"); projection = nil; return
        }
        let now = Date()
        if sky == nil || now.timeIntervalSince(lastSnapshot) >= 1 {
            sky = AstronomyService.snapshot(date:now,location:location); lastSnapshot = now; skyDate = now
            if star == nil, let sky {
                // Apparent positions: what the camera sees is lifted by atmospheric refraction.
                scanDirections = catalogue.compactMap { star in
                    let direction = Refraction.apparent(sky.direction(ra:star.ra_deg,dec:star.dec_deg))
                    return direction.z > 0 ? (star,direction) : nil
                }
                scanDirections += sky.planets.filter { $0.direction.z > sin(5 * .pi/180) }.map { ($0.star,Refraction.apparent($0.direction)) }
                scanDirections += [(CatalogStar.sun,sky.sunDirection),(CatalogStar.moon,sky.moonDirection)]
                    .map { ($0.0,Refraction.apparent($0.1)) }.filter { $0.1.z > 0 }
                refreshVisibility(sky)
            }
        }
        guard let sky, viewport.width > 0, viewport.height > 0 else { return }
        guard !alignment.requiresCalibration else {
            discardPendingDetection(); projection = nil; annotations = []; unidentifiedLights = []
            return
        }
        guard let star else {
            // Keep camera preview native-rate; publish the AR overlay at most 30 times/sec.
            guard lastOverlayTime < 0 || frame.timestamp-lastOverlayTime >= 1.0/30 else { return }
            lastOverlayTime = frame.timestamp
            scan(frame:frame,sky:sky)
            return
        }
        let horizon = Refraction.apparent(star.isSun ? sky.sunDirection : star.isMoon ? sky.moonDirection : sky.planets.first(where: { $0.star.id == star.id })?.direction ?? sky.direction(ra:star.ra_deg,dec:star.dec_deg))
        altitude = asin(min(1,max(-1,horizon.z))) * 180 / .pi
        guard horizon.z > 0 else { projection = nil; return }
        projection = SkyFinderProjection.project(direction:alignedDirection(horizon),
            view:frame.camera.viewMatrix(viewRotationAngle:viewRotationAngle),
            projection:screenProjection(frame),size:viewport)
    }
    private func scan(frame: ARFrame, sky: SkySnapshot) {
        guard frame.timestamp >= controlsSettleUntil, !scannerPaused else { discardPendingDetection(); annotations = []; unidentifiedLights = []; candidateHistory = [:]; opticalTracks = []; detectedLightCount = 0; return }
        let forward4 = frame.camera.transform.columns.2
        let forward = SIMD3(forward4.x,forward4.y,forward4.z)
        if let previousForward, simd_dot(forward,previousForward) < cos(1.5 * .pi/180) {
            discardPendingDetection()
            candidateHistory = [:]; annotations = []; opticalTracks = []; unidentifiedLights = []
        }
        previousForward = forward
        let view = frame.camera.viewMatrix(viewRotationAngle:viewRotationAngle)
        let projectionMatrix = screenProjection(frame)
        func projectLight(_ direction: SIMD3<Float>) -> CGPoint? {
            // Projection alone avoids normalizing and computing acos for every catalog dot.
            let local = view*SIMD4(direction.x,direction.y,direction.z,0)
            guard local.z < 0 else { return nil }
            let clip = projectionMatrix*SIMD4(local.x*1000,local.y*1000,local.z*1000,1)
            guard clip.w > 0 else { return nil }
            let x = CGFloat(clip.x/clip.w), y = CGFloat(clip.y/clip.w)
            guard abs(x) <= 1, abs(y) <= 1 else { return nil }
            return CGPoint(x:(x+1)*viewport.width/2,y:(1-y)*viewport.height/2)
        }
        if showsPredictions {
            if alignment.reference != nil || cameraHeadingAccuracy.map({ $0 >= 0 && $0 <= 25 }) == true {
                predictions = viewableObjects.filter { !$0.star.isSolarDisc }.map {
                    CameraSkyPrediction(direction:alignedDirection($0.direction),star:$0.star,guide:SkyFinderProjection.project(direction:alignedDirection($0.direction),
                        view:view,projection:projectionMatrix,size:viewport))
                }
            } else { predictions = [] }
            return
        }
        // The collecting camera only annotates optically detected sources.
        // Catalog directions remain internal inputs to identification, never a visual AR layer.
        let time = frame.timestamp
        // One analysis in flight; never queue camera frames or block the main actor on pixels.
        if detectionTask == nil, lastDetectionTime < 0 || time-lastDetectionTime >= 0.18 {
            lastDetectionTime = time
            let buffer = CameraAnalysisBuffer(value:frame.capturedImage), zoom = cameraZoom
            let focusRegion = time <= focusSearchUntil ? focusSearchRegion : nil
            let generation = detectionGeneration
            let transform = screenImageTransform(frame)
            let size = viewport
            detectionTask = Task { @MainActor [weak self] in
                let sources = await Task.detached(priority:.userInitiated) {
                    CameraStarDetector.detectDiscs(in:buffer.value) + CameraStarDetector.detect(in:buffer.value,zoom:zoom,focusRegion:focusRegion)
                }.value
                guard let self else { return }
                self.detectionTask = nil
                guard self.running, !self.scannerPaused, generation == self.detectionGeneration else { return }
                self.pendingDetection = (sources,time,transform,view,projectionMatrix,size)
            }
        }
        let result = pendingDetection
        pendingDetection = nil
        let didDetect = result.map { time-$0.time >= 0 && time-$0.time < 0.8 } ?? false
        if didDetect, let result {
            // Unproject with the analyzed frame's pose, then project into the current frame.
            // Using the new pose to interpret old pixels would make markers drift when panning.
            let inverseProjection = simd_inverse(result.projection), inverseView = simd_inverse(result.view)
            let lights = result.sources.compactMap { light -> (CGPoint,CGSize,Bool,SIMD3<Float>)? in
                let normalized = light.point.applying(result.transform)
                guard normalized.x > 0, normalized.x < 1, normalized.y > 0, normalized.y < 1 else { return nil }
                let clip = SIMD4<Float>(Float(normalized.x*2-1),Float(1-normalized.y*2),1,1)
                let camera = inverseProjection*clip
                let local = simd_normalize(SIMD3(camera.x,camera.y,camera.z))
                let world = inverseView*SIMD4(local.x,local.y,local.z,0)
                let ray = simd_normalize(SIMD3(world.x,world.y,world.z))
                guard let point = projectLight(ray) else { return nil }
                let bounds = light.bounds.applying(result.transform)
                return (point,CGSize(width:max(5,min(14,abs(bounds.width)*result.size.width+3)),
                    height:max(5,min(14,abs(bounds.height)*result.size.height+3))),light.isDisc,ray)
            }
            detectedLightCount = lights.count
            var tracks: [CameraOpticalTrack] = []
            var usedTracks: Set<Int> = []
            for light in lights {
                // Several peaks can belong to the same blurred source, especially at high zoom.
                guard !tracks.contains(where: { track in
                    guard let point = projectLight(track.direction) else { return false }
                    return hypot(point.x-light.0.x,point.y-light.0.y) < 16
                }) else { continue }
                let previous = opticalTracks.filter { !usedTracks.contains($0.id) && time-$0.time < 0.9 }.compactMap { track -> (CameraOpticalTrack,Double)? in
                    guard let point = projectLight(track.direction) else { return nil }
                    return (track,hypot(point.x-light.0.x,point.y-light.0.y))
                }.filter { $0.1 < min(22,max(12,10*sqrt(cameraZoom))) }.min { $0.1 < $1.1 }?.0
                let id: Int
                if let previous { id = previous.id; usedTracks.insert(id) }
                else { nextOpticalID += 1; id = nextOpticalID }
                tracks.append(CameraOpticalTrack(id:id,hits:(previous?.hits ?? 0)+1,direction:light.3,size:light.1,time:time,isDisc:light.2))
            }
            // A faint source may disappear for one analysis pass as exposure/noise changes.
            // Retain its track briefly instead of restarting confirmation from zero.
            tracks += opticalTracks.filter { !usedTracks.contains($0.id) && time-$0.time < 0.9 }
            opticalTracks = tracks
        }
        let angularCandidates = didDetect ? scanDirections.filter { $0.0.mag <= 5.5 }.map { ($0.0,alignedDirection($0.1)) } : []
        if didDetect { trackMatches = [:]; trackIssues = [:] }
        let activeIDs = Set(opticalTracks.map(\.id))
        confirmedNames = confirmedNames.filter { activeIDs.contains($0.key) && time-$0.value.supportedAt < 0.9 }
        var visible: [CameraStarAnnotation] = []
        var unknown: [CameraLightAnnotation] = []
        var nextHistory: [Int:(starID:Int,hits:Int)] = [:]
        for track in opticalTracks.sorted(by: { $0.hits == $1.hits ? $0.id < $1.id : $0.hits > $1.hits }) where time-track.time < 0.65 {
            guard let point = projectLight(track.direction), point.y < viewport.height-90 else { continue }
            var match: CameraCandidateMatch?
            var issue = trackIssues[track.id] ?? .stabilizing
            if didDetect {
                // A manual reference supplies direction independently of the compass accuracy report.
                let heading = alignment.reference == nil ? cameraHeadingAccuracy : nil
                let assessment = CameraCandidateMatcher.assess(direction:track.direction,isDisc:track.isDisc,
                    zoom:cameraZoom,headingAccuracy:heading,candidates:angularCandidates,
                    maximumSeparation:alignment.reference == nil ? nil : 3)
                match = assessment.match; issue = assessment.issue
                if match == nil, alignment.reference != nil, case .noCandidate = issue {
                    // Broader suggestions need more optical observations, a bright candidate and
                    // a clear lead. This is not permission to pick any star on the sky.
                    let wider = CameraCandidateMatcher.assess(direction:track.direction,isDisc:track.isDisc,
                        zoom:cameraZoom,headingAccuracy:nil,
                        candidates:angularCandidates.filter { $0.0.mag <= CameraCandidateMatcher.preferredMagnitudeLimit(zoom:cameraZoom) },
                        maximumSeparation:6,minimumScoreGap:1.5)
                    if wider.match != nil { issue = .alignment }
                    if track.hits >= 6, let candidate = wider.match { match = candidate }
                    else if wider.match == nil, case .ambiguous = wider.issue { issue = .ambiguous }
                }
                // Keep an already established identity across a brief ambiguous reading, only
                // while the same light is still observed close to that object's direction.
                if match == nil, let established = confirmedNames[track.id], time-established.supportedAt < 0.9,
                   (alignment.reference != nil || (cameraHeadingAccuracy.map { $0 >= 0 && $0 <= 25 } ?? false)),
                   let expected = angularCandidates.first(where:{ $0.0.id == established.match.star.id }) {
                    let separation = Double(acos(min(1,max(-1,simd_dot(track.direction,expected.1)))))*180 / .pi
                    let allowed = alignment.reference == nil ? min(12,max(6,(cameraHeadingAccuracy ?? 10)*0.75)) : 6
                    if separation <= allowed {
                        match = CameraCandidateMatch(star:established.match.star,separation:separation,score:established.match.score)
                    }
                }
                trackMatches[track.id] = match; trackIssues[track.id] = issue
                if let match, assessment.match?.star.id == match.star.id || (track.hits >= 6 && issue == .alignment) {
                    // Refresh support only on a genuine new observation, never cached frames.
                    if track.time == time, candidateHistory[track.id]?.starID == match.star.id,
                       (candidateHistory[track.id]?.hits ?? 0) >= 2 {
                        confirmedNames[track.id] = (match,time)
                    }
                }
            } else { match = trackMatches[track.id] }
            let previous = candidateHistory[track.id]
            if let match {
                let observedThisPass = didDetect && track.time == time
                let hits = observedThisPass ? (previous?.starID == match.star.id ? (previous?.hits ?? 0)+1 : 1) : (previous?.starID == match.star.id ? previous?.hits ?? 0 : 0)
                nextHistory[track.id] = (match.star.id,hits)
                if track.hits >= 3, hits >= 2, visible.count < 8,
                   !visible.contains(where: { $0.star.id == match.star.id || hypot($0.point.x-point.x,$0.point.y-point.y) < 90 }),
                   !unknown.contains(where: { hypot($0.point.x-point.x,$0.point.y-point.y) < 90 }) {
                    visible.append(CameraStarAnnotation(star:match.star,point:point,size:track.size,
                        estimatedSeparation:match.separation,sourceDirection:track.direction))
                    continue
                }
            }
            if track.hits >= 2, unknown.count < 8,
               !visible.contains(where: { hypot($0.point.x-point.x,$0.point.y-point.y) < 90 }),
               !unknown.contains(where: { hypot($0.point.x-point.x,$0.point.y-point.y) < 90 }) {
                unknown.append(CameraLightAnnotation(id:track.id,point:point,size:track.size,issue:issue))
            }
        }
        candidateHistory = nextHistory
        annotations = visible
        unidentifiedLights = unknown
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        alignment.invalidate(reason:"Camera tracking stopped. Restart and calibrate the sky again.")
        discardPendingDetection()
        projection = nil; annotations = []; unidentifiedLights = []; candidateHistory = [:]; opticalTracks = []; hasStartedSession = false
        status = .unavailable("The camera stopped: \(error.localizedDescription)")
    }
    func sessionWasInterrupted(_ session: ARSession) {
        alignment.invalidate(reason:"Camera tracking was interrupted. Align a known object again before using sky positions.")
        discardPendingDetection()
        projection = nil; annotations = []; unidentifiedLights = []; candidateHistory = [:]; opticalTracks = []; status = .limited("Camera paused. Come back to the app to keep looking.")
    }
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool { false }
    func sessionInterruptionEnded(_ session: ARSession) {
        hasStartedSession = false
        if running { authorizeLocation() }
    }
}


/// Corrections belong to one live AR world frame, never to a later app session.
@MainActor @Observable
final class CameraSkyAlignment {
    let session = ARSession()
    private(set) var reference: String?
    private(set) var date: Date?
    private(set) var location: ObserverLocation?
    private(set) var calibrationReason: String?
    var requiresCalibration: Bool { calibrationReason != nil }
    private(set) var generation = 0
    private(set) var rotation = simd_quatf(angle:0,axis:SIMD3<Float>(0,1,0))
    @ObservationIgnored private var configured = false
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // A quaternion alone cannot restore the AR world that produced it.
        if defaults.data(forKey:"cameraSkyAlignment.v1") != nil || defaults.bool(forKey:"cameraSkyAlignment.usedBefore") {
            calibrationReason = "The previous camera session ended. Align a known object again before using sky positions."
        }
        defaults.removeObject(forKey:"cameraSkyAlignment.v1")
    }
    func run(_ configuration: ARConfiguration) {
        session.run(configuration,options:configured ? [] : [.resetTracking,.removeExistingAnchors])
        configured = true
    }
    func correct(_ direction: SIMD3<Float>) -> SIMD3<Float> { rotation.act(direction) }
    func save(rotation: simd_quatf,reference: String,date: Date,location: ObserverLocation? = nil) {
        self.rotation = simd_normalize(rotation); self.reference = reference; self.date = date
        self.location = location; calibrationReason = nil
        defaults.set(true,forKey:"cameraSkyAlignment.usedBefore")
    }
    func enterBackground() {
        guard configured || reference != nil else { return }
        invalidate(reason:"The app left the foreground. Align a known object again because the phone may have moved.")
    }
    func invalidate(reason: String) {
        generation += 1; configured = false
        rotation = simd_quatf(angle:0,axis:SIMD3<Float>(0,1,0))
        reference = nil; date = nil; location = nil
        calibrationReason = reason
        defaults.removeObject(forKey:"cameraSkyAlignment.v1")
    }
    @discardableResult func validateLocation(_ current: ObserverLocation) -> Bool {
        guard let location else { return false }
        let distance = CLLocation(latitude:location.latitude,longitude:location.longitude)
            .distance(from:CLLocation(latitude:current.latitude,longitude:current.longitude))
        // Account for uncertainty so an ordinary GPS update does not demand calibration.
        guard distance > max(150,location.accuracy+current.accuracy) else { return false }
        invalidate(reason:"Your location changed. Align the sky again from this spot.")
        return true
    }
    func clear() { invalidate(reason:"Alignment was reset. Mark a known object to calibrate the sky again.") }
}

struct CameraAlignmentFrame {
    let generation: Int
    let image: UIImage
    let size: CGSize
    let date: Date
    let location: ObserverLocation
    let view: simd_float4x4
    let projection: simd_float4x4
}
