import ARKit
import SwiftUI

struct SkyFinderView: View {
    let star: CatalogStar
    @State private var service: SkyFinderService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @Environment(\.openURL) private var openURL

    init(star: CatalogStar, location: ObserverLocation) {
        self.star = star
        _service = State(initialValue:SkyFinderService(star:star,location:location))
    }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea()
                    if service.isCameraRunning { SkyCameraPreview(session:service.session,onViewport:service.updateViewport) }
                    if let guide = service.projection, service.status == .tracking {
                        guidance(guide,size:geometry.size)
                    }
                    VStack(spacing:16) {
                        Spacer()
                        statusCard
                    }.padding(24)
                }
            }
            .navigationTitle("Find \(star.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden,for:.navigationBar)
            .toolbarColorScheme(.dark,for:.navigationBar)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button("Close",systemImage:"xmark") { dismiss() }.accessibilityLabel("Close sky finder")
                }
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .task { await service.start() }
        .onDisappear { service.stop() }
        .onChange(of:phase) { _, value in
            if value == .active { Task { await service.start() } } else { service.stop() }
        }
    }

    @ViewBuilder private var statusCard: some View {
        VStack(spacing:10) {
            switch service.status {
            case .preparing, .requestingPermission:
                ProgressView()
                Text("Getting the camera ready and finding north…")
            case .denied(let message):
                Label("We need your permission",systemImage:"camera.fill")
                Text(message).font(.subheadline)
                Button("Open Settings") { if let url = URL(string:UIApplication.openSettingsURLString) { openURL(url) } }
                    .buttonStyle(.borderedProminent)
            case .unavailable(let message):
                Label("Sky Camera isn’t available",systemImage:"camera.fill")
                Text(message).font(.subheadline)
            case .limited(let message):
                ProgressView()
                Text(message)
            case .tracking:
                if let altitude = service.altitude, altitude <= 0 {
                    Text("\(star.title) is below the horizon").font(.headline)
                    Text("It hasn’t risen where you are yet. Come back a little later.").font(.subheadline)
                } else if let guide = service.projection {
                    Text(guide.isAligned ? "You’re pointing the right way" : instruction(guide)).font(.headline)
                    Text(String(format:"%.0f° from where you’re pointing",guide.separation)).monospacedDigit()
                    Text("The marker points to its expected position. Your compass may be a little off.").font(.caption)
                }
            }
        }
        .multilineTextAlignment(.center)
        .padding(20).frame(maxWidth:.infinity)
        .background(.regularMaterial,in:RoundedRectangle(cornerRadius:22))
    }

    private func instruction(_ guide: SkyFinderProjection) -> String {
        if abs(guide.arrow.dx) > abs(guide.arrow.dy) { return guide.arrow.dx > 0 ? "Move your phone to the right" : "Move your phone to the left" }
        return guide.arrow.dy > 0 ? "Point a little lower" : "Point a little higher"
    }
    @ViewBuilder private func guidance(_ guide: SkyFinderProjection,size: CGSize) -> some View {
        if guide.isAligned, let point = guide.point {
            ZStack {
                Circle().stroke(.white.opacity(0.95),lineWidth:1).frame(width:16,height:16)
                Circle().fill(.white).frame(width:3,height:3)
            }
            .position(point).allowsHitTesting(false)
            .accessibilityLabel("Expected position of \(star.title)")
            Text(star.title).font(.caption).padding(.horizontal,8).padding(.vertical,4).background(.regularMaterial,in:Capsule())
                .position(x:point.x,y:point.y+22).allowsHitTesting(false)
        } else {
            Circle().stroke(.white.opacity(0.6),lineWidth:1).frame(width:32,height:32)
                .position(x:size.width/2,y:size.height/2).accessibilityHidden(true)
            let marginX = max(16,size.width/2-48)
            let marginY = max(16,size.height/2-180)
            let scale = min(marginX/max(abs(guide.arrow.dx),0.001),marginY/max(abs(guide.arrow.dy),0.001))
            Image(systemName:"arrow.up").font(.system(size:36,weight:.bold))
                .rotationEffect(.radians(atan2(guide.arrow.dy,guide.arrow.dx) + .pi/2))
                .padding(16).background(.regularMaterial,in:Circle())
                .position(x:size.width/2+guide.arrow.dx*scale,y:size.height/2+guide.arrow.dy*scale)
                .accessibilityLabel(instruction(guide))
        }
    }
}

struct SkyCameraPreview: UIViewRepresentable {
    let session: ARSession
    let onViewport: (CGSize,UIInterfaceOrientation) -> Void
    var onTap: ((CGPoint) -> Void)? = nil
    var onHold: ((CGPoint) -> Void)? = nil
    func makeUIView(context: Context) -> FinderCameraView {
        let view = FinderCameraView()
        view.session = session
        view.scene = SCNScene()
        view.viewportChanged = onViewport
        view.tapped = onTap; view.held = onHold
        view.installCameraGestures()
        return view
    }
    func updateUIView(_ view: FinderCameraView,context: Context) {
        view.tapped = onTap; view.held = onHold
        view.updateViewport()
    }
    static func dismantleUIView(_ view: FinderCameraView,coordinator: ()) { view.session.pause() }
}

final class FinderCameraView: ARSCNView {
    var viewportChanged: ((CGSize,UIInterfaceOrientation) -> Void)?
    var tapped: ((CGPoint) -> Void)?
    var held: ((CGPoint) -> Void)?
    func installCameraGestures() {
        let tap = UITapGestureRecognizer(target:self,action:#selector(didTap(_:)))
        let hold = UILongPressGestureRecognizer(target:self,action:#selector(didHold(_:)))
        hold.minimumPressDuration = 0.7
        tap.require(toFail:hold)
        addGestureRecognizer(tap); addGestureRecognizer(hold)
    }
    @objc private func didTap(_ gesture: UITapGestureRecognizer) { tapped?(gesture.location(in:self)) }
    @objc private func didHold(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { held?(gesture.location(in:self)) }
    }
    override func layoutSubviews() { super.layoutSubviews(); updateViewport() }
    func updateViewport() {
        let orientation = window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
        viewportChanged?(bounds.size,orientation)
    }
}
