import SwiftUI
import AVFoundation
import simd

/// Garden in camera mode: the live back camera with the collected objects glowing on top,
/// each pinned to where it really is in the sky right now.
///
/// Uses the same AVFoundation + Core Motion pipeline as the collecting camera (true-north orientation,
/// the measured camera intrinsics and sensor orientation, and the calibrated compass correction in
/// `SkyFinderProjection.worldDirection`), so the overlay lines up with the real image.
struct GardenCameraLayer: View {
    let placed: [GardenPlacedObject]
    let selectedID: Int?
    var connections: [GardenConstellationConnection] = []
    var zodiacFigures: [GardenZodiacFigure] = []
    var equatorial: simd_double3x3?
    var isActive = true
    var onCameraUpdate: ((NightSeaCamera) -> Void)? = nil
    /// The onboarding tour's view of this camera (pose every frame, frozen frame on demand).
    let link: LiveCameraLink?
    let onSelect: (GardenCollectionItem) -> Void

    @State private var session = SkyCaptureSession()
    @State private var viewport: CGSize = .zero
    @State private var denied = false
    @Environment(\.scenePhase) private var phase

    private struct Sprite: Identifiable {
        let entry: GardenPlacedObject
        let point: CGPoint
        var id: Int { entry.id }

        var hitRadius: CGFloat {
            let scale: Double = entry.object.kind == .star ? 7.0 / 1.3 : 1.0
            return CGFloat(max(36, entry.object.radius * scale * 0.6))
        }

