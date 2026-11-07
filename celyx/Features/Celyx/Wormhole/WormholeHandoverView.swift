//  WormholeHandoverView.swift
//  Full-screen Metal view of the wormhole: one fragment pass over the frozen camera frame,
//  with the Night Sea (the garden's own shader code) seen through the hole.

import SwiftUI
import MetalKit
import simd

/// What the Night Sea holds while the wormhole opens (same placement the garden uses).
struct WormholeScene {
    var objects: [NightSeaObject] = []
    /// The object just collected: it fades in at landing.
    var newID: Int?
    var moon: (direction: SIMD3<Double>, illumination: Double)?
    var equatorial: simd_double3x3?
}

struct WormholeHandoverView: View {
    let handover: WormholeHandover

    var body: some View {
        ZStack {
            // Shown until Metal presents its first frame, so the swap from the live camera is invisible.
            if let image = handover.freeze.image {
                Image(decorative:image,scale:1).resizable().scaledToFill()
            } else {
                CelyxColor.night
            }
            WormholeMetalView(handover:handover)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WormholeMetalView: UIViewRepresentable {
    let handover: WormholeHandover

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> MTKView {
        let view = WormholeMTKView(frame:.zero,device:MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 120
        view.isOpaque = false
        view.backgroundColor = .clear
        view.layer.isOpaque = false
        view.clearColor = MTLClearColorMake(0,0,0,0)
        if let renderer = try? WormholeRenderer(view:view,handover:handover) {
            context.coordinator.renderer = renderer
            view.delegate = renderer
        }
        return view
    }
    func updateUIView(_ view: MTKView,context: Context) {}
    static func dismantleUIView(_ view: MTKView,coordinator: Coordinator) { view.isPaused = true; view.delegate = nil }
    final class Coordinator { var renderer: WormholeRenderer? }
}

/// Same 2× cap as the Night Sea view, so the cross into the garden is pixel-identical.
private final class WormholeMTKView: MTKView {
    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = min(traitCollection.displayScale,2)
        if contentScaleFactor != scale { contentScaleFactor = scale }
    }
}

// Mirrors SeaUniforms in NightSeaShader.txt.
private struct WormSeaUniforms {
    var res, cam, forward, right, up, zenith, mid, horizon, moon, flags, e0, e1, e2: SIMD4<Float>
}
private struct WormUniforms {
    var wh, ew, wave, fx, camT, scr: SIMD4<Float>
}
private struct WormPoint {
    var dirSize: SIMD4<Float>
    var color: SIMD4<Float>
}

@MainActor
final class WormholeRenderer: NSObject, MTKViewDelegate {
    private let handover: WormholeHandover
    private let queue: MTLCommandQueue
    private let pointPipeline: MTLRenderPipelineState
    private let wormPipeline: MTLRenderPipelineState
    private let milkyWay: MTLTexture
    private let cameraTexture: MTLTexture
    private var others: (buffer: MTLBuffer?, count: Int) = (nil,0)
    private var fresh: (buffer: MTLBuffer?, count: Int) = (nil,0)
    private var layers: (MTLTexture,MTLTexture)?
    private let inFlight = DispatchSemaphore(value:2)
    private let milkyWayStrength: Float = 0.26
    private let zenith = SIMD4<Float>(3/255,5/255,26/255,0)
    private let mid = SIMD4<Float>(13/255,24/255,68/255,0)
    private let horizon = SIMD4<Float>(58/255,93/255,147/255,0)

    init(view: MTKView,handover: WormholeHandover) throws {
        guard let device = view.device, let queue = device.makeCommandQueue() else { throw CocoaError(.featureUnsupported) }
        self.handover = handover
        self.queue = queue
        let sea = try String(contentsOf:SkyAssets.url("NightSeaShader",extension:"txt"),encoding:.utf8)
        let wormhole = try String(contentsOf:SkyAssets.url("WormholeShader",extension:"txt"),encoding:.utf8)
        let source = sea+"\n"+wormhole
        let library = try device.makeLibrary(source:source,options:nil)
        let points = MTLRenderPipelineDescriptor()
        points.vertexFunction = library.makeFunction(name:"gardenPointVertex")
        points.fragmentFunction = library.makeFunction(name:"gardenPointFragment")
        let attachment = points.colorAttachments[0]!
        attachment.pixelFormat = .rgba8Unorm
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pointPipeline = try device.makeRenderPipelineState(descriptor:points)
        let worm = MTLRenderPipelineDescriptor()
        worm.vertexFunction = library.makeFunction(name:"seaVertex")
        worm.fragmentFunction = library.makeFunction(name:"wormholeFragment")
        worm.colorAttachments[0].pixelFormat = view.colorPixelFormat
        wormPipeline = try device.makeRenderPipelineState(descriptor:worm)
        milkyWay = try NightSeaRenderer.loadMilkyWay(device:device)
        let loader = MTKTextureLoader(device:device)
        if let image = handover.freeze.image {
            cameraTexture = try loader.newTexture(cgImage:image,options:[.SRGB:false,.textureStorageMode:MTLStorageMode.private.rawValue])
        } else {
            // Night-blue placeholder frame (Simulator / no camera).
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:1,height:1,mipmapped:false)
            guard let texture = device.makeTexture(descriptor:descriptor) else { throw CocoaError(.featureUnsupported) }
            var pixel: [UInt8] = [6,10,30,255]
            texture.replace(region:MTLRegionMake2D(0,0,1,1),mipmapLevel:0,withBytes:&pixel,bytesPerRow:4)
            cameraTexture = texture
        }
        super.init()
        let scene = handover.scene
        func gpu(_ list: [NightSeaObject]) -> (MTLBuffer?,Int) {
            let points = list.map { o in
                WormPoint(dirSize:SIMD4(Float(o.direction.x),Float(o.direction.y),Float(o.direction.z),Float(o.radius)),
                          color:SIMD4(Float(o.color.x),Float(o.color.y),Float(o.color.z),o.kind.rawValue))
            }
            guard !points.isEmpty else { return (nil,0) }
            return (device.makeBuffer(bytes:points,length:points.count*MemoryLayout<WormPoint>.stride,options:.storageModeShared),points.count)
        }
        others = gpu(scene.objects.filter { $0.id != scene.newID })
        fresh = gpu(scene.objects.filter { $0.id == scene.newID })
    }

    func mtkView(_ view: MTKView,drawableSizeWillChange size: CGSize) { layers = nil }

    private func layerTextures(_ size: CGSize) -> (MTLTexture,MTLTexture)? {
        let width = max(1,Int(size.width)), height = max(1,Int(size.height))
        if let layers, layers.0.width == width, layers.0.height == height { return layers }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:width,height:height,mipmapped:false)
        descriptor.usage = [.renderTarget,.shaderRead]
        descriptor.storageMode = .private
        guard let a = queue.device.makeTexture(descriptor:descriptor), let b = queue.device.makeTexture(descriptor:descriptor) else { return nil }
        layers = (a,b)
        return layers
    }

    func draw(in view: MTKView) {
        guard inFlight.wait(timeout:.now()) == .success else { return }
        let size = view.drawableSize
        guard size.width > 0, let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
              let (layerA,layerB) = layerTextures(size), let command = queue.makeCommandBuffer() else { inFlight.signal(); return }
        let points = view.bounds.size
        let scale = Float(size.width/max(points.width,1))
        let tt = handover.tt()
        let f = handover.frame(tt)
        let pin = handover.pinhole(tt,frame:f)
        var camera = NightSeaCamera()
        camera.orientation = pin.orientation
        camera.focalOverride = pin.focal
        camera.centerYFraction = pin.centerY
        let center = camera.center(in:points)
        func v(_ d: SIMD3<Double>) -> SIMD4<Float> { SIMD4(Float(d.x),Float(d.y),Float(d.z),0) }
        let scene = handover.scene
        var moonUp: Float = 0
        var moonVector = SIMD4<Float>(0,0,-1,0)
        if let moon = scene.moon {
            moonUp = Float(min(1,max(0,(moon.direction.z*180 / .pi+1)/3)))
            moonVector = SIMD4(Float(moon.direction.x),Float(moon.direction.y),Float(moon.direction.z),Float(moon.illumination))
        }
        let basis = scene.equatorial ?? matrix_identity_double3x3
        let texelsPerRadian = Double(milkyWay.width)/(2 * .pi)
        let lod = Float(max(0,log2(texelsPerRadian/max(1,pin.focal*Double(scale))))+1.2)
        var e2 = v(basis.columns.2); e2.w = lod
        let time = Float(CACurrentMediaTime()-NightSeaRenderer.clockOrigin)
        var sea = WormSeaUniforms(res:SIMD4(Float(size.width),Float(size.height),scale,time),
                                  cam:SIMD4(Float(pin.focal),Float(center.x),Float(center.y),0.14),
                                  forward:v(camera.forward),right:v(camera.right),up:v(camera.up),
                                  zenith:zenith,mid:mid,horizon:horizon,moon:moonVector,
                                  flags:SIMD4(moonUp,moonUp*moonVector.w,1,scene.equatorial == nil ? 0 : milkyWayStrength),
                                  e0:v(basis.columns.0),e1:v(basis.columns.1),e2:e2)
        var worm = WormUniforms(wh:SIMD4(Float(f.center.x),Float(f.center.y),Float(f.R),1),
                                ew:SIMD4(Float(f.E),Float(f.W),Float(f.swirl),Float(f.blur)),
                                wave:SIMD4(Float(f.waveR),Float(f.waveA),Float(f.waveW),Float(f.glow)),
                                fx:SIMD4(Float(f.grain),Float(f.star),Float(f.expo),0),
                                camT:SIMD4(Float(pin.imageShift.dx),Float(pin.imageShift.dy),Float(pin.imageScale),0),
                                scr:SIMD4(Float(points.width),Float(points.height),Float(points.width/2),Float(points.height/2)))

        // Pinhole object layers: the collection, and the new star separately so it can fade in at landing.
        for (target,list) in [(layerA,others),(layerB,fresh)] {
            let layerPass = MTLRenderPassDescriptor()
            layerPass.colorAttachments[0].texture = target
            layerPass.colorAttachments[0].loadAction = .clear
            layerPass.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,0)
            layerPass.colorAttachments[0].storeAction = .store
            guard let encoder = command.makeRenderCommandEncoder(descriptor:layerPass) else { continue }
            if let buffer = list.buffer, list.count > 0 {
                encoder.setRenderPipelineState(pointPipeline)
                encoder.setVertexBytes(&sea,length:MemoryLayout<WormSeaUniforms>.stride,index:0)
                encoder.setFragmentBytes(&sea,length:MemoryLayout<WormSeaUniforms>.stride,index:0)
                encoder.setVertexBuffer(buffer,offset:0,index:1)
                encoder.drawPrimitives(type:.point,vertexStart:0,vertexCount:list.count)
            }
            encoder.endEncoding()
        }
        if let encoder = command.makeRenderCommandEncoder(descriptor:pass) {
            encoder.setRenderPipelineState(wormPipeline)
            encoder.setFragmentBytes(&sea,length:MemoryLayout<WormSeaUniforms>.stride,index:0)
            encoder.setFragmentBytes(&worm,length:MemoryLayout<WormUniforms>.stride,index:1)
            encoder.setFragmentTexture(layerA,index:0)
            encoder.setFragmentTexture(milkyWay,index:1)
            encoder.setFragmentTexture(cameraTexture,index:2)
            encoder.setFragmentTexture(layerB,index:3)
            encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3)
            encoder.endEncoding()
        }
        let semaphore = inFlight
        command.addCompletedHandler { _ in semaphore.signal() }
        command.present(drawable)
        command.commit()
    }
}
