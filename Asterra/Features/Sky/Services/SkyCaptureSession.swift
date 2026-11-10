import AVFoundation
import CoreMotion
import UIKit
import simd

/// The native sensor image is landscape, with camera axes x right, y up, z back.
/// World coordinates remain east/up/south so astronomical calibration is shared by all screens.
nonisolated struct SkyCaptureCamera: Sendable {
    enum TrackingReason: Sendable { case initializing, insufficientFeatures, excessiveMotion, relocalizing }
    enum TrackingState: Sendable { case normal, limited(TrackingReason), notAvailable }
    let transform: simd_float4x4
    let intrinsics: simd_float3x3
    let imageResolution: CGSize
    let trackingState: TrackingState

    static func sensorPose(deviceToReference: simd_quatf) -> simd_float4x4 {
        // True-north reference axes: north/west/up -> east/up/south.
        let toWorld = simd_float4x4(columns: (SIMD4(0, 0, -1, 0), SIMD4(-1, 0, 0, 0),
                                            SIMD4(0, 1, 0, 0), SIMD4(0, 0, 0, 1)))
        // A native pixel step to the right becomes DOWN after the portrait
        // clockwise image rotation. Raw camera x therefore points along device -Y.
        let sensorToDevice = simd_float4x4(simd_quatf(angle: -.pi / 2, axis: SIMD3(0, 0, 1)))
        return toWorld * simd_float4x4(deviceToReference) * sensorToDevice
    }

    func viewMatrix(viewRotationAngle angle: CGFloat) -> simd_float4x4 {
        simd_float4x4(simd_quatf(angle: -Float(angle) * .pi / 180, axis: SIMD3(0, 0, 1)))
            * simd_inverse(transform)
    }

    func projectionMatrix(viewRotationAngle angle: CGFloat, viewportSize: CGSize,
                          zNear: CGFloat, zFar: CGFloat) -> simd_float4x4 {
        let w = Float(imageResolution.width), h = Float(imageResolution.height)
        let n = Float(zNear), f = Float(zFar)
        let base = simd_float4x4(columns: (
            SIMD4(2 * intrinsics[0, 0] / w, 0, 0, 0),
            SIMD4(0, 2 * intrinsics[1, 1] / h, 0, 0),
            SIMD4(1 - 2 * intrinsics[2, 0] / w, 2 * intrinsics[2, 1] / h - 1,
                  -(f + n) / (f - n), -1),
            SIMD4(0, 0, -2 * f * n / (f - n), 0)))
        let t = Self.imageTransform(angle: angle, imageSize: imageResolution, viewport: viewportSize)
        let screen = simd_float4x4(columns: (
            SIMD4(Float(t.a), Float(-t.b), 0, 0),
            SIMD4(Float(-t.c), Float(t.d), 0, 0), SIMD4(0, 0, 1, 0),
            SIMD4(Float(t.a + t.c + 2 * t.tx - 1), Float(1 - t.b - t.d - 2 * t.ty), 0, 1)))
        // Callers supply a view already rotated for the screen. Undo that rotation
        // here because the native intrinsics and display transform operate in sensor axes.
        let undo = simd_float4x4(simd_quatf(angle: Float(angle) * .pi / 180, axis: SIMD3(0, 0, 1)))
        return screen * base * undo
    }

    static func imageTransform(angle: CGFloat, imageSize: CGSize, viewport: CGSize) -> CGAffineTransform {
        guard viewport.width > 0, viewport.height > 0, imageSize.width > 0, imageSize.height > 0 else {
            return .identity
        }
        let rotation: CGAffineTransform
        let portrait: Bool
        switch Int(angle.rounded()) {
        case 90: rotation = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0); portrait = true
        case 180: rotation = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1, ty: 1); portrait = false
        case 270: rotation = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 1); portrait = true
        default: rotation = .identity; portrait = false
        }
        let size = portrait ? CGSize(width: imageSize.height, height: imageSize.width) : imageSize
        let fill = max(viewport.width / size.width, viewport.height / size.height)
        let sx = size.width * fill / viewport.width, sy = size.height * fill / viewport.height
        return rotation.concatenating(CGAffineTransform(a: sx, b: 0, c: 0, d: sy,
                                                       tx: (1 - sx) / 2, ty: (1 - sy) / 2))
    }
}

