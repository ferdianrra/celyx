import AVFoundation
import CoreVideo
import Foundation
import Testing
import UIKit
import simd
@testable import celyx

nonisolated private final class TestCaptureDriver: SkyCaptureDriving, @unchecked Sendable {
    let captureSession = AVCaptureSession()
    let device: AVCaptureDevice? = nil
    private let lock = NSLock()
    private var callbacks: [@Sendable (Result<SkyCaptureFrame, Error>) -> Void] = []
    private var stops = 0
    private var releases = 0
    var stopCount: Int { lock.withLock { stops } }
    var releaseCount: Int { lock.withLock { releases } }
    func start(deliver: @escaping @Sendable (Result<SkyCaptureFrame, Error>) -> Void) { lock.withLock { callbacks.append(deliver) } }
    func stop() { lock.withLock { stops += 1 } }
    func releaseFrame() { lock.withLock { releases += 1 } }
    func configureDevice(_ update: @escaping @Sendable (AVCaptureDevice) -> Void) {}
    func emit(_ frame: SkyCaptureFrame, run: Int) {
        let callback = lock.withLock { callbacks[run] }
        callback(.success(frame))
    }
}

@MainActor private final class CaptureRecorder: SkyCaptureSessionDelegate {
    var times: [Double] = []
    var interruptions = 0
    func session(_ session: SkyCaptureSession, didUpdate frame: SkyCaptureFrame) { times.append(frame.timestamp) }
    func sessionWasInterrupted(_ session: SkyCaptureSession) { interruptions += 1 }
}

@MainActor struct SkyCaptureLifecycleTests {
    private func frame(at time: Double) throws -> SkyCaptureFrame {
        var image: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 32, 32, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nil, &image)
        return SkyCaptureFrame(capturedImage: try #require(image), timestamp: time,
            camera: SkyCaptureCamera(transform: matrix_identity_float4x4, intrinsics: matrix_identity_float3x3,
                imageResolution: CGSize(width: 32, height: 32), trackingState: .normal))
    }
    private func drain() async { try? await Task.sleep(for: .milliseconds(20)) }

    @Test func pauseAndResumeAcceptNewFramesAndDiscardOldRunCallbacksWithoutWedgingDelivery() async throws {
        let driver = TestCaptureDriver()
        let session = SkyCaptureSession(driver: driver)
        let recorder = CaptureRecorder(); session.delegate = recorder
        session.run(); driver.emit(try frame(at: 1), run: 0); await drain()
        #expect(recorder.times == [1])
        session.pause()
        #expect(!session.isRunning && session.currentFrame == nil)
        session.run()
        driver.emit(try frame(at: 2), run: 0) // Completion retained by the old run.
        driver.emit(try frame(at: 3), run: 1)
        await drain()
        #expect(session.isRunning)
        #expect(recorder.times == [1, 3])
        #expect(session.currentFrame?.timestamp == 3)
        #expect(driver.releaseCount == 3, "Discarded callbacks must also release the delivery slot")
    }

    @Test func screenshotEditorInactivityKeepsCaptureAndAlignmentButRealBackgroundStopsThem() {
        let driver = TestCaptureDriver()
        let session = SkyCaptureSession(driver: driver)
        let notifications = NotificationCenter()
        let name = "SkyCaptureLifecycleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let alignment = CameraSkyAlignment(defaults: defaults, notifications: notifications, session: session)
        alignment.save(rotation: simd_quatf(angle: 0.1, axis: SIMD3(0, 1, 0)), reference: "Jupiter", date: Date())
        alignment.run()
        notifications.post(name: UIApplication.userDidTakeScreenshotNotification, object: nil)
        notifications.post(name: UIApplication.willResignActiveNotification, object: nil)
        notifications.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        #expect(session.isRunning && !alignment.requiresCalibration)
        #expect(driver.stopCount == 0)
        notifications.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        #expect(!session.isRunning && alignment.requiresCalibration)
        #expect(driver.stopCount == 1)
    }

    private func postInterruptionOffMain(_ notifications: NotificationCenter, driver: TestCaptureDriver) -> Bool {
        let posted = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            notifications.post(name: AVCaptureSession.wasInterruptedNotification, object: driver.captureSession)
            posted.signal()
        }
        // Intentionally keep the UI occupied, reproducing native camera lock ordering.
        return posted.wait(timeout: .now() + 0.5) == .success
    }

    @Test func captureNotificationsNeverWaitSynchronouslyForTheUIThread() async {
        let driver = TestCaptureDriver()
        let notifications = NotificationCenter()
        let session = SkyCaptureSession(driver: driver, notifications: notifications)
        let recorder = CaptureRecorder(); session.delegate = recorder; session.run()
        #expect(postInterruptionOffMain(notifications, driver: driver))
        await drain()
        #expect(recorder.interruptions == 1)
    }
}
