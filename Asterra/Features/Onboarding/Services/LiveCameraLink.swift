import ARKit
import CoreImage
import SwiftUI
import simd

/// A window into the garden's live camera mode for the tour: the current pose (to pin practice stars
/// over the real image) and a frozen frame for the wormhole, built the same way the collect camera does.
@MainActor @Observable
final class LiveCameraLink {
    /// The live AR camera as a Night Sea camera; nil until ARKit tracks normally.
    var pose: NightSeaCamera?
    @ObservationIgnored weak var session: ARSession?
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
