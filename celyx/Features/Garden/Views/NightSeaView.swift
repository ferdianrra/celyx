import MetalKit
import SwiftUI

struct NightSeaView: UIViewRepresentable {
    var camera: NightSeaCamera
    var objects: [NightSeaObject]
    var selectedID: Int?
    /// Moon glitter on the sea and a halo in the sky, only when the Moon is in the collection and up.
    var moon: (direction: SIMD3<Double>, illumination: Double)?
    /// Columns: the equatorial X, Y, Z axes in the horizon frame for this place and time (rotates the Milky Way).
    var equatorial: simd_double3x3?
    var isActive = true
    var onError: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> MTKView {
        let view = NightSeaMetalView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0.01, 0.02, 0.07, 1)
        view.preferredFramesPerSecond = 60
        view.framebufferOnly = true
        do {
            let renderer = try NightSeaRenderer(view: view)
            context.coordinator.renderer = renderer
            view.delegate = renderer
        } catch {
            DispatchQueue.main.async { onError(error.localizedDescription) }
        }
        updateUIView(view, context: context)
        return view
    }
    func updateUIView(_ view: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        renderer.camera = camera
        renderer.setObjects(objects, selectedID: selectedID)
        renderer.moon = moon
        renderer.equatorial = equatorial
        view.isPaused = !isActive
    }
    static func dismantleUIView(_ view: MTKView, coordinator: Coordinator) {
        view.isPaused = true
        view.delegate = nil
    }
    final class Coordinator { var renderer: NightSeaRenderer? }
}

/// Caps the render target at 2× like the kit (the sea pass is a full-screen shader).
private final class NightSeaMetalView: MTKView {
    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = min(traitCollection.displayScale, 2)
        if contentScaleFactor != scale { contentScaleFactor = scale }
    }
}
