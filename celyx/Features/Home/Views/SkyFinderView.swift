import ARKit
import SceneKit
import SwiftUI

struct SkyFinderView: View {
    let star: CatalogStar
    let referenceStars: [CatalogStar]
    @State private var showsAlignment = false
    @State private var service: SkyFinderService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @Environment(\.openURL) private var openURL

    init(star: CatalogStar, location: ObserverLocation,alignment: CameraSkyAlignment? = nil,catalogue: [CatalogStar] = []) {
        self.star = star
        let references = [star,CatalogStar.sun,CatalogStar.moon] + CatalogStar.planets + catalogue.filter(\.hasCommonName)
        referenceStars = Dictionary(references.map { ($0.id,$0) },uniquingKeysWith:{ first,_ in first }).values.sorted { $0.title < $1.title }
        _service = State(initialValue:SkyFinderService(star:star,location:location,alignment:alignment))
    }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea()
                    if service.isCameraRunning {
                        SkyCameraPreview(session:service.session,onViewport:service.updateViewport,
                            skyMarkers:service.targetMarker.map { [$0] } ?? [],labeledMarkerIDs:[star.id],zoom:service.cameraZoom)
                    }
                    if let guide = service.projection, service.status == .tracking {
                        guidance(guide,size:geometry.size)
                    }
                    VStack(spacing:16) {
                        Spacer()
                        statusCard
                    }.padding(.horizontal,24).padding(.bottom,max(24,geometry.safeAreaInsets.bottom+12))
                }
            }
            .ignoresSafeArea()
            .navigationTitle(star.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden,for:.navigationBar)
            .toolbarColorScheme(.dark,for:.navigationBar)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button("Close",systemImage:"xmark") { dismiss() }.accessibilityLabel("Close sky finder")
                }
                ToolbarItem(placement:.topBarTrailing) { Button("Align",systemImage:"scope") { showsAlignment = true } }
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .sheet(isPresented:$showsAlignment) { CameraAlignmentView(service:service,stars:referenceStars,initialStar:star) }
        .task { await service.start() }
        .onDisappear { service.stop() }
        .onChange(of:phase) { _, value in
            if value == .active { Task { await service.start() } }
            else if value == .background { service.suspendForBackground() }
            else { service.stop() }
        }
    }

    @ViewBuilder private var statusCard: some View {
        VStack(spacing:10) {
            CameraRecalibrationNotice(service:service) { showsAlignment = true }
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
                if service.alignment.requiresCalibration {
                    Text("Sky positions are paused until calibration.").font(.caption)
                } else if let altitude = service.altitude, altitude <= 0 {
                    Text("\(star.title) is below the horizon").font(.headline)
                    Text("It isn’t above your horizon right now. You can check again later.").font(.subheadline)
                } else if let guide = service.projection {
                    Text(guide.isAligned ? "Near the expected direction" : instruction(guide)).font(.headline)
                    Text(String(format:"%.0f° from where you’re pointing",guide.separation)).monospacedDigit()
                    Text(service.alignment.reference.map { "Aligned using \($0). This still shows an expected position." } ?? "If the marker is off, tap Align and mark a known object.").font(.caption)
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
        if !guide.isAligned {
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
    var onExposureDrag: ((CGFloat,CGPoint,Bool) -> Void)? = nil
    var skyMarkers: [CameraSkyPrediction] = []
    var labeledMarkerIDs: Set<Int> = []
    var selectedMarkerID: Int? = nil
    var onSelectMarker: ((Int) -> Void)? = nil
    var markerColor: UIColor = .systemCyan
    var markerTitlePrefix = ""
    var zoom: Double = 1
    func makeUIView(context: Context) -> FinderCameraContainer {
        let container = FinderCameraContainer()
        container.zoom = zoom
        let view = container.cameraView
        view.session = session
        view.scene = SCNScene()
        view.preferredFramesPerSecond = 60
        view.onSelectMarker = onSelectMarker
        view.markerColor = markerColor; view.markerTitlePrefix = markerTitlePrefix
        view.viewportChanged = onViewport
        view.tapped = onTap; view.held = onHold; view.exposureDragged = onExposureDrag
        view.installCameraGestures()
        return container
    }
    func updateUIView(_ container: FinderCameraContainer,context: Context) {
        container.zoom = zoom
        let view = container.cameraView
        view.tapped = onTap; view.held = onHold; view.exposureDragged = onExposureDrag
        view.onSelectMarker = onSelectMarker
        view.markerColor = markerColor; view.markerTitlePrefix = markerTitlePrefix
        view.updateSkyMarkers(skyMarkers,labeledIDs:labeledMarkerIDs,selectedID:selectedMarkerID)
        view.updateViewport()
    }
    static func dismantleUIView(_ view: FinderCameraContainer,coordinator: ()) { view.cameraView.isPlaying = false }
}

/// Scale the entire AR composite, keeping the camera image and world markers together.
/// ARKit continues to own its camera projection and capture-device configuration.
final class FinderCameraContainer: UIView {
    let cameraView = FinderCameraView()
    var zoom: Double = 1 { didSet { updateCameraLayout() } }
    override init(frame: CGRect) {
        super.init(frame:frame)
        clipsToBounds = true
        addSubview(cameraView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() { super.layoutSubviews(); updateCameraLayout() }
    private func updateCameraLayout() {
        cameraView.bounds = CGRect(origin:.zero,size:bounds.size)
        cameraView.center = CGPoint(x:bounds.midX,y:bounds.midY)
        let scale = CGFloat(CameraZoom.clamped(zoom))
        cameraView.transform = CGAffineTransform(scaleX:scale,y:scale)
    }
}

final class FinderCameraView: ARSCNView {
    var viewportChanged: ((CGSize,UIInterfaceOrientation) -> Void)?
    var tapped: ((CGPoint) -> Void)?
    var held: ((CGPoint) -> Void)?
    var exposureDragged: ((CGFloat,CGPoint,Bool) -> Void)?
    var onSelectMarker: ((Int) -> Void)?
    var markerColor: UIColor = .systemCyan
    var markerTitlePrefix = ""
    private var skyNodes: [Int:SCNNode] = [:]
    private var exposurePanActive = false

    // SceneKit projects these world-space nodes with the camera on every render frame.
    // At 1 km, a small step barely changes their apparent celestial direction.
    func updateSkyMarkers(_ markers: [CameraSkyPrediction],labeledIDs: Set<Int>,selectedID: Int?) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        let ids = Set(markers.map(\.id))
        for id in Array(skyNodes.keys) where !ids.contains(id) {
            skyNodes.removeValue(forKey:id)?.removeFromParentNode()
        }
        for marker in markers {
            let node: SCNNode
            if let existing = skyNodes[marker.id] { node = existing }
            else {
                node = makeSkyMarker(marker)
                scene.rootNode.addChildNode(node)
                skyNodes[marker.id] = node
            }
            node.simdPosition = simd_normalize(marker.direction)*1000
            node.childNode(withName:"label",recursively:false)?.isHidden = !labeledIDs.contains(marker.id)
            node.childNode(withName:"ring",recursively:false)?.simdScale = SIMD3(repeating:marker.id == selectedID ? 1.2 : 1)
        }
        pointOfView?.camera?.zFar = 2000
        SCNTransaction.commit()
    }

    private func makeSkyMarker(_ marker: CameraSkyPrediction) -> SCNNode {
        let root = SCNNode()
        root.name = "sky:\(marker.id)"
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        root.constraints = [billboard]
        func plane(image: UIImage,width: CGFloat,height: CGFloat) -> SCNNode {
            let geometry = SCNPlane(width:width,height:height)
            geometry.firstMaterial?.diffuse.contents = image
            geometry.firstMaterial?.lightingModel = .constant
            geometry.firstMaterial?.isDoubleSided = true
            geometry.firstMaterial?.writesToDepthBuffer = false
            return SCNNode(geometry:geometry)
        }
        let color = markerColor
        let ringImage = UIGraphicsImageRenderer(size:CGSize(width:64,height:64)).image { context in
            color.setStroke()
            context.cgContext.setLineWidth(3)
            context.cgContext.strokeEllipse(in:CGRect(x:3,y:3,width:58,height:58))
        }
        let ring = plane(image:ringImage,width:28,height:28)
        ring.name = "ring"
        root.addChildNode(ring)
        let font = UIFont.systemFont(ofSize:24,weight:.medium)
        let attributes: [NSAttributedString.Key:Any] = [.font:font,.foregroundColor:color]
        let title = (markerTitlePrefix+marker.star.title) as NSString
        let size = CGSize(width:ceil(title.size(withAttributes:attributes).width)+24,height:42)
        let image = UIGraphicsImageRenderer(size:size).image { _ in
            UIColor.black.withAlphaComponent(0.65).setFill()
            UIBezierPath(roundedRect:CGRect(origin:.zero,size:size),cornerRadius:21).fill()
            title.draw(at:CGPoint(x:12,y:6),withAttributes:attributes)
        }
        let label = plane(image:image,width:size.width*0.65,height:size.height*0.65)
        label.name = "label"
        label.position.y = -32
        root.addChildNode(label)
        return root
    }

    func installCameraGestures() {
        let tap = UITapGestureRecognizer(target:self,action:#selector(didTap(_:)))
        let hold = UILongPressGestureRecognizer(target:self,action:#selector(didHold(_:)))
        hold.minimumPressDuration = 0.7
        tap.require(toFail:hold)
        addGestureRecognizer(tap); addGestureRecognizer(hold)
        if exposureDragged != nil {
            let pan = UIPanGestureRecognizer(target:self,action:#selector(didDragExposure(_:)))
            pan.minimumNumberOfTouches = 1; pan.maximumNumberOfTouches = 1
            tap.require(toFail:pan)
            addGestureRecognizer(pan)
        }
    }
    @objc private func didDragExposure(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in:superview ?? self)
        let location = gesture.location(in:superview ?? self)
        let start = CGPoint(x:location.x-translation.x,y:location.y-translation.y)
        switch gesture.state {
        case .began:
            let velocity = gesture.velocity(in:self)
            exposurePanActive = abs(velocity.y) > abs(velocity.x)
            if exposurePanActive { exposureDragged?(translation.y,start,false) }
        case .changed:
            if exposurePanActive { exposureDragged?(translation.y,start,false) }
        case .ended,.cancelled,.failed:
            if exposurePanActive { exposureDragged?(translation.y,start,true) }
            exposurePanActive = false
        default: break
        }
    }
    @objc private func didTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in:self)
        if onSelectMarker != nil {
            for hit in hitTest(point,options:nil) {
                var node: SCNNode? = hit.node
                while let current = node {
                    if let name = current.name, name.hasPrefix("sky:"),let id = Int(name.dropFirst(4)) {
                        onSelectMarker?(id); return
                    }
                    node = current.parent
                }
            }
        }
        tapped?(convert(point,to:superview))
    }
    @objc private func didHold(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { held?(convert(gesture.location(in:self),to:superview)) }
    }
    override func layoutSubviews() { super.layoutSubviews(); updateViewport() }
    func updateViewport() {
        let orientation = window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
        viewportChanged?(bounds.size,orientation)
    }
}

/// Optional preview of filtered sky positions; kept separate from optical collection evidence.
struct VisibleSkyARView: View {
    let model: HomeViewModel
    @State private var showsAlignment = false
    @State private var service: SkyFinderService
    @State private var selectedID: Int?
    @State private var zoomStart: Double?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @Environment(\.openURL) private var openURL

    init(model: HomeViewModel) {
        self.model = model
        _service = State(initialValue:SkyFinderService(location:model.location,catalogue:model.stars,showsPredictions:true,alignment:model.cameraAlignment))
        _selectedID = State(initialValue:model.predictedVisibleObjects.first?.id)
    }
    private var target: CameraSkyPrediction? {
        if let selectedID { return service.predictions.first { $0.id == selectedID } }
        return service.predictions.min { $0.guide.separation < $1.guide.separation }
    }
    private var worldMarkers: [CameraSkyPrediction] {
        guard service.status == .tracking else { return [] }
        var markers = Array(service.predictions.prefix(160))
        var ids = Set(markers.map(\.id))
        for marker in labeledPredictions where ids.insert(marker.id).inserted { markers.append(marker) }
        if let selectedID, !markers.contains(where:{ $0.id == selectedID }),
           let selected = service.predictions.first(where:{ $0.id == selectedID }) { markers.append(selected) }
        return markers
    }
    private var labeledPredictions: [CameraSkyPrediction] {
        var points: [CGPoint] = []
        return service.predictions.sorted {
            if $0.id == $1.id { return false }
            if $0.id == selectedID { return true }
            if $1.id == selectedID { return false }
            return $0.guide.separation < $1.guide.separation
        }
            .filter { prediction in
                guard let point = prediction.guide.point, points.count < 12,
                      !points.contains(where:{ hypot($0.x-point.x,$0.y-point.y) < 65 }) else { return false }
                points.append(point); return true
            }
    }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    Color.black
                    if service.isCameraRunning {
                        SkyCameraPreview(session:service.session,onViewport:service.updateViewport,
                            onTap:{ _ = service.focus(at:$0) },
                            skyMarkers:worldMarkers,labeledMarkerIDs:Set(labeledPredictions.map(\.id)),
                            selectedMarkerID:selectedID,onSelectMarker:{ selectedID = $0 },zoom:service.cameraZoom)
                            .simultaneousGesture(MagnifyGesture().onChanged { value in
                                if zoomStart == nil { zoomStart = service.cameraZoom }
                                service.setZoom((zoomStart ?? 1)*value.magnification)
                            }.onEnded { _ in zoomStart = nil })
                    }
                    if service.status == .tracking {
                        if let target, !target.guide.isAligned {
                            let guide = target.guide
                            let x = max(24,geometry.size.width/2-42), y = max(24,geometry.size.height/2-200)
                            let scale = min(x/max(abs(guide.arrow.dx),0.001),y/max(abs(guide.arrow.dy),0.001))
                            Image(systemName:"arrow.up").font(.system(size:30,weight:.semibold))
                                .rotationEffect(.radians(atan2(guide.arrow.dy,guide.arrow.dx) + .pi/2))
                                .padding(14).background(.regularMaterial,in:Circle())
                                .position(x:geometry.size.width/2+guide.arrow.dx*scale,y:geometry.size.height/2+guide.arrow.dy*scale)
                                .allowsHitTesting(false)
                        }
                    }
                    VStack {
                        Spacer()
                        VStack(spacing:8) {
                            CameraRecalibrationNotice(service:service) { showsAlignment = true }
                            switch service.status {
                            case .tracking:
                                if service.alignment.requiresCalibration {
                                    Text("Sky positions are paused until calibration.").font(.caption)
                                } else if let target {
                                    Text(target.star.title).font(.headline)
                                    Text(target.guide.isAligned ? "You’re pointing the right way" : instruction(target.guide)).font(.subheadline)
                                    Text("Expected position · not a camera detection").font(.caption).foregroundStyle(.secondary)
                                } else if (service.cameraHeadingAccuracy ?? 100) > 25 {
                                    Text("Finding north…").font(.headline)
                                    Text("Hold steady, away from magnets or metal cases.").font(.caption)
                                } else {
                                    Text("No objects match these conditions right now.").font(.subheadline)
                                }
                            case .preparing,.requestingPermission:
                                ProgressView(); Text("Getting the camera ready…").font(.subheadline)
                            case .limited(let message),.unavailable(let message): Text(message).font(.subheadline)
                            case .denied(let message):
                                Text(message).font(.subheadline)
                                Button("Open Settings") { if let url = URL(string:UIApplication.openSettingsURLString) { openURL(url) } }
                            }
                        }.multilineTextAlignment(.center).padding(16).frame(maxWidth:.infinity)
                            .background(.regularMaterial,in:RoundedRectangle(cornerRadius:20))
                    }.padding(.horizontal,20).padding(.bottom,max(24,geometry.safeAreaInsets.bottom+12))
                }
            }.ignoresSafeArea()
                .navigationTitle("Visible Now").navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden,for:.navigationBar).toolbarColorScheme(.dark,for:.navigationBar)
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("Close",systemImage:"xmark") { dismiss() } }
                    ToolbarItemGroup(placement:.topBarTrailing) {
                        Menu {
                            Picker("Find an object",selection:$selectedID) {
                                ForEach(service.viewableObjects.filter { !$0.star.isSolarDisc }) { observation in
                                    Text(observation.star.title).tag(Optional(observation.id))
                                }
                            }
                        } label: { Label("Find an object",systemImage:"list.star") }
                        Button("Align",systemImage:"scope") { showsAlignment = true }
                    }
                }
        }.preferredColorScheme(.dark).foregroundStyle(.white).tint(.white)
            .sheet(isPresented:$showsAlignment,onDismiss:{ service.scannerPaused = false }) {
                CameraAlignmentView(service:service,stars:service.viewableObjects.map(\.star),initialStar:target?.star)
            }
            .task { service.updateVisibility(quality:model.quality,atmosphere:model.atmosphere,filters:model.visibilityFilters); await service.start() }
            .onChange(of:model.visibilityFilters) { _, _ in service.updateVisibility(quality:model.quality,atmosphere:model.atmosphere,filters:model.visibilityFilters) }
            .onDisappear { service.stop() }
            .onChange(of:phase) { _, value in
                if value == .active { Task { await service.start() } }
            else if value == .background { service.suspendForBackground() }
            else { service.stop() }
            }
            .onChange(of:service.skyDate) { _, _ in
                if let selectedID, !service.viewableObjects.contains(where:{ $0.id == selectedID }) { self.selectedID = nil }
            }
    }
    private func instruction(_ guide: SkyFinderProjection) -> String {
        if abs(guide.arrow.dx) > abs(guide.arrow.dy) { return guide.arrow.dx > 0 ? "Move your phone to the right" : "Move your phone to the left" }
        return guide.arrow.dy > 0 ? "Point a little lower" : "Point a little higher"
    }
}

