import ImageIO
import MetalKit
import SwiftUI
import simd

/// Pinhole camera from the Night Sea kit: focal length 0.62·min(W,H)/tan(fov/2), optical centre (W/2, 0.47·H).
/// Shared by the Metal renderer and SwiftUI (labels, taps), so both agree on where every object is.
///
/// With `orientation` set (gyro), it becomes a 1:1 window onto the real sky instead: the phone's full
/// attitude (heading, tilt and roll) and the back camera's real field of view, centred on the screen,
/// so an object appears exactly where it is behind the phone.
private struct SeaUniforms {
    var res: SIMD4<Float>
    var cam: SIMD4<Float>
    var forward: SIMD4<Float>
    var right: SIMD4<Float>
    var up: SIMD4<Float>
    var zenith: SIMD4<Float>
    var mid: SIMD4<Float>
    var horizon: SIMD4<Float>
    var moon: SIMD4<Float>
    var flags: SIMD4<Float>
    var e0: SIMD4<Float>
    var e1: SIMD4<Float>
    var e2: SIMD4<Float>
}

private struct GPUPoint {
    var dirSize: SIMD4<Float>
    var color: SIMD4<Float>
}

@MainActor
final class NightSeaRenderer: NSObject, MTKViewDelegate {
    var camera = NightSeaCamera()
    var moon: (direction: SIMD3<Double>, illumination: Double)?
    var equatorial: simd_double3x3?
    /// Subtle on purpose: the collected objects must stay the brightest things in the sky.
    private let milkyWayStrength: Float = 0.26
    private let milkyWay: MTLTexture
    private let queue: MTLCommandQueue
    private let seaPipeline: MTLRenderPipelineState
    private let pointPipeline: MTLRenderPipelineState
    private var layerTexture: MTLTexture?
    private var pointBuffer: MTLBuffer?
    private var pointCount = 0
    private var lastObjects: [NightSeaObject] = []
    private var lastSelected: Int?
    private let inFlight = DispatchSemaphore(value: 2)
    private let start = CACurrentMediaTime()
    private let reduceMotion = UIAccessibility.isReduceMotionEnabled
    // Kit palette: zenith #03051a, mid #0d1844, horizon #3a5d93.
    private let zenith = SIMD4<Float>(3 / 255, 5 / 255, 26 / 255, 0)
    private let mid = SIMD4<Float>(13 / 255, 24 / 255, 68 / 255, 0)
    private let horizon = SIMD4<Float>(58 / 255, 93 / 255, 147 / 255, 0)

