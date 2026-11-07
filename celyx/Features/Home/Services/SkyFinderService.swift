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
    let session = ARSession()
    private let locationManager = CLLocationManager()
    private let star: CatalogStar?
    private let catalogue: [CatalogStar]
    private(set) var annotations: [CameraStarAnnotation] = []
    private(set) var mappedObjects: [CameraMappedObject] = []
    private(set) var viewableObjects: [StarObservation] = []
    private(set) var visibilityLimit: Double = 0
    private var visibilityQuality: SkyQuality = .city
    private var visibilityAtmosphere = Atmosphere()
    @ObservationIgnored private var likelyVisibleIDs: Set<Int> = []
    @ObservationIgnored private var lastOverlayTime: TimeInterval = -1
    @ObservationIgnored private var detectionGeneration = 0
    @ObservationIgnored private var detectionTask: Task<Void,Never>?
    @ObservationIgnored private var pendingDetection: (sources:[CameraLightPoint],time:TimeInterval,
        transform:CGAffineTransform,view:simd_float4x4,projection:simd_float4x4,size:CGSize)?
    @ObservationIgnored private var trackMatches: [Int:CameraCandidateMatch] = [:]

    func updateVisibility(quality: SkyQuality,atmosphere: Atmosphere) {
        guard visibilityQuality != quality || visibilityAtmosphere != atmosphere || sky == nil else { return }
        visibilityQuality = quality; visibilityAtmosphere = atmosphere
        sky = nil
    }
    private func refreshVisibility(_ sky: SkySnapshot) {
        let moonAltitude = asin(min(1,max(-1,sky.moonDirection.z)))*180 / .pi
        visibilityLimit = VisibilityEstimator.limitingMagnitude(sunAltitude:sky.sunAltitude,
            quality:visibilityQuality,moonAltitude:moonAltitude,moonIllumination:sky.moonIllumination)
        viewableObjects = scanDirections.map { star,direction in
            VisibilityEstimator.observation(star:star,direction:direction,limit:visibilityLimit,
                sunAltitude:sky.sunAltitude,atmosphere:visibilityAtmosphere)
        }.filter { !$0.star.isSolarDisc && $0.likelyVisible }
        // Solar discs need their own daytime/phase rules, rather than the star darkness limit.
        for (star,direction) in scanDirections where star.isSolarDisc && direction.z > 0 {
            let clear = (visibilityAtmosphere.cloudCover ?? 0) < 75
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
        detectionGeneration += 1; pendingDetection = nil; trackMatches = [:]
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
        guard status == .tracking, !isAdjustingCamera, !scannerPaused else { return nil }
        let center = CGPoint(x:viewport.width/2,y:viewport.height/2)
        // The observed light takes precedence over its compass-derived catalog position.
        let objects = annotations.map { CameraMappedObject(star:$0.star,point:$0.point,likelyVisible:likelyVisibleIDs.contains($0.id)) }
            + mappedObjects.filter { object in !annotations.contains(where:{ $0.id == object.id }) }
        let object: CameraMappedObject?
        if let pinnedID {
            object = objects.first(where:{ $0.id == pinnedID })
        } else {
            let nearby = objects.filter { hypot($0.point.x-center.x,$0.point.y-center.y) <= 36 }
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
    private(set) var maximumZoom: Double = 1
    private(set) var cameraControlMessage: String?
    private var captureDevice: AVCaptureDevice?
    private var originalExposure: Float?
    private var originalZoom: CGFloat?
    private var zoomBase: CGFloat = 1
    private var originalLowLightBoost: Bool?
    private var originalFocusMode: AVCaptureDevice.FocusMode?
    private var originalExposureMode: AVCaptureDevice.ExposureMode?
    private var originalFocusRange: AVCaptureDevice.AutoFocusRangeRestriction?
    private var originalFocusPoint: CGPoint?
    private var originalExposurePoint: CGPoint?
    private var imageDisplayTransform = CGAffineTransform.identity
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
    var isAdjustingCamera: Bool { lastFrameTime < controlsSettleUntil || captureDevice?.isRampingVideoZoom == true }
    private var sky: SkySnapshot?
    /// Sun altitude (degrees) at the current GPS position and time, or nil before the first fix.
    var sunAltitude: Double? { sky?.sunAltitude }
    private var lastSnapshot = Date.distantPast
    private let photoContext = CIContext(options:[.cacheIntermediates:false])

    init(star: CatalogStar? = nil, location: ObserverLocation? = nil, catalogue: [CatalogStar] = []) {
        self.star = star; self.catalogue = catalogue.sorted { $0.mag < $1.mag }
        self.location = location ?? ObserverLocation(latitude:0,longitude:0)
        super.init()
        session.delegate = self; session.delegateQueue = .main
        locationManager.delegate = self
    }

    func captureObservation(annotation: CameraStarAnnotation,identificationNote: String?) -> CameraObservationDraft? {
        guard running, let frame = session.currentFrame, case .normal = frame.camera.trackingState,
              hasLocationFix, viewport.width > 0, viewport.height > 0 else { return nil }
        let imageOrientation: CGImagePropertyOrientation
        switch orientation {
        case .landscapeRight: imageOrientation = .up
        case .landscapeLeft: imageOrientation = .down
        case .portraitUpsideDown: imageOrientation = .left
        default: imageOrientation = .right
        }
        let source = CIImage(cvPixelBuffer:frame.capturedImage).oriented(imageOrientation)
        let aspect = viewport.width/viewport.height
        let extent = source.extent
        let width = min(extent.width,extent.height*aspect)
        let height = width/aspect
        let crop = CGRect(x:extent.midX-width/2,y:extent.midY-height/2,width:width,height:height)
        guard let cgImage = photoContext.createCGImage(source,from:crop) else { return nil }
        // Reproject the observed light into this exact frame, rather than circling the
        // name label (which sits below it) or using a later frame from the detail sheet.
        let point: CGPoint
        if let direction = annotation.sourceDirection {
            let projected = SkyFinderProjection.project(direction:direction,
                view:frame.camera.viewMatrix(viewRotationAngle:viewRotationAngle),
                projection:frame.camera.projectionMatrix(viewRotationAngle:viewRotationAngle,viewportSize:viewport,zNear:0.01,zFar:2000),size:viewport)
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
            discardPendingDetection()
            mappedObjects = []; annotations = []; unidentifiedLights = []; opticalTracks = []
            candidateHistory = [:]; lastDetectionTime = -1
        }
        viewport = size; self.orientation = orientation
    }

    func start() async {
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
        mappedObjects = []
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
        let configuration = AROrientationTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading
        if star == nil {
            let formats = AROrientationTrackingConfiguration.supportedVideoFormats
            if let wide = formats.first(where:{ $0.captureDeviceType == .builtInWideAngleCamera && $0.framesPerSecond <= 30 })
                ?? formats.first(where:{ $0.captureDeviceType == .builtInWideAngleCamera }) {
                configuration.videoFormat = wide
            }
        }
        status = .preparing
        // Rotation-only tracking works for distant celestial objects without a nearby plane.
        session.run(configuration,options:[.resetTracking,.removeExistingAnchors])
    }
    private func prepareCameraControls() {
        guard !controlsPrepared else { return }
        controlsPrepared = true
        guard let device = AROrientationTrackingConfiguration.configurableCaptureDeviceForPrimaryCamera else {
            cameraControlMessage = "Brightness and zoom controls aren’t available in this camera mode."
            return
        }
        captureDevice = device
        originalExposure = device.exposureTargetBias
        originalZoom = device.videoZoomFactor
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
        zoomBase = device.videoZoomFactor
        minimumZoom = 1
        maximumZoom = Double(max(1,min(10,device.maxAvailableVideoZoomFactor/zoomBase)))
        exposureBias = Double(device.exposureTargetBias)
        cameraZoom = 1
        if maximumExposure <= minimumExposure { cameraControlMessage = "Brightness controls aren’t available in this camera mode." }
    }
    private func invalidateCameraMatches() {
        discardPendingDetection()
        mappedObjects = []
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
    func setZoom(_ requested: Double, animated: Bool = false) {
        guard let device = captureDevice, maximumZoom > minimumZoom else { return }
        let value = CGFloat(min(maximumZoom,max(minimumZoom,requested)))*zoomBase
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            let factor = min(device.maxAvailableVideoZoomFactor,max(device.minAvailableVideoZoomFactor,value))
            if device.isRampingVideoZoom { device.cancelVideoZoomRamp() }
            if animated { device.ramp(toVideoZoomFactor:factor,withRate:4) }
            else { device.videoZoomFactor = factor; cameraZoom = Double(device.videoZoomFactor/zoomBase) }
            cameraControlMessage = nil
            invalidateCameraMatches()
        } catch { cameraControlMessage = "We couldn’t change the zoom. Try again." }
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
                if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .none }
                if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = capturePoint }
                if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = capturePoint }
                if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            }
            focusLocked = locked
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
                if device.isRampingVideoZoom { device.cancelVideoZoomRamp() }
                if let originalZoom { device.videoZoomFactor = min(device.maxAvailableVideoZoomFactor,max(device.minAvailableVideoZoomFactor,originalZoom)) }
                if let originalLowLightBoost, device.isLowLightBoostSupported { device.automaticallyEnablesLowLightBoostWhenAvailable = originalLowLightBoost }
                if let originalFocusRange, device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = originalFocusRange }
                if let originalFocusPoint, device.isFocusPointOfInterestSupported { device.focusPointOfInterest = originalFocusPoint }
                if let originalExposurePoint, device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = originalExposurePoint }
                if let originalFocusMode, device.isFocusModeSupported(originalFocusMode) { device.focusMode = originalFocusMode }
                if let originalExposureMode, device.isExposureModeSupported(originalExposureMode) { device.exposureMode = originalExposureMode }
            } catch { /* The session may already have released the capture device. */ }
        }
        captureDevice = nil; originalExposure = nil; originalZoom = nil; controlsPrepared = false
        minimumExposure = 0; maximumExposure = 0; minimumZoom = 1; maximumZoom = 1
        originalLowLightBoost = nil; originalFocusMode = nil; originalExposureMode = nil
        originalFocusRange = nil; originalFocusPoint = nil; originalExposurePoint = nil; focusLocked = false
        exposureBias = 0; cameraZoom = 1
    }
    func stop() {
        discardPendingDetection()
        viewableObjects = []
        lastOverlayTime = -1
        restoreCameraControls()
        running = false; hasStartedSession = false
        session.pause(); locationManager.stopUpdatingLocation(); locationManager.stopUpdatingHeading(); hasLocationFix = false
        projection = nil; mappedObjects = []; annotations = []; unidentifiedLights = []; candidateHistory = [:]; opticalTracks = []; detectedLightCount = 0
        cameraHeadingAccuracy = nil; lastDetectionTime = -1; previousForward = nil
        status = .preparing
    }
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard running, hasStartedSession, hasLocationFix else { return }
        lastFrameTime = frame.timestamp
        if star == nil {
            prepareCameraControls()
            if let device = captureDevice {
                let actualZoom = Double(device.videoZoomFactor/zoomBase)
                if abs(actualZoom-cameraZoom) > 0.005 { cameraZoom = actualZoom }
            }
            if viewport.width > 0, viewport.height > 0 {
                imageDisplayTransform = frame.displayTransform(viewRotationAngle:viewRotationAngle,viewportSize:viewport)
            }
        }
        switch frame.camera.trackingState {
        case .normal: if status != .tracking { status = .tracking }
        case .limited: discardPendingDetection(); mappedObjects = []; annotations = []; unidentifiedLights = []; candidateHistory = [:]; opticalTracks = []; status = .limited("Hold your phone steady and move away from magnets."); projection = nil; return
        case .notAvailable: discardPendingDetection(); mappedObjects = []; annotations = []; unidentifiedLights = []; candidateHistory = [:]; opticalTracks = []; status = .limited("Finding the camera’s direction…"); projection = nil; return
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
        projection = SkyFinderProjection.project(direction:SkyFinderProjection.worldDirection(horizon),
            view:frame.camera.viewMatrix(viewRotationAngle:viewRotationAngle),
            projection:frame.camera.projectionMatrix(viewRotationAngle:viewRotationAngle,viewportSize:viewport,zNear:0.01,zFar:2000),size:viewport)
    }
    private func scan(frame: ARFrame, sky: SkySnapshot) {
        guard captureDevice?.isRampingVideoZoom != true, frame.timestamp >= controlsSettleUntil, !scannerPaused else { discardPendingDetection(); mappedObjects = []; annotations = []; unidentifiedLights = []; candidateHistory = [:]; opticalTracks = []; detectedLightCount = 0; return }
        let forward4 = frame.camera.transform.columns.2
        let forward = SIMD3(forward4.x,forward4.y,forward4.z)
        if let previousForward, simd_dot(forward,previousForward) < cos(1.5 * .pi/180) {
            discardPendingDetection()
            candidateHistory = [:]; annotations = []; opticalTracks = []; unidentifiedLights = []
        }
        previousForward = forward
        let view = frame.camera.viewMatrix(viewRotationAngle:viewRotationAngle)
        let projectionMatrix = frame.camera.projectionMatrix(viewRotationAngle:viewRotationAngle,viewportSize:viewport,zNear:0.01,zFar:2000)
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
        // Project with the same camera intrinsics and viewport as the live image, including zoom.
        // No forecast/cloud gate: these are catalog positions, not claimed detections.
        if let accuracy = cameraHeadingAccuracy, accuracy >= 0, accuracy <= 25 {
            mappedObjects = scanDirections.compactMap { star, direction in
                guard let point = projectLight(SkyFinderProjection.worldDirection(direction)) else { return nil }
                return CameraMappedObject(star:star,point:point,likelyVisible:likelyVisibleIDs.contains(star.id))
            }
        } else { mappedObjects = [] }
        let time = frame.timestamp
        // One analysis in flight; never queue camera frames or block the main actor on pixels.
        if detectionTask == nil, lastDetectionTime < 0 || time-lastDetectionTime >= 0.18 {
            lastDetectionTime = time
            let buffer = CameraAnalysisBuffer(value:frame.capturedImage), zoom = cameraZoom
            let generation = detectionGeneration
            let transform = frame.displayTransform(viewRotationAngle:viewRotationAngle,viewportSize:viewport)
            let size = viewport
            detectionTask = Task { @MainActor [weak self] in
                let sources = await Task.detached(priority:.userInitiated) {
                    CameraStarDetector.detectDiscs(in:buffer.value) + CameraStarDetector.detect(in:buffer.value,zoom:zoom)
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
                let previous = opticalTracks.filter { !usedTracks.contains($0.id) && time-$0.time < 0.65 }.compactMap { track -> (CameraOpticalTrack,Double)? in
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
            tracks += opticalTracks.filter { !usedTracks.contains($0.id) && time-$0.time < 0.65 }
            opticalTracks = tracks
        }
        let angularCandidates = didDetect ? scanDirections.filter { $0.0.mag <= 5.5 }.map { ($0.0,SkyFinderProjection.worldDirection($0.1)) } : []
        if didDetect { trackMatches = [:] }
        var visible: [CameraStarAnnotation] = []
        var unknown: [CameraLightAnnotation] = []
        var nextHistory: [Int:(starID:Int,hits:Int)] = [:]
        for track in opticalTracks.sorted(by: { $0.hits == $1.hits ? $0.id < $1.id : $0.hits > $1.hits }) where time-track.time < 0.4 {
            guard let point = projectLight(track.direction), point.y < viewport.height-90 else { continue }
            let match: CameraCandidateMatch?
            if didDetect {
                match = CameraCandidateMatcher.best(direction:track.direction,isDisc:track.isDisc,
                    zoom:cameraZoom,headingAccuracy:cameraHeadingAccuracy,candidates:angularCandidates)
                trackMatches[track.id] = match
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
                unknown.append(CameraLightAnnotation(id:track.id,point:point,size:track.size))
            }
        }
        candidateHistory = nextHistory
        annotations = visible
        unidentifiedLights = unknown
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        discardPendingDetection()
        projection = nil; mappedObjects = []; annotations = []; unidentifiedLights = []; candidateHistory = [:]; opticalTracks = []; hasStartedSession = false
        status = .unavailable("The camera stopped: \(error.localizedDescription)")
    }
    func sessionWasInterrupted(_ session: ARSession) {
        discardPendingDetection()
        projection = nil; mappedObjects = []; annotations = []; unidentifiedLights = []; candidateHistory = [:]; opticalTracks = []; status = .limited("Camera paused. Come back to the app to keep looking.")
    }
    func sessionInterruptionEnded(_ session: ARSession) {
        hasStartedSession = false
        if running { authorizeLocation() }
    }
}
