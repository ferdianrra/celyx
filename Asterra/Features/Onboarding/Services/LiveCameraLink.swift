import CoreImage
import SwiftUI
import simd

/// A window into the garden's live camera mode for the tour: the current pose (to pin practice stars
/// over the real image) and a frozen frame for the wormhole, built the same way the collect camera does.
@MainActor @Observable
final class LiveCameraLink: SkyCaptureSessionDelegate {
    enum State: Equatable {
        case idle, starting, streaming
        case failed(String)
    }
    private(set) var state: State = .idle

    func reset() {
        pose = nil
        state = .idle
    }

    func connect(to session: SkyCaptureSession) {
        reset()
        self.session = session
        session.delegate = self
        state = .starting
    }

    func disconnect(from session: SkyCaptureSession) {
        guard self.session === session else { return }
        session.delegate = nil
        self.session = nil
        reset()
    }

    func previewChanged(_ previewing: Bool, from session: SkyCaptureSession) {
        guard self.session === session, previewing else { return }
        if case .failed = state { return }
        if state != .streaming { state = .streaming }
    }

    func session(_ session: SkyCaptureSession, didUpdate frame: SkyCaptureFrame) {
        guard self.session === session else { return }
        // A delivered image is ready even if motion currently limits sky alignment.
        // This pose is for the tutorial only; optical identification retains its own tracking gates.
        if viewport.width > 0, viewport.height > 0 {
            let freeze = WormholeFreeze.make(image: nil, size: viewport,
                view: frame.camera.viewMatrix(viewRotationAngle: 90),
                projection: frame.camera.projectionMatrix(viewRotationAngle: 90, viewportSize: viewport, zNear: 0.01, zFar: 2000),
                alignment: simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)))
            var camera = NightSeaCamera()
            camera.orientation = freeze.orientation
            camera.focalOverride = freeze.focal
            pose = camera
        }
        state = .streaming
    }

    func session(_ session: SkyCaptureSession, didFailWithError error: Error) {
        guard self.session === session else { return }
        pose = nil
        state = .failed(error.localizedDescription)
    }

    func sessionWasInterrupted(_ session: SkyCaptureSession) {
        guard self.session === session else { return }
        pose = nil
        state = .starting
    }

    func sessionInterruptionEnded(_ session: SkyCaptureSession) {
        guard self.session === session else { return }
        state = .starting
    }

    /// The live capture camera as a Night Sea camera; updated from delivered frames independently of tracking quality.
    var pose: NightSeaCamera?
    @ObservationIgnored weak var session: SkyCaptureSession?
    @ObservationIgnored var viewport: CGSize = .zero
    @ObservationIgnored private let context = CIContext()

    /// The current camera frame, cropped and oriented like the portrait preview, with its pose.
    func freeze() -> WormholeFreeze? {
        guard let frame = session?.currentFrame, viewport.width > 0, viewport.height > 0 else { return nil }
        let source = CIImage(cvPixelBuffer: frame.capturedImage).oriented(.right)
        let crop = CameraZoom.imageCrop(extent: source.extent, viewport: viewport, zoom: 1)
        let image = context.createCGImage(source, from: crop)
        return WormholeFreeze.make(image: image, size: viewport,
            view: frame.camera.viewMatrix(viewRotationAngle: 90),
            projection: frame.camera.projectionMatrix(viewRotationAngle: 90, viewportSize: viewport, zNear: 0.01, zFar: 2000),
            alignment: simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)))
    }
}