nonisolated struct SkyCaptureFrame: @unchecked Sendable {
    let capturedImage: CVPixelBuffer
    let timestamp: TimeInterval
    let camera: SkyCaptureCamera
    func displayTransform(viewRotationAngle: CGFloat, viewportSize: CGSize) -> CGAffineTransform {
        SkyCaptureCamera.imageTransform(angle: viewRotationAngle, imageSize: camera.imageResolution,
                                        viewport: viewportSize)
    }
}

@MainActor protocol SkyCaptureSessionDelegate: AnyObject {
    func session(_ session: SkyCaptureSession, didUpdate frame: SkyCaptureFrame)
    func session(_ session: SkyCaptureSession, didFailWithError error: Error)
    func sessionWasInterrupted(_ session: SkyCaptureSession)
    func sessionInterruptionEnded(_ session: SkyCaptureSession)
}
extension SkyCaptureSessionDelegate {
    func session(_ session: SkyCaptureSession, didFailWithError error: Error) {}
    func sessionWasInterrupted(_ session: SkyCaptureSession) {}
    func sessionInterruptionEnded(_ session: SkyCaptureSession) {}
}

/// Capture operations run off the UI actor. The injectable driver also lets lifecycle
/// regressions be tested without a physical camera or simulator motion sensors.
nonisolated protocol SkyCaptureDriving: AnyObject, Sendable {
    var captureSession: AVCaptureSession { get }
    var device: AVCaptureDevice? { get }
    func start(deliver: @escaping @Sendable (Result<SkyCaptureFrame, Error>) -> Void)
    func stop()
    func releaseFrame()
    func configureDevice(_ update: @escaping @Sendable (AVCaptureDevice) -> Void)
}

/// UI-facing owner. All capture configuration/start/stop work runs on the worker queue.
@MainActor final class SkyCaptureSession {
    weak var delegate: (any SkyCaptureSessionDelegate)?
    private(set) var currentFrame: SkyCaptureFrame?
    private let worker: any SkyCaptureDriving
    private(set) var isRunning = false
    private var generation = 0
    private var observers: [NSObjectProtocol] = []
    private let notificationCenter: NotificationCenter
    var captureSession: AVCaptureSession { worker.captureSession }
    var captureDevice: AVCaptureDevice? { worker.device }
    static var isSupported: Bool { CMMotionManager().isDeviceMotionAvailable &&
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil }

    init(driver: (any SkyCaptureDriving)? = nil, notifications: NotificationCenter = .default) {
        worker = driver ?? SkyCaptureWorker()
        notificationCenter = notifications
        let center = notifications
        // Never dispatch these notifications synchronously to the main queue:
        // start/stopRunning may post while holding native camera locks. The UI may
        // concurrently be configuring the device, which otherwise creates a lock cycle.
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification,
            object: worker.captureSession, queue: nil) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isRunning else { return }
                    self.currentFrame = nil
                    self.delegate?.sessionWasInterrupted(self)
                }
            })
        observers.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification,
            object: worker.captureSession, queue: nil) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isRunning else { return }
                    self.delegate?.sessionInterruptionEnded(self)
                }
            })
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
            object: worker.captureSession, queue: nil) { [weak self] note in
                let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
                    ?? NSError(domain: "SkyCapture", code: 1)
                Task { @MainActor [weak self] in
                    guard let self, self.isRunning else { return }
                    self.pause()
                    self.delegate?.session(self, didFailWithError: error)
                }
            })
    }
    deinit { observers.forEach(notificationCenter.removeObserver); worker.stop() }
    func run() {
        isRunning = true
        generation += 1
        let token = generation
        worker.start { [weak self, weak worker] result in
            Task { @MainActor [weak self, weak worker] in
                if case .success = result { defer { worker?.releaseFrame() }; self?.receive(result, token: token) }
                else { self?.receive(result, token: token) }
            }
        }
    }
    private func receive(_ result: Result<SkyCaptureFrame, Error>, token: Int) {
        guard generation == token else { return }
        switch result {
        case .success(let frame): currentFrame = frame; delegate?.session(self, didUpdate: frame)
        case .failure(let error): pause(); delegate?.session(self, didFailWithError: error)
        }
    }
    func pause() { isRunning = false; generation += 1; currentFrame = nil; worker.stop() }
    func configureDevice(_ update: @escaping @Sendable (AVCaptureDevice) -> Void) {
        worker.configureDevice(update)
    }
}

