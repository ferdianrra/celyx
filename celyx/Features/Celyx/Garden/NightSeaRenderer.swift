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
struct NightSeaCamera: Equatable {
    /// Radians, from north toward east (drag mode).
    var azimuth: Double = 150 * .pi/180
    /// Radians above the horizon (drag mode).
    var altitude: Double = 18 * .pi/180
    /// Degrees (drag mode).
    var fieldOfView: Double = 72
    /// Device attitude: maps camera axes (x right, y up, z back) to [east, north, up].
    var orientation: simd_quatd?
    /// Back camera field of view along the sensor's long side, degrees.
    var cameraFieldOfView: Double = 69
    /// Pinch zoom on top of the real field of view.
    var zoom: Double = 1
    /// Exact focal length in points (wormhole handover), overriding the two modes above.
    var focalOverride: Double?
    /// Optical centre height as a fraction of the screen (wormhole handover).
    var centerYFraction: Double?

    var forward: SIMD3<Double> {
        if let orientation { return -orientation.act(SIMD3(0,0,1)) }
        return SIMD3(sin(azimuth)*cos(altitude),cos(azimuth)*cos(altitude),sin(altitude))
    }
    var right: SIMD3<Double> {
        if let orientation { return orientation.act(SIMD3(1,0,0)) }
        return SIMD3(cos(azimuth),-sin(azimuth),0)
    }
    var up: SIMD3<Double> {
        if let orientation { return orientation.act(SIMD3(0,1,0)) }
        return simd_cross(right,forward)
    }
    /// Compass heading of the view, radians.
    var heading: Double { let f = forward; return atan2(f.x,f.y) }

    func focalLength(in size: CGSize) -> Double {
        if let focalOverride { return focalOverride }
        guard orientation != nil else { return Double(min(size.width,size.height))*0.62/tan(fieldOfView * .pi/360) }
        // Aspect-fill a 4:3 sensor onto the screen, like the camera preview does.
        let long = Double(max(size.width,size.height)), short = Double(min(size.width,size.height))
        let halfLong = tan(cameraFieldOfView * .pi/360)
        let focal = long/short >= 4.0/3 ? (long/2)/halfLong : (short/2)/(halfLong*3/4)
        return focal*zoom
    }
    func center(in size: CGSize) -> CGPoint {
        CGPoint(x:size.width/2,y:size.height*(centerYFraction ?? (orientation == nil ? 0.47 : 0.5)))
    }

    /// Screen point (in points) of a horizon direction [east, north, up], or nil when behind the camera.
    func project(_ direction: SIMD3<Double>,in size: CGSize) -> CGPoint? {
        let f = forward, r = right, u = up
        let z = simd_dot(direction,f)
        guard z >= 0.06 else { return nil }
        let focal = focalLength(in:size), c = center(in:size)
        return CGPoint(x:c.x+simd_dot(direction,r)/z*focal,y:c.y-simd_dot(direction,u)/z*focal)
    }
}

/// One collected object placed in the sky.
struct NightSeaObject: Identifiable, Equatable {
    enum Kind: Float { case star = 0, planet = 1, moon = 2, sun = 3, background = 4 }
    let id: Int
    let direction: SIMD3<Double>
    /// Stars: core radius in points (the kit's starR, x1.3 for collected). Background stars: their magnitude.
    /// Planets, Moon, Sun: sprite radius in points (glow included).
    let radius: Double
    let color: SIMD3<Double>
    let kind: Kind
    var isAboveHorizon: Bool { direction.z > 0.002 }
    var gpuKind: Float { kind.rawValue }
    /// The kit's star radius (points) for a magnitude; collected stars use it x1.3.
    static func starRadius(magnitude: Double) -> Double { min(5,max(0.8,3.0-0.55*magnitude)) }
}

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
        let view = NightSeaMetalView(frame:.zero,device:MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        // The shader writes sRGB-encoded values (like the kit's WebGL canvas): say so, so iOS doesn't re-match them.
        (view.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name:CGColorSpace.sRGB)
        view.clearColor = MTLClearColorMake(0.01,0.02,0.07,1)
        view.preferredFramesPerSecond = 60
        view.framebufferOnly = true
        do {
            let renderer = try NightSeaRenderer(view:view)
            context.coordinator.renderer = renderer
            view.delegate = renderer
        } catch {
            DispatchQueue.main.async { onError(error.localizedDescription) }
        }
        updateUIView(view,context:context)
        return view
    }
    func updateUIView(_ view: MTKView,context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        renderer.camera = camera
        renderer.setObjects(objects,selectedID:selectedID)
        renderer.moon = moon
        renderer.equatorial = equatorial
        view.isPaused = !isActive
    }
    static func dismantleUIView(_ view: MTKView,coordinator: Coordinator) { view.isPaused = true; view.delegate = nil }
    final class Coordinator { var renderer: NightSeaRenderer? }
}

/// Caps the render target at 2× like the kit (the sea pass is a full-screen shader).
private final class NightSeaMetalView: MTKView {
    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = min(traitCollection.displayScale,2)
        if contentScaleFactor != scale { contentScaleFactor = scale }
    }
}

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
    /// Kit value: the full Milky Way (colour graded in the map itself).
    static let milkyWayStrength: Float = 1
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
        super.init()
    }

    /// RA/Dec Milky Way map from the Night Sea kit, downsampled to 2048 px wide with mipmaps.
    /// The kit's 4096×2048 map at full size, decoded into explicit RGBA bytes.
    /// (The old path went through an XRGB thumbnail: MTKTextureLoader then read the padding byte as BLUE,
    /// so every sample had blue = 1 and the whole sky and sea got a flat blue haze.)
    static func loadMilkyWay(device: MTLDevice) throws -> MTLTexture {
        let url = try SkyAssets.url("garden-milky-way-radec",extension:"jpg")
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
        // Pass 2: sky, islands and the sea that mirrors the layer.
        if let encoder = command.makeRenderCommandEncoder(descriptor:pass) {
            encoder.setRenderPipelineState(seaPipeline)
            encoder.setFragmentBytes(&uniforms,length:MemoryLayout<SeaUniforms>.stride,index:0)
            encoder.setFragmentTexture(layer,index:0)
            encoder.setFragmentTexture(milkyWay,index:1)
            encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3)
            encoder.endEncoding()
        }
        let semaphore = inFlight
        command.addCompletedHandler { _ in semaphore.signal() }
        command.present(drawable)
        command.commit()
    }
}

#Preview("Night sea") {
    NightSeaView(camera:NightSeaCamera(),objects:[],selectedID:nil,moon:nil,equatorial:nil,isActive:false).ignoresSafeArea()
        .preferredColorScheme(.dark)
}
