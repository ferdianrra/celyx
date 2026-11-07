//
//  PanoramaView.swift
//  celyx
//
//  Created by Ferdiansyah Annora on 02/11/26.
//

import SwiftUI
import MetalKit
import ImageIO
import simd

/// A star placed in the personal garden sky. `direction` is in the scene's equatorial frame.
struct GardenSkyStar: Equatable {
    let id: Int
    let direction: SIMD3<Double>
    let magnitude: Double
    let color: SIMD3<Double>
}

struct PanoramaView: UIViewRepresentable {
    let scene: SkySceneState
    var isActive = true
    /// When set, only these stars are drawn instead of the full catalogue (Garden mode).
    var gardenStars: [GardenSkyStar]? = nil
    var onError: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> MTKView {
        let view = PanoramaMetalView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.clearColor = MTLClearColorMake(0.02, 0.02, 0.08, 1)
        view.preferredFramesPerSecond = 60
        view.framebufferOnly = true
        do {
            let renderer = try PanoramaRenderer(view: view)
            context.coordinator.renderer = renderer
            renderer.scene = scene
            renderer.setGardenStars(gardenStars)
            view.delegate = renderer
            updateRendering(view)
        } catch { DispatchQueue.main.async { onError(error.localizedDescription) } }
        return view
    }
    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.renderer?.scene = scene
        context.coordinator.renderer?.setGardenStars(gardenStars)
        updateRendering(view)
    }
    private func updateRendering(_ view: MTKView) {
        view.enableSetNeedsDisplay = scene.reduceMotion
        view.isPaused = !isActive || scene.reduceMotion
        if isActive && scene.reduceMotion { view.setNeedsDisplay() }
    }
    static func dismantleUIView(_ view: MTKView, coordinator: Coordinator) { view.isPaused = true; view.delegate = nil }
    final class Coordinator { var renderer: PanoramaRenderer? }
}

// Keep the GPU render target at most 2x points, rather than the screen's 3x.
// Re-evaluate after moving a preview/window between displays or rotating it.
private final class PanoramaMetalView: MTKView {
    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = min(traitCollection.displayScale, 2)
        if contentScaleFactor != scale { contentScaleFactor = scale }
        let size = CGSize(width: bounds.width*scale, height: bounds.height*scale)
        if drawableSize != size { drawableSize = size }
    }
}

private struct PanoramaUniforms {
    var camera: SIMD4<Float>
    var viewport: SIMD4<Float>
    var layers: SIMD4<Float>
    var eqX: SIMD4<Float>
    var eqY: SIMD4<Float>
    var eqZ: SIMD4<Float>
    var forward: SIMD4<Float>
    var right: SIMD4<Float>
    var up: SIMD4<Float>
    var conditions: SIMD4<Float>
    var sun: SIMD4<Float>
    var moon: SIMD4<Float>
    var starVisibility: SIMD4<Float>
}

private struct GPUStar {
    var directionMagnitude: SIMD4<Float>
    var color: SIMD4<Float>
}

@MainActor
final class PanoramaRenderer: NSObject, MTKViewDelegate {
    var scene = SkySceneState()
    private let queue: MTLCommandQueue
    private let backgroundPipeline: MTLRenderPipelineState
    private let starPipeline: MTLRenderPipelineState
    private let foregroundPipeline: MTLRenderPipelineState
    private let textures: [MTLTexture]
    private let starBuffer: MTLBuffer
    let starCount: Int
    private var gardenStars: [GardenSkyStar]?
    private var gardenBuffer: MTLBuffer?
    let textureByteCount: Int
    private let inFlight = DispatchSemaphore(value: 2)
    private let start = CACurrentMediaTime()