/// Both motion history and camera callbacks are serialized on one queue. Intrinsics
/// come from the actual output buffer; stabilization is off to preserve that geometry.
nonisolated private final class SkyCaptureWorker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, SkyCaptureDriving, @unchecked Sendable {
    let captureSession = AVCaptureSession()
    let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    private let queue = DispatchQueue(label: "celyx.sky.capture", qos: .userInitiated)
    private let motion = CMMotionManager()
    private let motionQueue = OperationQueue()
    private var history: [MotionSample] = []
    private var deliver: (@Sendable (Result<SkyCaptureFrame, Error>) -> Void)?
    private var configured = false
    private var missingIntrinsics = 0
    private var missingMotionSince: TimeInterval?
    private let deliveryLock = NSLock()
    private var frameInFlight = false
    func releaseFrame() { deliveryLock.withLock { frameInFlight = false } }
    private func reserveFrame() -> Bool {
        deliveryLock.withLock {
            guard !frameInFlight else { return false }
            frameInFlight = true; return true
        }
    }
    private struct MotionSample { let time: Double; let rotation: simd_quatf; let speed: Double }

    override init() {
        super.init()
        motionQueue.maxConcurrentOperationCount = 1
        motionQueue.underlyingQueue = queue
    }
    func start(deliver: @escaping @Sendable (Result<SkyCaptureFrame, Error>) -> Void) {
        queue.async { [self] in
            self.deliver = deliver
            do {
                if !configured { try configure() }
                guard !captureSession.isRunning else { return }
                history.removeAll()
                missingMotionSince = nil
                missingIntrinsics = 0
                let frames = CMMotionManager.availableAttitudeReferenceFrames()
                guard motion.isDeviceMotionAvailable, frames.contains(.xTrueNorthZVertical) else {
                    throw NSError(domain: "SkyCapture", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "True-north motion tracking is unavailable."])
                }
                motion.deviceMotionUpdateInterval = 1.0 / 100
                motion.startDeviceMotionUpdates(using: .xTrueNorthZVertical, to: motionQueue) { [weak self] data, error in
                    guard let self else { return }
                    if let error { self.deliver?(.failure(error)); return }
                    guard let data else { return }
                    let r = data.attitude.rotationMatrix
                    // CMAttitude's DCM maps reference -> device. Its rows are the
                    // device axes in reference coordinates; transpose for device -> reference.
                    let deviceToReference = simd_float3x3(columns: (
                        SIMD3(Float(r.m11), Float(r.m12), Float(r.m13)),
                        SIMD3(Float(r.m21), Float(r.m22), Float(r.m23)),
                        SIMD3(Float(r.m31), Float(r.m32), Float(r.m33))))
                    let speed = data.rotationRate
                    self.history.append(MotionSample(time: data.timestamp,
                        rotation: simd_quatf(deviceToReference),
                        speed: sqrt(speed.x * speed.x + speed.y * speed.y + speed.z * speed.z)))
                    self.history.removeAll { data.timestamp - $0.time > 3 }
                }
                captureSession.startRunning()
            } catch { deliver(.failure(error)) }
        }
    }
    func stop() { queue.async { [self] in
        deliver = nil; motion.stopDeviceMotionUpdates(); history.removeAll()
        if captureSession.isRunning { captureSession.stopRunning() }
    } }
    func configureDevice(_ update: @escaping @Sendable (AVCaptureDevice) -> Void) {
        queue.async { [self] in
            guard let device else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                update(device)
            } catch { /* A stopped/disconnected camera no longer needs its controls restored. */ }
        }
    }
    private func configure() throws {
        guard let device else { throw NSError(domain: "SkyCapture", code: 3,
            userInfo: [NSLocalizedDescriptionKey: "The back camera is unavailable."]) }
        captureSession.beginConfiguration()
        var committed = false
        defer { if !committed { captureSession.commitConfiguration() } }
        // Clear a partial configuration before retrying after a setup failure.
        captureSession.inputs.forEach(captureSession.removeInput)
        captureSession.outputs.forEach(captureSession.removeOutput)
        captureSession.sessionPreset = .hd1920x1080
        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input) else { throw NSError(domain: "SkyCapture", code: 4) }
        captureSession.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.setSampleBufferDelegate(self, queue: queue)
        guard captureSession.canAddOutput(output) else { throw NSError(domain: "SkyCapture", code: 5) }
        captureSession.addOutput(output)
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(0) { connection.videoRotationAngle = 0 }
            if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .off }
            guard connection.isCameraIntrinsicMatrixDeliverySupported else {
                throw NSError(domain: "SkyCapture", code: 6, userInfo:
                    [NSLocalizedDescriptionKey: "This camera cannot provide calibrated image geometry."])
            }
            connection.isCameraIntrinsicMatrixDeliveryEnabled = true
        }
        captureSession.commitConfiguration()
        committed = true
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        // Allow auto-exposure to slow down in darkness rather than forcing 60 fps.
        let ranges = device.activeFormat.videoSupportedFrameRateRanges
        let minFPS = ranges.map(\.minFrameRate).min() ?? 30
        let maxFPS = ranges.map(\.maxFrameRate).max() ?? 30
        device.activeVideoMinFrameDuration = CMTime(seconds: 1 / min(30, maxFPS), preferredTimescale: 600)
        device.activeVideoMaxFrameDuration = CMTime(seconds: 1 / max(10, minFPS), preferredTimescale: 600)
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
            let limit = min(device.activeVideoMaxFrameDuration.seconds, device.activeFormat.maxExposureDuration.seconds)
            device.activeMaxExposureDuration = CMTime(seconds: max(device.activeFormat.minExposureDuration.seconds, limit),
                                                      preferredTimescale: 1_000_000)
        }
        if device.isLowLightBoostSupported { device.automaticallyEnablesLowLightBoostWhenAvailable = true }
        if device.isFocusModeSupported(.locked), device.isLockingFocusWithCustomLensPositionSupported {
            device.setFocusModeLocked(lensPosition: 1, completionHandler: nil)
        }
        configured = true
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let deliver, let image = CMSampleBufferGetImageBuffer(buffer), let device else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
        let host = captureSession.synchronizationClock.map {
            CMSyncConvertTime(pts, from: $0, to: CMClockGetHostTimeClock())
        } ?? pts
        let timestamp = host.seconds
        // Match the capture timestamp in the host clock, never the time analysis finishes.
        let target = timestamp
        guard let nearest = history.min(by: { abs($0.time - target) < abs($1.time - target) }),
            abs(nearest.time - target) < 0.12 else {
            if missingMotionSince == nil { missingMotionSince = timestamp }
            if timestamp - (missingMotionSince ?? timestamp) > 2 {
                deliver(.failure(NSError(domain: "SkyCapture", code: 8, userInfo:
                    [NSLocalizedDescriptionKey: "Motion data is unavailable or out of sync. Check motion access and reopen the camera."])))
                self.deliver = nil
            }
            return
        }
        missingMotionSince = nil
        var attitude = nearest.rotation
        if let before = history.last(where: { $0.time <= target }),
            let after = history.first(where: { $0.time > target }), after.time - before.time < 0.1 {
            attitude = simd_slerp(before.rotation, after.rotation, Float((target - before.time) / (after.time - before.time)))
        }
        let size = CGSize(width: CVPixelBufferGetWidth(image), height: CVPixelBufferGetHeight(image))
        guard let data = CMGetAttachment(buffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
                                          attachmentModeOut: nil) as? Data,
            data.count >= MemoryLayout<simd_float3x3>.size else {
            // Never identify against guessed field-of-view geometry.
            missingIntrinsics += 1
            if missingIntrinsics >= 15 {
                deliver(.failure(NSError(domain: "SkyCapture", code: 7, userInfo:
                    [NSLocalizedDescriptionKey: "The camera is not delivering calibrated image geometry."])))
                self.deliver = nil
            }
            return
        }
        missingIntrinsics = 0
        let intrinsics = data.withUnsafeBytes { $0.loadUnaligned(as: simd_float3x3.self) }
        let pose = SkyCaptureCamera.sensorPose(deviceToReference: attitude)
        let blurred = nearest.speed * device.exposureDuration.seconds > 0.006
        let camera = SkyCaptureCamera(transform: pose, intrinsics: intrinsics, imageResolution: size,
                                      trackingState: blurred ? .limited(.excessiveMotion) : .normal)
        guard reserveFrame() else { return }
        deliver(.success(SkyCaptureFrame(capturedImage: image, timestamp: timestamp, camera: camera)))
    }
}