        var labelPosition: CGPoint {
            let scale: Double = entry.object.kind == .star ? 7.0 / 1.3 : 1.0
            let offset = entry.object.radius * scale * 0.45 + 16
            return CGPoint(x: point.x, y: point.y + CGFloat(offset))
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SkyCameraPreview(session:session,onViewport:{ size,_ in viewport = size; link?.viewport = size },
                    onPreviewingChanged:{ previewing in link?.previewChanged(previewing, from: session) })
                TimelineView(.animation(paused:!isActive)) { timeline in
                    let size = viewport == .zero ? geometry.size : viewport
                    let sprites = project(in:size)
                    ZStack {
                        GardenZodiacFigures(unlocked: zodiacFigures,
                            projected: projectZodiac(in: size), skyClip: zodiacSkyClip(in: size),
                            isActive: isActive)
                        GardenConstellationLines(connections: connections,
                            positions: Dictionary(uniqueKeysWithValues: sprites.map { ($0.id, $0.point) }),
                            isActive: isActive)
                        Canvas { context, _ in
                            for sprite in sprites { draw(sprite,in:&context) }
                        }
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                        ForEach(sprites) { sprite in
                            Button { onSelect(sprite.entry.item) } label: {
                                Text(sprite.entry.item.star.title)
                                    .font(.system(size:13,weight:.semibold)).foregroundStyle(.white)
                                    .shadow(color:.black.opacity(0.8),radius:3)
                                    .padding(.horizontal,8).padding(.vertical,6)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .position(sprite.labelPosition)
                            .accessibilityLabel("\(sprite.entry.item.star.title), collected \(sprite.entry.item.collectedDate)")
                        }
                    if let message = statusMessage {
                        Text(message).font(.system(size:12,weight:.medium)).foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal,14).padding(.vertical,8)
                            .glassEffect(.regular,in:Capsule())
                            .padding(.horizontal,32)
                            .frame(maxHeight:.infinity,alignment:.bottom).padding(.bottom,140)
                            .allowsHitTesting(false)
                    }
                    }
                    .onChange(of: timeline.date) { _, _ in
                        guard onCameraUpdate != nil, let frame = session.currentFrame, case .normal = frame.camera.trackingState else { return }
                        let freeze = WormholeFreeze.make(image: nil, size: size,
                            view: frame.camera.viewMatrix(viewRotationAngle: 90),
                            projection: frame.camera.projectionMatrix(viewRotationAngle: 90, viewportSize: size, zNear: 0.01, zFar: 2000),
                            alignment: simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)))
                        var pose = NightSeaCamera()
                        pose.orientation = freeze.orientation; pose.focalOverride = freeze.focal
                        onCameraUpdate?(pose)
                    }
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(SpatialTapGesture().onEnded { value in
                let size = viewport == .zero ? geometry.size : viewport
                let hits = project(in:size).map { ($0,hypot($0.point.x-value.location.x,$0.point.y-value.location.y)) }
                    .filter { $0.1 <= $0.0.hitRadius }
                if let hit = hits.min(by:{ $0.1 < $1.1 }) { onSelect(hit.0.entry.item) }
            })
        }
        .background(Color.black)
        .task { link?.connect(to: session); await start() }
        .onChange(of:isActive) { _, active in
            if active { run() }
            else { session.pause(); link?.sessionWasInterrupted(session) }
        }
        .onChange(of:phase) { _, value in
            if value == .active && isActive { run() }
            else if value == .background { session.pause(); link?.sessionWasInterrupted(session) }
        }
        .onDisappear { session.pause(); link?.disconnect(from: session) }
    }

    private var statusMessage: String? {
        if denied { return "Allow camera access in Settings to see your garden in the real sky." }
        guard let frame = session.currentFrame else { return "Starting the camera…" }
        if case .normal = frame.camera.trackingState { return nil }
        return "Move your phone slowly to line up the sky…"
    }

    // MARK: Session

    private func start() async {
        guard !AppPreviewData.isRunning else { return }
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for:.video) {
        case .authorized: granted = true
        case .notDetermined: granted = await AVCaptureDevice.requestAccess(for:.video)
        default: granted = false
        }
        guard granted else { denied = true; return }
        guard SkyCaptureSession.isSupported else {
            link?.session(session, didFailWithError: NSError(domain: "SkyCapture", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Camera or motion tracking is unavailable on this device."]))
            return
        }
        if isActive { run() }
    }
    private func run() {
        guard !denied, SkyCaptureSession.isSupported else { return }
        session.run()
    }

    // MARK: Projection (identical to the collecting camera)

    private func project(in size: CGSize) -> [Sprite] {
        guard size.width > 0, let frame = session.currentFrame, case .normal = frame.camera.trackingState else { return [] }
        let view = frame.camera.viewMatrix(viewRotationAngle:90)
        let projection = frame.camera.projectionMatrix(viewRotationAngle:90,viewportSize:size,zNear:0.01,zFar:2000)
        return placed.compactMap { entry in
            guard entry.object.isAboveHorizon else { return nil }
            let world = SkyFinderProjection.worldDirection(entry.object.direction)
            let local = view*SIMD4(world.x,world.y,world.z,0)
            guard local.z < 0 else { return nil }
            let clip = projection*SIMD4(local.x*1000,local.y*1000,local.z*1000,1)
            guard clip.w > 0 else { return nil }
            let x = CGFloat(clip.x/clip.w), y = CGFloat(clip.y/clip.w)
            guard abs(x) <= 1.3, abs(y) <= 1.3 else { return nil }
            return Sprite(entry:entry,point:CGPoint(x:(x+1)*size.width/2,y:(1-y)*size.height/2))
        }
    }

    // MARK: Drawing

    private func projectZodiac(in size: CGSize) -> [ProjectedConstellationFigure] {
        guard size.width > 0, size.height > 0, let frame = session.currentFrame,
            case .normal = frame.camera.trackingState else { return [] }
        let view = frame.camera.viewMatrix(viewRotationAngle: 90)
        let projection = frame.camera.projectionMatrix(viewRotationAngle: 90, viewportSize: size, zNear: 0.01, zFar: 2000)
        return GardenZodiacFigure.project(zodiacFigures, basis: equatorial, size: size) { direction in
            let world = SkyFinderProjection.worldDirection(direction)
            let local = view * SIMD4(world.x, world.y, world.z, 0)
            guard local.z < -0.06 else { return nil }
            let clip = projection * SIMD4(local.x * 1000, local.y * 1000, local.z * 1000, 1)
            guard clip.w > 0 else { return nil }
            return CGPoint(x: Double(clip.x / clip.w + 1) * size.width / 2,
                           y: Double(1 - clip.y / clip.w) * size.height / 2)
        }
    }

    private func zodiacSkyClip(in size: CGSize) -> [CGPoint] {
        guard size.width > 0, size.height > 0, let frame = session.currentFrame else { return [] }
        let inverse = simd_inverse(frame.camera.viewMatrix(viewRotationAngle: 90))
        let projection = frame.camera.projectionMatrix(viewRotationAngle: 90, viewportSize: size, zNear: 0.01, zFar: 2000)
        return GardenZodiacFigure.skyClip(size: size) { point in
            let x = Float(2 * point.x / size.width - 1) / projection.columns.0.x
            let y = Float(1 - 2 * point.y / size.height) / projection.columns.1.y
            return Double((inverse * SIMD4(x, y, -1, 0)).y)
        }
    }

    private func draw(_ sprite: Sprite,in context: inout GraphicsContext) {
        let object = sprite.entry.object
        let color = Color(red:object.color.x,green:object.color.y,blue:object.color.z)
        // Stars now carry the kit's core radius (x1.3); keep this camera overlay's original sprite size (x7).
        let radius = object.radius*(object.kind == .star ? 7/1.3 : 1)*1.15
        let p = sprite.point
        let disc = object.kind == .sun || object.kind == .moon
        // Soft halo
        let halo = Path(ellipseIn:CGRect(x:p.x-radius,y:p.y-radius,width:radius*2,height:radius*2))
        context.fill(halo,with:.radialGradient(Gradient(stops:[
            .init(color:color.opacity(0.9),location:0),
            .init(color:color.opacity(0.35),location:0.18),
            .init(color:color.opacity(0.1),location:0.5),
            .init(color:.clear,location:1)
        ]),center:p,startRadius:0,endRadius:radius))
        // Diffraction spikes on stars
        if object.kind == .star {
            let length = radius*0.8
            var spikes = Path()
            spikes.move(to:CGPoint(x:p.x-length,y:p.y)); spikes.addLine(to:CGPoint(x:p.x+length,y:p.y))
            spikes.move(to:CGPoint(x:p.x,y:p.y-length)); spikes.addLine(to:CGPoint(x:p.x,y:p.y+length))
            context.stroke(spikes,with:.color(color.opacity(0.45)),lineWidth:0.8)
        }
        // Bright core
        let core = disc ? radius*0.24 : max(2.2,radius*0.12)
        context.fill(Path(ellipseIn:CGRect(x:p.x-core,y:p.y-core,width:core*2,height:core*2)),with:.color(.white))
        if object.kind != .star, sprite.id == selectedID {
            let ring = radius*0.55
            context.stroke(Path(ellipseIn:CGRect(x:p.x-ring,y:p.y-ring,width:ring*2,height:ring*2)),with:.color(.white.opacity(0.9)),lineWidth:1.5)
        }
    }
}

#Preview("Garden camera") {
    GardenCameraLayer(placed:[],selectedID:nil,isActive:false,link:nil,onSelect:{ _ in })
        .preferredColorScheme(.dark)
}
