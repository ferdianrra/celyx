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
    private(set) var unidentifiedLights: [CameraLightAnnotation] = []
    private(set) var detectedLightCount = 0
    private(set) var cameraHeadingAccuracy: Double?
    private var opticalTracks: [CameraOpticalTrack] = []
    private var nextOpticalID = 0
    private(set) var skyDate: Date?
    var scannerPaused = false
    var observerLocation: ObserverLocation? { hasLocationFix ? location : nil }
    private var detections: [Int:(hits: Int, offset: CGPoint, size: CGSize, time: TimeInterval, direction: SIMD3<Float>)] = [:]
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
    private var lastFrameTime: TimeInterval = 0
    private var controlsSettleUntil: TimeInterval = 0
    private var location: ObserverLocation
    private var hasLocationFix = false
    private var viewport = CGSize.zero
    private var orientation: UIInterfaceOrientation = .portrait
    private var running = false
    private var hasStartedSession = false
    var isCameraRunning: Bool { hasStartedSession }
    private var sky: SkySnapshot?
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
            annotations = []; detections = [:]; lastDetectionTime = -1
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
        annotations = []; unidentifiedLights = []; detections = [:]; opticalTracks = []
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
        annotations = []; unidentifiedLights = []; detections = [:]; opticalTracks = []; detectedLightCount = 0; lastDetectionTime = -1
        controlsSettleUntil = lastFrameTime+0.8
    }
    func setExposure(_ requested: Double) {
        guard let device = captureDevice, maximumExposure > minimumExposure else { return }
        let value = Float(min(maximumExposure,max(minimumExposure,requested)))
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
        } catch { cameraControlMessage = "We couldn’t change the zoom. Try again. Coba lagi sebentar." }
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
        restoreCameraControls()
        running = false; hasStartedSession = false
        session.pause(); locationManager.stopUpdatingLocation(); locationManager.stopUpdatingHeading(); hasLocationFix = false
        projection = nil; annotations = []; unidentifiedLights = []; detections = [:]; opticalTracks = []; detectedLightCount = 0
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
        case .normal: status = .tracking
        case .limited: annotations = []; unidentifiedLights = []; detections = [:]; opticalTracks = []; status = .limited("Hold your phone steady and move away from magnets."); projection = nil; return
        case .notAvailable: annotations = []; unidentifiedLights = []; detections = [:]; opticalTracks = []; status = .limited("Finding the camera’s direction…"); projection = nil; return
        }
        let now = Date()
        if sky == nil || now.timeIntervalSince(lastSnapshot) >= 1 {
            sky = AstronomyService.snapshot(date:now,location:location); lastSnapshot = now; skyDate = now
            if star == nil, let sky {
                scanDirections = catalogue.filter { $0.mag <= 5.5 }.compactMap { star in
                    let direction = sky.direction(ra:star.ra_deg,dec:star.dec_deg)
                    return direction.z > sin(5 * .pi/180) ? (star,direction) : nil
                }
                scanDirections += [(CatalogStar.sun,sky.sunDirection),(CatalogStar.moon,sky.moonDirection)].filter { $0.1.z > 0 }
            }
        }
        guard let sky, viewport.width > 0, viewport.height > 0 else { return }
        guard let star else {
            scan(frame:frame,sky:sky)
            return
        }
        let horizon = star.isSun ? sky.sunDirection : star.isMoon ? sky.moonDirection : sky.direction(ra:star.ra_deg,dec:star.dec_deg)
        altitude = asin(min(1,max(-1,horizon.z))) * 180 / .pi
        guard horizon.z > 0 else { projection = nil; return }
        projection = SkyFinderProjection.project(direction:SkyFinderProjection.worldDirection(horizon),
            view:frame.camera.viewMatrix(viewRotationAngle:viewRotationAngle),
            projection:frame.camera.projectionMatrix(viewRotationAngle:viewRotationAngle,viewportSize:viewport,zNear:0.01,zFar:2000),size:viewport)
    }
    private func scan(frame: ARFrame, sky: SkySnapshot) {
        guard captureDevice?.isRampingVideoZoom != true, frame.timestamp >= controlsSettleUntil, !scannerPaused else { annotations = []; unidentifiedLights = []; detections = [:]; opticalTracks = []; detectedLightCount = 0; return }
        let forward4 = frame.camera.transform.columns.2
        let forward = SIMD3(forward4.x,forward4.y,forward4.z)
        if let previousForward, simd_dot(forward,previousForward) < cos(1.5 * .pi/180) {
            detections = [:]; annotations = []; opticalTracks = []; unidentifiedLights = []
        }
        previousForward = forward
        let view = frame.camera.viewMatrix(viewRotationAngle:viewRotationAngle)
        let projectionMatrix = frame.camera.projectionMatrix(viewRotationAngle:viewRotationAngle,viewportSize:viewport,zNear:0.01,zFar:2000)
        let candidates: [(CatalogStar,CGPoint)] = scanDirections.compactMap { star,direction in
            let projected = SkyFinderProjection.project(direction:SkyFinderProjection.worldDirection(direction),view:view,projection:projectionMatrix,size:viewport)
            guard let point = projected.point, point.x > 24, point.x < viewport.width-24,
                  point.y > 24, point.y < viewport.height-90 else { return nil }
            return (star,point)
        }
        func projectLight(_ direction: SIMD3<Float>) -> CGPoint? {
            SkyFinderProjection.project(direction:direction,view:view,projection:projectionMatrix,size:viewport).point
        }
        func worldRay(_ point: CGPoint) -> SIMD3<Float> {
            let clip = SIMD4<Float>(Float(point.x/viewport.width*2-1),Float(1-point.y/viewport.height*2),1,1)
            let camera = simd_inverse(projectionMatrix)*clip
            let local = simd_normalize(SIMD3(camera.x,camera.y,camera.z))
            let world = simd_inverse(view)*SIMD4(local.x,local.y,local.z,0)
            return simd_normalize(SIMD3(world.x,world.y,world.z))
        }
        let time = frame.timestamp
        if lastDetectionTime < 0 || time-lastDetectionTime >= 0.18 {
            lastDetectionTime = time
            let transform = frame.displayTransform(viewRotationAngle:viewRotationAngle,viewportSize:viewport)
            let sources = CameraStarDetector.detectDiscs(in:frame.capturedImage) + CameraStarDetector.detect(in:frame.capturedImage,zoom:cameraZoom)
            let lights = sources.compactMap { light -> (CGPoint,CGSize,Bool)? in
                let normalized = light.point.applying(transform)
                guard normalized.x > 0, normalized.x < 1, normalized.y > 0, normalized.y < 1 else { return nil }
                let bounds = light.bounds.applying(transform)
                return (CGPoint(x:normalized.x*viewport.width,y:normalized.y*viewport.height),
                    CGSize(width:max(5,min(14,abs(bounds.width)*viewport.width+3)),height:max(5,min(14,abs(bounds.height)*viewport.height+3))),light.isDisc)
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
                let previous = opticalTracks.filter { !usedTracks.contains($0.id) && time-$0.time < 0.55 }.compactMap { track -> (CameraOpticalTrack,Double)? in
                    guard let point = projectLight(track.direction) else { return nil }
                    return (track,hypot(point.x-light.0.x,point.y-light.0.y))
                }.filter { $0.1 < 12 }.min { $0.1 < $1.1 }?.0
                let id: Int
                if let previous { id = previous.id; usedTracks.insert(id) }
                else { nextOpticalID += 1; id = nextOpticalID }
                tracks.append(CameraOpticalTrack(id:id,hits:(previous?.hits ?? 0)+1,direction:worldRay(light.0),size:light.1,time:time,isDisc:light.2))
            }
            opticalTracks = tracks
            let searchRadius = min(70,max(20,Double(projectionMatrix.columns.0.x)*viewport.width/2*tan(2 * .pi/180)))
            let headingReady = cameraHeadingAccuracy.map { $0 <= 15 } ?? false
            var next: [Int:(hits: Int, offset: CGPoint, size: CGSize, time: TimeInterval, direction: SIMD3<Float>)] = [:]
            var used: Set<Int> = []
            for (star,predicted) in candidates where headingReady {
                let matches = lights.enumerated().filter { !used.contains($0.offset) && (!$0.element.2 || star.isSolarSystemBody) }.map { index,light in
                    (index,light,hypot(light.0.x-predicted.x,light.0.y-predicted.y))
                }.filter { $0.2 < searchRadius }.sorted { $0.2 < $1.2 }
                guard let match = matches.first else { continue }
                // Suppress ambiguous local matches; this remains a sensor-assisted estimate, not plate solving.
                let competing = candidates.filter { $0.0.id != star.id }.map { hypot($0.1.x-match.1.0.x,$0.1.y-match.1.0.y) }.min() ?? .infinity
                guard competing > match.2*1.6+4 else { continue }
                let offset = CGPoint(x:match.1.0.x-predicted.x,y:match.1.0.y-predicted.y)
                let previous = detections[star.id]
                let stable = previous.map { hypot($0.offset.x-offset.x,$0.offset.y-offset.y) < 7 && time-$0.time < 0.55 } ?? false
                next[star.id] = (stable ? (previous?.hits ?? 0)+1 : 1,offset,match.1.1,time,worldRay(match.1.0))
                used.insert(match.0)
            }
            detections = next
        }
        var visible: [CameraStarAnnotation] = []
        for (star,_) in candidates {
            guard let detection = detections[star.id], detection.hits >= 3, time-detection.time < 0.3 else { continue }
            guard let point = projectLight(detection.direction) else { continue }
            guard !visible.contains(where:{ hypot($0.point.x-point.x,$0.point.y-point.y) < 65 }) else { continue }
            visible.append(CameraStarAnnotation(star:star,point:point,size:detection.size,sourceDirection:detection.direction))
            if visible.count >= 8 { break }
        }
        // Compass offsets can move catalogue positions outside a narrow zoomed viewport.
        // Compare world-space angles, while keeping every marker on the observed light.
        let angularCandidates = scanDirections.map { ($0.0,SkyFinderProjection.worldDirection($0.1)) }
        var unknown: [CameraLightAnnotation] = []
        for track in opticalTracks.sorted(by: { $0.hits > $1.hits }) where track.hits >= 3 && time-track.time < 0.3 {
            guard let point = projectLight(track.direction), point.y < viewport.height-90,
                  !visible.contains(where: { hypot($0.point.x-point.x,$0.point.y-point.y) < 90 }),
                  !unknown.contains(where: { hypot($0.point.x-point.x,$0.point.y-point.y) < 90 }) else { continue }
            let ranked = angularCandidates.map { star,direction in
                (star,Double(acos(min(1,max(-1,simd_dot(track.direction,direction)))))*180 / .pi)
            }
            let nearbyBody = ranked.filter { $0.0.isSolarSystemBody && $0.1 <= 20 }.min { $0.1 < $1.1 }
            let nearest = track.isDisc && nearbyBody != nil ? nearbyBody : ranked.min { $0.1 < $1.1 }
            // A bounded fallback avoids naming unrelated lights using a distant sky object.
            if let (star,separation) = nearest, separation <= 20,
               !visible.contains(where: { $0.star.id == star.id }), visible.count < 8 {
                visible.append(CameraStarAnnotation(star:star,point:point,size:track.size,estimatedSeparation:separation,sourceDirection:track.direction))
            } else if unknown.count < 8 {
                unknown.append(CameraLightAnnotation(id:track.id,point:point,size:track.size))
            }
        }
        annotations = visible
        unidentifiedLights = unknown
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        projection = nil; annotations = []; unidentifiedLights = []; detections = [:]; opticalTracks = []; hasStartedSession = false
        status = .unavailable("The camera stopped: \(error.localizedDescription)")
    }
    func sessionWasInterrupted(_ session: ARSession) {
        projection = nil; annotations = []; unidentifiedLights = []; detections = [:]; opticalTracks = []; status = .limited("Camera paused. Come back to the app to keep looking.")
    }
    func sessionInterruptionEnded(_ session: ARSession) {
        hasStartedSession = false
        if running { authorizeLocation() }
    }
}