struct CameraAlignmentView: View {
    let service: SkyFinderService
    let stars: [CatalogStar]
    let initialStar: CatalogStar?
    @State private var selectedID: Int?
    @State private var snapshot: CameraAlignmentFrame?
    @State private var point: CGPoint?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    private var selected: CatalogStar? { stars.first { $0.id == selectedID } ?? initialStar ?? stars.first }

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot, let selected {
                    VStack(spacing:12) {
                        Text("Tap the real \(selected.title) in this photo.").font(.headline).multilineTextAlignment(.center)
                        Text("The image is frozen. Put the ring on the light itself, then save.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Image(uiImage:snapshot.image).resizable()
                            .aspectRatio(snapshot.size.width/snapshot.size.height,contentMode:.fit)
                            .overlay {
                                GeometryReader { geometry in
                                    ZStack {
                                        Color.clear.contentShape(Rectangle())
                                        if let point {
                                            Circle().stroke(.black,lineWidth:4).overlay { Circle().stroke(.yellow,lineWidth:1.5) }
                                                .frame(width:28,height:28)
                                                .position(x:point.x/snapshot.size.width*geometry.size.width,y:point.y/snapshot.size.height*geometry.size.height)
                                        }
                                    }.gesture(SpatialTapGesture().onEnded { value in
                                        point = CGPoint(x:value.location.x/geometry.size.width*snapshot.size.width,
                                                        y:value.location.y/geometry.size.height*snapshot.size.height)
                                    })
                                }
                            }
                        HStack {
                            Button("Retake") { self.snapshot = nil; point = nil; service.scannerPaused = false }
                                .buttonStyle(.bordered)
                            Button("Use This Position") {
                                guard let point else { return }
                                if service.applyAlignment(frame:snapshot,star:selected,point:point) { dismiss() }
                                else { error = "The photo may be out of date, the reference may be wrong, or tracking may have shifted. Reset tracking, retake the photo and mark a known object above the horizon." }
                            }.buttonStyle(.borderedProminent).disabled(point == nil)
                        }
                    }.padding(16)
                } else {
                    Form {
                        if let reason = service.alignment.calibrationReason {
                            Section("Calibration needed") { Text(reason).font(.subheadline) }
                        }
                        Section("Reference object") {
                            if stars.count > 1 {
                                Picker("Object",selection:Binding(get:{ selected?.id ?? 0 },set:{ selectedID = $0 })) {
                                    ForEach(stars) { star in Text(star.title).tag(star.id) }
                                }.pickerStyle(.navigationLink)
                            } else { Text(selected?.title ?? "No reference available") }
                            Text("Choose an object you can identify yourself. The app’s suggested name may be wrong, so don’t use that guess alone to calibrate.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text("Keep the object in the camera view. Freeze the image, then tap the light’s real position.")
                                .font(.subheadline)
                            Button("Freeze Camera",systemImage:"camera") {
                                guard let frame = service.captureAlignmentFrame() else {
                                    error = "The camera isn’t ready yet. Close this sheet, hold still until tracking is ready, and try again."
                                    return
                                }
                                snapshot = frame; service.scannerPaused = true
                            }.disabled(selected == nil || service.status != .tracking)
                            Button("Reset Tracking & Recalibrate",systemImage:"arrow.counterclockwise") {
                                service.resetTrackingForCalibration()
                            }
                        }
                        Section("Saved alignment") {
                            if let reference = service.alignment.reference {
                                LabeledContent("Reference",value:reference)
                                if let date = service.alignment.date { Text(date.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary) }
                                Button("Remove Alignment",role:.destructive) { service.clearAlignment() }
                            } else { Text("No manual alignment saved.").foregroundStyle(.secondary) }
                            Text("This correction is shared by Collect, Find in the Sky and View in AR during this camera session. After leaving the app, losing tracking or moving to another location, calibrate again. One reference improves alignment nearby; check a second known object elsewhere in the sky.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }.navigationTitle("Align the Sky").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } } }
        }.preferredColorScheme(.dark)
            .onAppear { selectedID = initialStar?.id ?? stars.first?.id }
            .onChange(of:service.alignment.generation) { _, _ in
                snapshot = nil; point = nil; service.scannerPaused = false
            }
            .onDisappear { service.scannerPaused = false }
            .alert("Couldn’t align",isPresented:Binding(get:{ error != nil },set:{ if !$0 { error = nil } })) {
                Button("OK",role:.cancel) { error = nil }
            } message: { Text(error ?? "") }
    }
}

/// Keep recovery visible in all camera screens until a fresh reference is saved.
struct CameraRecalibrationNotice: View {
    let service: SkyFinderService
    let openAlignment: () -> Void
    var body: some View {
        if let reason = service.alignment.calibrationReason {
            VStack(spacing:8) {
                Label("Calibrate the sky again",systemImage:"scope").font(.headline)
                Text(reason).font(.caption).foregroundStyle(.secondary)
                Button("Reset & Calibrate") {
                    service.resetTrackingForCalibration()
                    openAlignment()
                }.buttonStyle(.borderedProminent)
            }.multilineTextAlignment(.center)
        }
    }
}
