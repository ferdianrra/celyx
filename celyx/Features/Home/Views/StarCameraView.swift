import SwiftUI

struct StarCameraView: View {
    let model: HomeViewModel
    @State private var service: SkyFinderService
    @State private var selectedStar: CatalogStar?
    @State private var identificationNote: String?
    @State private var tappedCapture: CameraObservationDraft?
    @State private var showsCaptureError = false
    @State private var showsInfo = false
    @State private var showsUnknownInfo = false
    @State private var showsExposureRuler = false
    @State private var showsZoomRuler = false
    @State private var focusPoint: CGPoint?
    @State private var exposureStart: Double?
    @State private var zoomStart: Double?
    @State private var focusTask: Task<Void,Never>?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @Environment(\.openURL) private var openURL

    init(model: HomeViewModel) {
        self.model = model
        _service = State(initialValue:SkyFinderService(location:model.location,catalogue:model.stars))
    }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea()
                    if service.isCameraRunning {
                        SkyCameraPreview(session:service.session,onViewport:service.updateViewport,
                            onTap:{ point in placeFocus(point) },onHold:{ point in placeFocus(point,lock:true) })
                            .simultaneousGesture(MagnifyGesture().onChanged { value in
                                if zoomStart == nil { zoomStart = service.cameraZoom }
                                service.setZoom((zoomStart ?? 1)*value.magnification)
                            }.onEnded { _ in zoomStart = nil })
                    }
                    if service.status == .tracking && selectedStar == nil {
                        ForEach(service.unidentifiedLights) { light in
                            RoundedRectangle(cornerRadius:1).stroke(.white.opacity(0.9),lineWidth:1)
                                .frame(width:light.size.width,height:light.size.height).position(light.point).allowsHitTesting(false)
                            Button { showsUnknownInfo = true } label: {
                                Text("A little light").font(.system(size:10,weight:.medium)).foregroundStyle(.white)
                                    .padding(.horizontal,5).padding(.vertical,3).background(.black.opacity(0.6),in:RoundedRectangle(cornerRadius:4))
                                    .frame(minWidth:44,minHeight:44)
                            }.buttonStyle(.plain)
                                .position(x:min(geometry.size.width-55,max(55,light.point.x)),y:light.point.y+22)
                        }
                        ForEach(service.annotations) { annotation in
                            RoundedRectangle(cornerRadius:1)
                                .stroke(annotation.estimatedSeparation == nil ? Color.green : Color.orange,lineWidth:1)
                                .frame(width:annotation.size.width,height:annotation.size.height)
                                .position(annotation.point).allowsHitTesting(false)
                            Button { select(annotation) } label: {
                                Text((annotation.estimatedSeparation == nil ? "" : "≈ ")+annotation.star.title)
                                    .font(.system(size:10,weight:.medium))
                                    .foregroundStyle(annotation.estimatedSeparation == nil ? Color.green : Color.orange)
                                    .padding(.horizontal,5).padding(.vertical,3)
                                    .background(.black.opacity(0.55),in:RoundedRectangle(cornerRadius:4))
                                    .frame(minWidth:44,minHeight:44)
                            }
                            .buttonStyle(.plain)
                            .position(x:min(geometry.size.width-65,max(65,annotation.point.x)),y:annotation.point.y+22)
                            .accessibilityLabel("Detail \(annotation.star.title)")
                            Button { select(annotation) } label: {
                                Color.clear.frame(width:44,height:44).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).position(annotation.point)
                            .accessibilityLabel("Capture \(annotation.star.title)")
                        }
                    }
                    if let point = focusPoint {
                        focusControl(at:point,size:geometry.size)
                    }
                    VStack(spacing:12) {
                        Spacer()
                        if service.focusLocked {
                            Text("AE/AF LOCK").font(.caption.weight(.semibold)).foregroundStyle(.yellow)
                                .padding(7).background(.black.opacity(0.6),in:Capsule())
                        }
                        if service.isCameraRunning { inlineCameraControls }
                        cameraStatus
                    }.padding(20)
                }
            }
            .navigationTitle("Sky Camera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark,for:.navigationBar)
            .toolbarBackground(.hidden,for:.navigationBar)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button("Close",systemImage:"xmark") { dismiss() }.accessibilityLabel("Close Sky Camera")
                }
                ToolbarItemGroup(placement:.topBarTrailing) {
                    Button("Exposure",systemImage:"plusminus") { showsExposureRuler.toggle() }
                        .tint(showsExposureRuler ? .yellow : .white)
                    Menu {
                        Button("Reset camera",systemImage:"arrow.counterclockwise") {
                            focusTask?.cancel(); service.resetCameraControls(); focusPoint = nil
                        }
                        Button("About these markers",systemImage:"info.circle") { showsInfo = true }
                    } label: { Image(systemName:"ellipsis") }
                    .accessibilityLabel("Camera options")
                }
            }
            .alert("What’s that light?",isPresented:$showsInfo) {
                Button("Got it",role:.cancel) {}
            } message: {
                Text("We look for bright stars and planets near the light in your camera. Direction, expected brightness and a steady match help us pick one suggestion. A ≈ name is still a guess. If two matches are too close to call, we leave the light unnamed. Lights on the ground can still fool the camera.")
            }
            .alert("We spotted a light",isPresented:$showsUnknownInfo) {
                Button("Recalibrate compass") { service.recalibrateCameraDirection() }
                Button("Close",role:.cancel) {}
            } message: {
                Text("We can see a light, but we can’t give it a clear name yet. The matches may be too close to call, or the compass may need recalibrating. It could also be a light on the ground.")
            }
            .alert("Couldn’t capture that",isPresented:$showsCaptureError) {
                Button("Try Again",role:.cancel) {}
            } message: {
                Text("Keep the light in view and tap its name again.")
            }
            .sheet(item:$selectedStar,onDismiss:{ service.scannerPaused = false; tappedCapture = nil }) { star in
                CameraCollectionFlow(model:model,star:star,capture:tappedCapture,identificationNote:identificationNote,onClose:{ selectedStar = nil })
                    .presentationDetents([.large]).presentationDragIndicator(.visible)
            }
        }
        .foregroundStyle(.white).tint(.white).preferredColorScheme(.dark)
        .task { await service.start() }
        .onDisappear { focusTask?.cancel(); service.stop() }
        .onChange(of:phase) { _, value in
            if value == .active { Task { await service.start() } } else { service.stop() }
        }
        .onChange(of:selectedStar?.id) { _, id in service.scannerPaused = id != nil }
        .onChange(of:service.skyDate) { _, _ in if let selectedStar { prepare(selectedStar) } }
    }
    private func select(_ annotation: CameraStarAnnotation) {
        let current = service.annotations.first(where: { $0.id == annotation.id }) ?? annotation
        let note = current.estimatedSeparation.map {
            String(format:"Our best match is %@, based on direction and brightness. Direction offset: %.1f°. This is still a guess, not a confirmed identification.",current.star.title,$0)
        }
        guard let capture = service.captureObservation(annotation:current,identificationNote:note) else {
            showsCaptureError = true
            return
        }
        identificationNote = note
        tappedCapture = capture
        focusTask?.cancel(); focusPoint = nil
        service.scannerPaused = true
        prepare(current.star)
        selectedStar = current.star
    }
    private func placeFocus(_ point: CGPoint,lock: Bool = false) {
        focusTask?.cancel()
        guard service.focus(at:point) else { return }
        focusPoint = point
        showsZoomRuler = false
        focusTask = Task { @MainActor in
            if lock {
                try? await Task.sleep(for:.milliseconds(600))
                guard !Task.isCancelled else { return }
                service.focus(at:point,locked:true)
            } else {
                try? await Task.sleep(for:.seconds(4))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration:0.25)) { focusPoint = nil }
            }
        }
    }
    @ViewBuilder private func focusControl(at point: CGPoint,size: CGSize) -> some View {
        RoundedRectangle(cornerRadius:1).stroke(.yellow,lineWidth:1)
            .frame(width:64,height:64).position(point).allowsHitTesting(false)
        Image(systemName:"sun.max.fill")
            .font(.system(size:20)).foregroundStyle(.yellow)
            .frame(width:44,height:100).contentShape(Rectangle())
            .position(x:point.x > size.width-80 ? point.x-48 : point.x+48,y:point.y)
            .gesture(DragGesture(minimumDistance:2).onChanged { value in
                focusTask?.cancel()
                if exposureStart == nil { exposureStart = service.exposureBias }
                service.setExposure((exposureStart ?? 0)-Double(value.translation.height)/65)
            }.onEnded { _ in exposureStart = nil })
            .accessibilityLabel("Slide up to brighten, down to darken")
    }
    private var inlineCameraControls: some View {
        VStack(spacing:10) {
            if showsExposureRuler {
                HStack(spacing:12) {
                    Image(systemName:"sun.min")
                    Slider(value:Binding(get:{service.exposureBias},set:{ service.setExposure($0) }),
                        in:service.minimumExposure...max(service.minimumExposure+0.1,service.maximumExposure),step:0.1)
                        .disabled(service.maximumExposure <= service.minimumExposure)
                        .accessibilityLabel("Camera exposure")
                    Text(String(format:"%+.1f",service.exposureBias)).font(.caption.monospacedDigit()).frame(width:42)
                }.foregroundStyle(.yellow).tint(.yellow)
                .padding(12).background(.black.opacity(0.65),in:Capsule())
            }
            if showsZoomRuler {
                HStack(spacing:12) {
                    Text("1×").font(.caption)
                    Slider(value:Binding(get:{service.cameraZoom},set:{ service.setZoom($0) }),
                        in:service.minimumZoom...max(service.minimumZoom+0.1,service.maximumZoom))
                        .disabled(service.maximumZoom <= service.minimumZoom)
                        .accessibilityLabel("Camera zoom")
                    Text(String(format:"%.1f×",service.cameraZoom)).font(.caption.monospacedDigit()).frame(width:44)
                }.tint(.yellow).padding(12).background(.black.opacity(0.65),in:Capsule())
            }
            HStack(spacing:10) {
                ForEach([1.0,2,3,6].filter { $0 <= service.maximumZoom+0.01 },id:\.self) { factor in
                    Button {
                        service.setZoom(factor,animated:true)
                    } label: {
                        Text(String(format:"%.0f×",factor)).font(.system(size:13,weight:.semibold))
                            .foregroundStyle(abs(service.cameraZoom-factor) < 0.15 ? .yellow : .white)
                            .frame(width:42,height:42)
                            .background(.black.opacity(0.55),in:Circle())
                    }.buttonStyle(.plain)
                    .onLongPressGesture(minimumDuration:0.4) { showsZoomRuler = true }
                    .accessibilityLabel(String(format:"Zoom %.0f times",factor))
                }
                Button { showsZoomRuler.toggle() } label: {
                    Text(String(format:"%.1f×",service.cameraZoom)).font(.caption.monospacedDigit())
                        .foregroundStyle(.yellow).padding(10).background(.black.opacity(0.65),in:Capsule())
                }.buttonStyle(.plain).accessibilityLabel("Adjust zoom")
            }
            if let message = service.cameraControlMessage {
                Text(message).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }

    private func prepare(_ star: CatalogStar) {
        if let location = service.observerLocation { model.prepareCameraStar(star,location:location) }
    }
    @ViewBuilder private var cameraStatus: some View {
        VStack(spacing:8) {
            switch service.status {
            case .tracking:
                if service.isAdjustingCamera {
                    Text("Letting the camera settle…").font(.subheadline.weight(.medium))
                    Text("Hold still for a moment after changing focus, brightness or zoom.").font(.caption).foregroundStyle(.secondary)
                } else if service.annotations.isEmpty {
                    Text(!service.unidentifiedLights.isEmpty ? "Light detected · name not confirmed" : service.detectedLightCount > 0 ? "Light spotted · hold still…" : "Looking for a little light…")
                        .font(.subheadline.weight(.medium))
                    Text((service.cameraHeadingAccuracy ?? 0) > 25 ? "Your compass needs a moment. The light can still be marked while we find its name." : !service.unidentifiedLights.isEmpty ? "The white marker follows the light, even without a name." : service.detectedLightCount > 0 ? "Keeping it steady helps us hold the marker." : "Point at the sky. If the light looks faint, try a little more brightness.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(service.annotations.contains(where: { $0.estimatedSeparation != nil }) ? "≈ Our best guess" : "Tap a name to take a closer look").font(.caption)
                    if service.annotations.contains(where: { $0.estimatedSeparation != nil }) {
                        Text("Tap the name to look closer or save a memory.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            case .preparing, .requestingPermission:
                ProgressView(); Text("Getting the camera ready…").font(.subheadline)
            case .limited(let message):
                ProgressView(); Text(message).font(.subheadline)
            case .denied(let message):
                Text(message).font(.subheadline)
                Button("Open Settings") { if let url = URL(string:UIApplication.openSettingsURLString) { openURL(url) } }.buttonStyle(.bordered)
            case .unavailable(let message):
                Label("Sky Camera isn’t available",systemImage:"camera")
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center).padding(14)
        .background(.regularMaterial,in:RoundedRectangle(cornerRadius:16))
        .allowsHitTesting(service.status != .tracking)
    }
}
