import SwiftUI
import MetalKit
import ImageIO
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
    /// The NASA map, just a little under full strength (the user's pick).
    static let milkyWayStrength: Float = 0.85
    /// Kit look: crisp (a hair of softening only, to keep the map from shimmering).
    static let milkyWayLodBias = 0.3
    private let milkyWayStrength = NightSeaRenderer.milkyWayStrength
    private let milkyWay: MTLTexture
    private let queue: MTLCommandQueue
    private let seaPipeline: MTLRenderPipelineState
    private let pointPipeline: MTLRenderPipelineState
    private var layerTexture: MTLTexture?
    private var pointBuffer: MTLBuffer?
    private var pointCount = 0
    private var lastObjects: [NightSeaObject] = []
    private var lastSelected: Int?
    private let inFlight = DispatchSemaphore(value:2)
    // Touch ripples: 2D wave equation on a 256² height field (see NightSeaWater), fixed 60 Hz steps.
    private let rippleStep: MTLComputePipelineState
    private let rippleDrop: MTLComputePipelineState
    private var ripple: [MTLTexture]
    private var rippleClock: CFTimeInterval?
    private var rippleBacklog = 0.0
    static let rippleSize = 256
    #if DEBUG
    private var perf = (frames: 0, start: CACurrentMediaTime(), gpu: 0.0)
    #endif
    /// Shared by every Night Sea view (and the wormhole), so waves and twinkle never jump between them.
    static let clockOrigin = CACurrentMediaTime()
    private let start = NightSeaRenderer.clockOrigin
    private let reduceMotion = UIAccessibility.isReduceMotionEnabled
    // Kit palette: zenith #03051a, mid #0d1844, horizon #3a5d93.
    private let zenith = SIMD4<Float>(3/255,5/255,26/255,0)
    private let mid = SIMD4<Float>(13/255,24/255,68/255,0)
    private let horizon = SIMD4<Float>(58/255,93/255,147/255,0)

    init(view: MTKView) throws {
        guard let device = view.device, let queue = device.makeCommandQueue() else {
            throw NSError(domain:"NightSea",code:1,userInfo:[NSLocalizedDescriptionKey:"This device doesn’t support Metal."])
        }
        self.queue = queue
        let source = try String(contentsOf:SkyAssets.url("NightSeaShader",extension:"txt"),encoding:.utf8)
        let library = try device.makeLibrary(source:source,options:nil)
        let sea = MTLRenderPipelineDescriptor()
        sea.vertexFunction = library.makeFunction(name:"seaVertex")
        sea.fragmentFunction = library.makeFunction(name:"seaFragment")
        sea.colorAttachments[0].pixelFormat = view.colorPixelFormat
        seaPipeline = try device.makeRenderPipelineState(descriptor:sea)
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
        milkyWay = try Self.loadMilkyWay(device:device)
        guard let step = library.makeFunction(name:"rippleStep"), let drop = library.makeFunction(name:"rippleDrop") else {
            throw CocoaError(.featureUnsupported)
        }
        rippleStep = try device.makeComputePipelineState(function:step)
        rippleDrop = try device.makeComputePipelineState(function:drop)
        let n = Self.rippleSize
        let rd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.r32Float,width:n,height:n,mipmapped:false)
        rd.usage = [.shaderRead,.shaderWrite]
        rd.storageMode = .shared
        let zeros = [Float](repeating:0,count:n*n)
        ripple = try (0..<3).map { _ in
            guard let t = device.makeTexture(descriptor:rd) else { throw CocoaError(.featureUnsupported) }
            t.replace(region:MTLRegionMake2D(0,0,n,n),mipmapLevel:0,withBytes:zeros,bytesPerRow:n*4)
            return t
        }
        super.init()
    }

    /// RA/Dec Milky Way map from the Night Sea kit, downsampled to 2048 px wide with mipmaps.
    /// The kit's 4096×2048 map at full size, decoded into explicit RGBA bytes.
    /// (The old path went through an XRGB thumbnail: MTKTextureLoader then read the padding byte as BLUE,
    /// so every sample had blue = 1 and the whole sky and sea got a flat blue haze.)
    /// NASA/Goddard SVS "Deep Star Maps 2020" Milky Way (no point stars), aligned to RA/Dec by
    /// scripts/make_nasa_milky_way.swift. Credit in Resources/LICENSES.md.
    nonisolated static func loadMilkyWay(device: MTLDevice) throws -> MTLTexture {
        let url = try SkyAssets.url("garden-milky-way-nasa",extension:"jpg")
        guard let source = CGImageSourceCreateWithURL(url as CFURL,nil),
              let image = CGImageSourceCreateImageAtIndex(source,0,nil) else { throw CocoaError(.fileReadCorruptFile) }
        let width = image.width, height = image.height, rowBytes = width*4
        var bytes = [UInt8](repeating:0,count:rowBytes*height)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data:buffer.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:rowBytes,
                                          space:CGColorSpace(name:CGColorSpace.sRGB)!,
                                          bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue)
            else { return false }
            context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
            return true
        }
        guard drawn else { throw CocoaError(.fileReadCorruptFile) }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:width,height:height,mipmapped:true)
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor:descriptor), let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else { throw CocoaError(.featureUnsupported) }
        texture.replace(region:MTLRegionMake2D(0,0,width,height),mipmapLevel:0,withBytes:bytes,bytesPerRow:rowBytes)
        if let blit = command.makeBlitCommandEncoder() { blit.generateMipmaps(for:texture); blit.endEncoding() }
        command.commit(); command.waitUntilCompleted()
        return texture
    }

    func setObjects(_ objects: [NightSeaObject],selectedID: Int?) {
        guard objects != lastObjects || selectedID != lastSelected else { return }
        lastObjects = objects; lastSelected = selectedID
        let gpu = objects.map { object in
            GPUPoint(dirSize:SIMD4(Float(object.direction.x),Float(object.direction.y),Float(object.direction.z),Float(object.radius)),
                     color:SIMD4(Float(object.color.x),Float(object.color.y),Float(object.color.z),object.gpuKind+(object.id == selectedID && object.kind != .background ? 10 : 0)))
        }
        pointCount = gpu.count
        pointBuffer = gpu.isEmpty ? nil : queue.device.makeBuffer(bytes:gpu,length:gpu.count*MemoryLayout<GPUPoint>.stride,options:.storageModeShared)
    }

    func mtkView(_ view: MTKView,drawableSizeWillChange size: CGSize) { layerTexture = nil }

    private func layer(for size: CGSize) -> MTLTexture? {
        let width = max(1,Int(size.width)), height = max(1,Int(size.height))
        if let layerTexture, layerTexture.width == width, layerTexture.height == height { return layerTexture }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:width,height:height,mipmapped:false)
        descriptor.usage = [.renderTarget,.shaderRead]
        descriptor.storageMode = .private
        layerTexture = queue.device.makeTexture(descriptor:descriptor)
        return layerTexture
    }

    func draw(in view: MTKView) {
        guard inFlight.wait(timeout:.now()) == .success else { return }
        let size = view.drawableSize
        guard size.width > 0, let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
              let layer = layer(for:size), let command = queue.makeCommandBuffer() else { inFlight.signal(); return }
        let points = view.bounds.size
        let scale = size.width/max(points.width,1)
        let focal = camera.focalLength(in:points), center = camera.center(in:points)
        func v(_ d: SIMD3<Double>) -> SIMD4<Float> { SIMD4(Float(d.x),Float(d.y),Float(d.z),0) }
        let time = reduceMotion ? 0 : Float(CACurrentMediaTime()-start)
        var moonUp: Float = 0
        var moonVector = SIMD4<Float>(0,0,-1,0)
        if let moon {
            let altitudeDegrees = moon.direction.z*180 / .pi
            moonUp = Float(min(1,max(0,(altitudeDegrees+1)/3)))
            moonVector = SIMD4(Float(moon.direction.x),Float(moon.direction.y),Float(moon.direction.z),Float(moon.illumination))
        }
        let wave: Float = reduceMotion ? 0.06 : 0.14
        let res = SIMD4<Float>(Float(size.width),Float(size.height),Float(scale),time)
        let cam = SIMD4<Float>(Float(focal),Float(center.x),Float(center.y),wave)
        let flags = SIMD4<Float>(moonUp,moonUp*moonVector.w,1,equatorial == nil ? 0 : milkyWayStrength)
        let basis = equatorial ?? matrix_identity_double3x3
        // Mip level: texels per radian of the map vs. pixels per radian on screen.
        let texelsPerRadian = Double(milkyWay.width)/(2 * .pi)
        // +1.2 blurs the map's tiny background dots so they never read as collected stars.
        let lod = Float(max(0,log2(texelsPerRadian/max(1,focal*Double(scale))))+NightSeaRenderer.milkyWayLodBias)
        var e2 = v(basis.columns.2); e2.w = lod
        var uniforms = SeaUniforms(res:res,cam:cam,forward:v(camera.forward),right:v(camera.right),up:v(camera.up),
                                   zenith:zenith,mid:mid,horizon:horizon,moon:moonVector,flags:flags,
                                   e0:v(basis.columns.0),e1:v(basis.columns.1),e2:e2)

        // Pass 1: collected objects into the offscreen layer.
        let layerPass = MTLRenderPassDescriptor()
        layerPass.colorAttachments[0].texture = layer
        layerPass.colorAttachments[0].loadAction = .clear
        layerPass.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,0)
        layerPass.colorAttachments[0].storeAction = .store
        if let encoder = command.makeRenderCommandEncoder(descriptor:layerPass) {
            if let pointBuffer, pointCount > 0 {
                encoder.setRenderPipelineState(pointPipeline)
                encoder.setVertexBytes(&uniforms,length:MemoryLayout<SeaUniforms>.stride,index:0)
                encoder.setFragmentBytes(&uniforms,length:MemoryLayout<SeaUniforms>.stride,index:0)
                encoder.setVertexBuffer(pointBuffer,offset:0,index:1)
                encoder.drawPrimitives(type:.point,vertexStart:0,vertexCount:pointCount)
            }
            encoder.endEncoding()
        }
        #if DEBUG
        // Measuring only: launch with CELYX_NO_RIPPLES=1 to skip the ripple simulation.
        if ProcessInfo.processInfo.environment["CELYX_NO_RIPPLES"] == nil { stepRipples(command) }
        #else
        stepRipples(command)
        #endif

        // Pass 2: sky, islands and the sea that mirrors the layer.
        if let encoder = command.makeRenderCommandEncoder(descriptor:pass) {
            encoder.setRenderPipelineState(seaPipeline)
            encoder.setFragmentBytes(&uniforms,length:MemoryLayout<SeaUniforms>.stride,index:0)
            encoder.setFragmentTexture(layer,index:0)
            encoder.setFragmentTexture(milkyWay,index:1)
            encoder.setFragmentTexture(ripple[0],index:2)
            encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3)
            encoder.endEncoding()
        }
        let semaphore = inFlight
        #if DEBUG
        command.addCompletedHandler { [weak self] buffer in
            let gpu = buffer.gpuEndTime-buffer.gpuStartTime
            DispatchQueue.main.async { self?.logPerf(gpu:gpu) }
        }
        #endif
        command.addCompletedHandler { _ in semaphore.signal() }
        command.present(drawable)
        command.commit()
    }

    // MARK: Touch ripples

    /// Applies queued drops, then advances the wave equation at a fixed 60 Hz (at most 4 steps per frame).
    private func stepRipples(_ command: MTLCommandBuffer) {
        let now = CACurrentMediaTime()
        rippleBacklog = min(4,rippleBacklog+(now-(rippleClock ?? now))*60)
        rippleClock = now
        let n = Self.rippleSize
        let threads = MTLSize(width:8,height:8,depth:1)
        let groups = MTLSize(width:(n+7)/8,height:(n+7)/8,depth:1)
        let drops = NightSeaWater.shared.drain()
        if !drops.isEmpty, let encoder = command.makeComputeCommandEncoder() {
            let cell = NightSeaWater.span/Double(n)
            var gpu = drops.map { d -> SIMD4<Float> in
                SIMD4(Float((d.position.x/NightSeaWater.span+0.5)*Double(n)),Float((d.position.y/NightSeaWater.span+0.5)*Double(n)),
                      Float(max(0.8,d.radius/cell)),Float(d.height))
            }
            var count = UInt32(gpu.count)
            encoder.setComputePipelineState(rippleDrop)
            encoder.setTexture(ripple[0],index:0)
            encoder.setBytes(&gpu,length:MemoryLayout<SIMD4<Float>>.stride*gpu.count,index:0)
            encoder.setBytes(&count,length:4,index:1)
            encoder.dispatchThreadgroups(groups,threadsPerThreadgroup:threads)
            encoder.endEncoding()
        }
        // c = 0.9 m/s over 0.375 m cells at 60 Hz: courant 0.04; damping .985 per step (rings fade in ~3–4 s).
        let cell = NightSeaWater.span/Double(n), courant = 0.9*(1.0/60)/cell
        var params = SIMD4<Float>(Float(courant*courant),0.985,0,0)
        while rippleBacklog >= 1 {
            rippleBacklog -= 1
            guard let encoder = command.makeComputeCommandEncoder() else { break }
            encoder.setComputePipelineState(rippleStep)
            encoder.setTexture(ripple[0],index:0)        // current
            encoder.setTexture(ripple[1],index:1)        // previous
            encoder.setTexture(ripple[2],index:2)        // next
            encoder.setBytes(&params,length:MemoryLayout<SIMD4<Float>>.stride,index:0)
            encoder.dispatchThreadgroups(groups,threadsPerThreadgroup:threads)
            encoder.endEncoding()
            ripple = [ripple[2],ripple[0],ripple[1]]     // next becomes current, current becomes previous
        }
    }

    #if DEBUG
    /// Every ~2 s: average frame rate and GPU time per frame (read with `devicectl ... --console`).
    private func logPerf(gpu: Double) {
        perf.frames += 1; perf.gpu += gpu
        let elapsed = CACurrentMediaTime()-perf.start
        guard elapsed >= 2 else { return }
        print(String(format:"[NightSea] %.1f fps, GPU %.2f ms/frame",Double(perf.frames)/elapsed,perf.gpu/Double(perf.frames)*1000))
        perf = (0,CACurrentMediaTime(),0)
    }
    #endif
}

#Preview("Night sea") {
    NightSeaView(camera:NightSeaCamera(),objects:[],selectedID:nil,moon:nil,equatorial:nil,isActive:false).ignoresSafeArea()
        .preferredColorScheme(.dark)
}