    init(view: MTKView) throws {
        guard let device = view.device, let queue = device.makeCommandQueue() else {
            throw NSError(
                domain: "NightSea", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "This device doesn’t support Metal."])
        }
        self.queue = queue
        let source = try String(
            contentsOf: SkyAssets.url("NightSeaShader", extension: "txt"), encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)
        let sea = MTLRenderPipelineDescriptor()
        sea.vertexFunction = library.makeFunction(name: "seaVertex")
        sea.fragmentFunction = library.makeFunction(name: "seaFragment")
        sea.colorAttachments[0].pixelFormat = view.colorPixelFormat
        seaPipeline = try device.makeRenderPipelineState(descriptor: sea)
        let points = MTLRenderPipelineDescriptor()
        points.vertexFunction = library.makeFunction(name: "gardenPointVertex")
        points.fragmentFunction = library.makeFunction(name: "gardenPointFragment")
        let attachment = points.colorAttachments[0]!
        attachment.pixelFormat = .rgba8Unorm
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pointPipeline = try device.makeRenderPipelineState(descriptor: points)
        milkyWay = try Self.loadMilkyWay(device: device)
        super.init()
    }

    /// RA/Dec Milky Way map from the Night Sea kit, downsampled to 2048 px wide with mipmaps.
    private static func loadMilkyWay(device: MTLDevice) throws -> MTLTexture {
        let url = try SkyAssets.url("garden-milky-way-radec", extension: "jpg")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2048,
                ] as CFDictionary)
        else { throw CocoaError(.fileReadCorruptFile) }
        let loader = MTKTextureLoader(device: device)
        return try loader.newTexture(
            cgImage: image,
            options: [
                .SRGB: false, .generateMipmaps: true,
                .textureStorageMode: MTLStorageMode.private.rawValue,
            ])
    }

    func setObjects(_ objects: [NightSeaObject], selectedID: Int?) {
        guard objects != lastObjects || selectedID != lastSelected else { return }
        lastObjects = objects
        lastSelected = selectedID
        let gpu = objects.map { object in
            GPUPoint(
                dirSize: SIMD4(
                    Float(object.direction.x), Float(object.direction.y), Float(object.direction.z),
                    Float(object.radius)),
                color: SIMD4(
                    Float(object.color.x), Float(object.color.y), Float(object.color.z),
                    object.kind.rawValue + (object.id == selectedID ? 10 : 0)))
        }
        pointCount = gpu.count
        pointBuffer =
            gpu.isEmpty
            ? nil
            : queue.device.makeBuffer(
                bytes: gpu, length: gpu.count * MemoryLayout<GPUPoint>.stride, options: .storageModeShared)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { layerTexture = nil }

    private func layer(for size: CGSize) -> MTLTexture? {
        let width = max(1, Int(size.width))
        let height = max(1, Int(size.height))
        if let layerTexture, layerTexture.width == width, layerTexture.height == height {
            return layerTexture
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        layerTexture = queue.device.makeTexture(descriptor: descriptor)
        return layerTexture
    }

    func draw(in view: MTKView) {
        guard inFlight.wait(timeout: .now()) == .success else { return }
        let size = view.drawableSize
        guard size.width > 0, let drawable = view.currentDrawable,
            let pass = view.currentRenderPassDescriptor,
            let layer = layer(for: size), let command = queue.makeCommandBuffer()
        else {
            inFlight.signal()
            return
        }
        let points = view.bounds.size
        let scale = size.width / max(points.width, 1)
        let focal = camera.focalLength(in: points)
        let center = camera.center(in: points)
        func v(_ d: SIMD3<Double>) -> SIMD4<Float> { SIMD4(Float(d.x), Float(d.y), Float(d.z), 0) }
        let time = reduceMotion ? 0 : Float(CACurrentMediaTime() - start)
        var moonUp: Float = 0
        var moonVector = SIMD4<Float>(0, 0, -1, 0)
        if let moon {
            let altitudeDegrees = moon.direction.z * 180 / .pi
            moonUp = Float(min(1, max(0, (altitudeDegrees + 1) / 3)))
            moonVector = SIMD4(
                Float(moon.direction.x), Float(moon.direction.y), Float(moon.direction.z),
                Float(moon.illumination))
        }
        let wave: Float = reduceMotion ? 0.06 : 0.14
        let res = SIMD4<Float>(Float(size.width), Float(size.height), Float(scale), time)
        let cam = SIMD4<Float>(Float(focal), Float(center.x), Float(center.y), wave)
        let flags = SIMD4<Float>(
            moonUp, moonUp * moonVector.w, 1, equatorial == nil ? 0 : milkyWayStrength)
        let basis = equatorial ?? matrix_identity_double3x3
        // Mip level: texels per radian of the map vs. pixels per radian on screen.
        let texelsPerRadian = Double(milkyWay.width) / (2 * .pi)
        // +1.2 blurs the map's tiny background dots so they never read as collected stars.
        let lod = Float(max(0, log2(texelsPerRadian / max(1, focal * Double(scale)))) + 1.2)
        var e2 = v(basis.columns.2)
        e2.w = lod
        var uniforms = SeaUniforms(
            res: res, cam: cam, forward: v(camera.forward), right: v(camera.right), up: v(camera.up),
            zenith: zenith, mid: mid, horizon: horizon, moon: moonVector, flags: flags,
            e0: v(basis.columns.0), e1: v(basis.columns.1), e2: e2)

        // Pass 1: collected objects into the offscreen layer.
        let layerPass = MTLRenderPassDescriptor()
        layerPass.colorAttachments[0].texture = layer
        layerPass.colorAttachments[0].loadAction = .clear
        layerPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        layerPass.colorAttachments[0].storeAction = .store
        if let encoder = command.makeRenderCommandEncoder(descriptor: layerPass) {
            if let pointBuffer, pointCount > 0 {
                encoder.setRenderPipelineState(pointPipeline)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<SeaUniforms>.stride, index: 0)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SeaUniforms>.stride, index: 0)
                encoder.setVertexBuffer(pointBuffer, offset: 0, index: 1)
                encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: pointCount)
            }
            encoder.endEncoding()
        }
        // Pass 2: sky, islands and the sea that mirrors the layer.
        if let encoder = command.makeRenderCommandEncoder(descriptor: pass) {
            encoder.setRenderPipelineState(seaPipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SeaUniforms>.stride, index: 0)
            encoder.setFragmentTexture(layer, index: 0)
            encoder.setFragmentTexture(milkyWay, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }
        let semaphore = inFlight
        command.addCompletedHandler { _ in semaphore.signal() }
        command.present(drawable)
        command.commit()
    }
}

#Preview("Night sea") {
    NightSeaView(
        camera: NightSeaCamera(), objects: [], selectedID: nil, moon: nil, equatorial: nil,
        isActive: false
    ).ignoresSafeArea()
        .preferredColorScheme(.dark)
}