    init(view: MTKView) throws {
        guard let device = view.device, let queue = device.makeCommandQueue() else {
            throw NSError(domain: "Panorama", code: 1, userInfo: [NSLocalizedDescriptionKey: "This device doesn’t support Metal."])
        }
        self.queue = queue
        let shader = try String(contentsOf: SkyAssets.url("PanoramaShader", extension: "txt"), encoding: .utf8)
        let library = try device.makeLibrary(source: shader, options: nil)
        func pipeline(vertex: String = "panoramaVertex", fragment: String, blend: Bool = false, additive: Bool = false) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: vertex)
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = view.colorPixelFormat
            attachment.isBlendingEnabled = blend
            attachment.sourceRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationRGBBlendFactor = additive ? .one : .oneMinusSourceAlpha
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        backgroundPipeline = try pipeline(fragment: "panoramaFragment")
        starPipeline = try pipeline(vertex: "starVertex", fragment: "starFragment", blend: true, additive: true)
        foregroundPipeline = try pipeline(fragment: "foregroundFragment", blend: true)
        let loader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [.SRGB: false, .generateMipmaps: true,
            .origin: MTKTextureLoader.Origin.topLeft, .textureStorageMode: MTLStorageMode.private.rawValue]
        func load(_ name: String, _ ext: String, width: Int) throws -> MTLTexture {
            let url = try SkyAssets.url(name, extension: ext)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: width
                  ] as CFDictionary),
                  let context = CGContext(data: nil, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width*4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            else { throw CocoaError(.fileReadCorruptFile) }
            // Normalize indexed/16-bit source images to explicit 8-bit RGBA.
            // This also gives the foreground shader a known premultiplied-alpha format.
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard let rgba = context.makeImage() else { throw CocoaError(.fileReadCorruptFile) }
            return try loader.newTexture(cgImage: rgba, options: options)
        }
        let catalogue = try SkyAssets.stars()
        let stars = catalogue.map { star -> GPUStar in
            let ra = star.ra_deg * .pi/180, dec = star.dec_deg * .pi/180
            let p = SIMD3(cos(dec)*cos(ra),cos(dec)*sin(ra),sin(dec))
            let color = star.rgb
            return GPUStar(directionMagnitude: SIMD4(Float(p.x),Float(p.y),Float(p.z),Float(star.mag)),
                           color: SIMD4(Float(color.x),Float(color.y),Float(color.z),1))
        }
        guard let buffer = device.makeBuffer(bytes: stars, length: stars.count*MemoryLayout<GPUStar>.stride, options: .storageModeShared)
        else { throw CocoaError(.coderInvalidValue) }
        starBuffer = buffer
        starCount = stars.count
        catalogGPU = zip(catalogue.map(\.id),stars).map { ($0.0,$0.1) }
        textures = try [load("sky-gradient-360", "jpg", width: 1024),
                        load("milky-way-radec-4096", "jpg", width: 4096),
                        loader.newTexture(cgImage: Self.constellationImage(stars: catalogue), options: options),
                        load("sea-360", "png", width: 4096)]
        textureByteCount = textures.reduce(0) { $0+$1.allocatedSize }
        super.init()
    }

    private static func constellationImage(stars: [CatalogStar]) throws -> CGImage {
        let data = try Data(contentsOf: SkyAssets.url("constellations", extension: "json"))
        let entries = try JSONDecoder().decode([String: Constellation].self, from: data)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true; format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: CGSize(width: 2048, height: 1024), format: format).image { renderer in
            let c = renderer.cgContext
            c.setFillColor(UIColor.black.cgColor); c.fill(CGRect(x: 0,y: 0,width: 2048,height: 1024))
            func point(_ star: CatalogStar) -> CGPoint { CGPoint(x: star.ra_deg/360*2048, y: (90-star.dec_deg)/180*1024) }
            let indexed = Dictionary(uniqueKeysWithValues: stars.map { ($0.id,$0) })
            c.setStrokeColor(UIColor(red: 0.45,green: 0.65,blue: 0.9,alpha: 0.6).cgColor); c.setLineWidth(0.75)
            for entry in entries.values { for pair in entry.segments where pair.count == 2 {
                guard let a = indexed[pair[0]], let b = indexed[pair[1]] else { continue }
                var p = point(a); var q = point(b)
                if abs(p.x-q.x)>1024 { if p.x<q.x { p.x += 2048 } else { q.x += 2048 } }
                for shift in [-2048.0,0,2048] {
                    c.move(to: CGPoint(x:p.x+shift,y:p.y)); c.addLine(to: CGPoint(x:q.x+shift,y:q.y)); c.strokePath()
                }
            } }
        }.cgImage!
    }

    func setGardenStars(_ stars: [GardenSkyStar]?) {
        guard stars != gardenStars else { return }
        gardenStars = stars
        guard let stars, !stars.isEmpty else { gardenBuffer = nil; return }
        let gpu = stars.map { star in
            GPUStar(directionMagnitude: SIMD4(Float(star.direction.x),Float(star.direction.y),Float(star.direction.z),Float(star.magnitude)),
                    color: SIMD4(Float(star.color.x),Float(star.color.y),Float(star.color.z),1))
        }
        gardenBuffer = queue.device.makeBuffer(bytes: gpu, length: gpu.count*MemoryLayout<GPUStar>.stride, options: .storageModeShared)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    private func updateCollectionBuffer() {
        guard !appliedCollectionFilter || appliedIDs != scene.collectedIDs else { return }
        let values = catalogGPU.filter { scene.collectedIDs?.contains($0.0) ?? true }.map(\.1)
        if !values.isEmpty {
            guard let buffer = queue.device.makeBuffer(bytes:values,length:values.count*MemoryLayout<GPUStar>.stride,options:.storageModeShared) else { return }
            starBuffer = buffer
        }
        starCount = values.count
        appliedIDs = scene.collectedIDs; appliedCollectionFilter = true
    }
    func draw(in view: MTKView) {
        updateCollectionBuffer()
        guard inFlight.wait(timeout: .now()) == .success else { return }
        guard let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
              let command = queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            inFlight.signal(); return
        }
        let az = Float(scene.azimuth), alt = Float(scene.altitude)
        let forward = SIMD3(sin(az)*cos(alt),cos(az)*cos(alt),sin(alt))
        let right = SIMD3(cos(az),-sin(az),Float(0))
        let up = simd_cross(right,forward)
        let t = Float(CACurrentMediaTime()-start)
        let focal = Float(CameraProjection.focalLength(width: view.drawableSize.width, height: view.drawableSize.height, fieldOfView: scene.fieldOfView))
        func vector(_ p: SIMD3<Float>) -> SIMD4<Float> { SIMD4(p.x,p.y,p.z,0) }
        func doubleVector(_ p: SIMD3<Double>, w: Double = 0) -> SIMD4<Float> { SIMD4(Float(p.x),Float(p.y),Float(p.z),Float(w)) }
        var uniforms = PanoramaUniforms(camera: SIMD4(az,alt,Float(scene.fieldOfView),t),
            viewport: SIMD4(Float(view.drawableSize.width),Float(view.drawableSize.height),focal,Float(view.drawableSize.width/max(view.bounds.width,1))),
            layers: SIMD4(scene.showsMilkyWay && scene.collectedIDs == nil ? 1:0,scene.showsStars ? 1:0,scene.showsGrid ? 1:0,scene.showsConstellations && scene.collectedIDs == nil ? 1:0),
            eqX: doubleVector(scene.equatorialX),eqY: doubleVector(scene.equatorialY),eqZ: doubleVector(scene.equatorialZ),
            forward: vector(forward),right: vector(right),up: vector(up),
            conditions: SIMD4(Float(scene.limitingMagnitude),Float(scene.renderedExtinction),Float(scene.renderedCloudCover),scene.hasLocation ? 1:0),
            sun: doubleVector(scene.sunDirection),moon: doubleVector(scene.moonDirection,w:scene.moonIllumination),
            starVisibility: SIMD4(Float(scene.starLimitingMagnitude),Float(scene.spaceBlend),Float(scene.starExtinction),(scene.collectedIDs?.contains(CatalogStar.sun.id) ?? true) ? 1:0))
        encoder.setVertexBytes(&uniforms,length: MemoryLayout<PanoramaUniforms>.stride,index: 0)
        encoder.setFragmentBytes(&uniforms,length: MemoryLayout<PanoramaUniforms>.stride,index: 0)
        for (index,texture) in textures.enumerated() { encoder.setFragmentTexture(texture,index: index) }
        encoder.setRenderPipelineState(backgroundPipeline)
        encoder.drawPrimitives(type: .triangle,vertexStart: 0,vertexCount: 3)
        if scene.showsStars {
            if let gardenStars {
                if let gardenBuffer {
                    encoder.setRenderPipelineState(starPipeline)
                    encoder.setVertexBuffer(gardenBuffer,offset: 0,index: 1)
                    encoder.drawPrimitives(type: .point,vertexStart: 0,vertexCount: gardenStars.count)
                }
            } else {
                encoder.setRenderPipelineState(starPipeline)
                encoder.setVertexBuffer(starBuffer,offset: 0,index: 1)
                encoder.drawPrimitives(type: .point,vertexStart: 0,vertexCount: starCount)
            }
        }
        encoder.setRenderPipelineState(foregroundPipeline)
        encoder.drawPrimitives(type: .triangle,vertexStart: 0,vertexCount: 3)
        encoder.endEncoding()
        let semaphore = inFlight
        command.addCompletedHandler { _ in semaphore.signal() }
        command.present(drawable); command.commit()
    }
}

#Preview("360° Panorama") {
    PanoramaView(scene: SkySceneState()) { error in
        print("Panorama preview: \(error)")
    }
    .ignoresSafeArea()
    .preferredColorScheme(.dark)
}
