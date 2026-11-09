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
    var isActive = true
    let onSelect: (GardenCollectionItem) -> Void

    @State private var session = SkyCaptureSession()
    @State private var viewport: CGSize = .zero
    @State private var denied = false
    @Environment(\.scenePhase) private var phase

    private struct Sprite: Identifiable {
        let entry: GardenPlacedObject
        let point: CGPoint
        var id: Int { entry.id }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SkyCameraPreview(session:session,onViewport:{ size,_ in viewport = size })
                TimelineView(.animation(paused:!isActive)) { _ in
                    let size = viewport == .zero ? geometry.size : viewport
                    let sprites = project(in:size)
                    ZStack {
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
                            .position(x:sprite.point.x,y:sprite.point.y+sprite.entry.object.radius*(sprite.entry.object.kind == .star ? 7/1.3 : 1)*0.45+16)
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
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(SpatialTapGesture().onEnded { value in
                let size = viewport == .zero ? geometry.size : viewport
                let hits = project(in:size).map { ($0,hypot($0.point.x-value.location.x,$0.point.y-value.location.y)) }
                    .filter { $0.1 <= max(36,$0.0.entry.object.radius*($0.0.entry.object.kind == .star ? 7/1.3 : 1)*0.6) }
                if let hit = hits.min(by:{ $0.1 < $1.1 }) { onSelect(hit.0.entry.item) }
            })
        }
        .background(Color.black)
        .task { await start() }
        .onChange(of:isActive) { _, active in active ? run() : session.pause() }
        .onChange(of:phase) { _, value in
            if value == .active && isActive { run() }
            else if value == .background { session.pause() }
        }
        .onDisappear { session.pause() }
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
    GardenCameraLayer(placed:[],selectedID:nil,isActive:false,onSelect:{ _ in })
        .preferredColorScheme(.dark)
}
