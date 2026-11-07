import SwiftUI

struct StarCameraView: View {
    let model: HomeViewModel
    @State private var service: SkyFinderService
    @State private var selectedStar: CatalogStar?
    @State private var pinnedTargetID: Int?
    @State private var opensNoteDirectly = false
    @State private var settledTargetID: Int?
    @State private var identificationNote: String?
    @State private var tappedCapture: CameraObservationDraft?
    @State private var showsCaptureError = false
    @State private var showsInfo = false
    @State private var showsAlignment = false
    @State private var showsNearbyStars = false
    @State private var showsUnknownInfo = false
    @State private var unknownIssue: CameraIdentificationIssue = .stabilizing
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
        _service = State(initialValue:SkyFinderService(location:model.location,catalogue:model.stars,alignment:model.cameraAlignment))
    }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea()
                    if service.isCameraRunning {
                        SkyCameraPreview(session:service.session,onViewport:service.updateViewport,
                            onTap:{ point in placeFocus(point) },onHold:{ point in placeFocus(point,lock:true) },
                            onExposureDrag:{ translation, point, ended in
                                adjustExposure(translation:translation,at:point,ended:ended)
                            },skyMarkers:observedWorldMarkers,labeledMarkerIDs:Set(observedWorldMarkers.map(\.id)),
                            selectedMarkerID:pinnedTargetID,onSelectMarker:{ id in
                                if let annotation = service.annotations.first(where:{ $0.id == id }) { pin(annotation) }
                            },markerColor:.systemGreen,markerTitlePrefix:"≈ ",zoom:service.cameraZoom)
                            .simultaneousGesture(MagnifyGesture().onChanged { value in
                                if zoomStart == nil { zoomStart = service.cameraZoom }
                                service.setZoom((zoomStart ?? 1)*value.magnification)
                            }.onEnded { _ in zoomStart = nil })
                    }
                    if service.status == .tracking && selectedStar == nil {
                        ForEach(service.unidentifiedLights) { light in
                            RoundedRectangle(cornerRadius:1).stroke(.white.opacity(0.9),lineWidth:1)
                                .frame(width:light.size.width,height:light.size.height).position(light.point).allowsHitTesting(false)
                            Button { unknownIssue = light.issue; showsUnknownInfo = true } label: {
                                Text(light.issue.title).font(.system(size:10,weight:.medium)).foregroundStyle(.white)
                                    .multilineTextAlignment(.center).lineLimit(2).frame(maxWidth:170)
                                    .padding(.horizontal,5).padding(.vertical,3).background(.black.opacity(0.6),in:RoundedRectangle(cornerRadius:4))
                                    .frame(minWidth:44,minHeight:44)
                            }.buttonStyle(.plain)
                                .position(x:min(geometry.size.width-90,max(90,light.point.x)),y:light.point.y+22)
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
                        CameraRecalibrationNotice(service:service) { showsAlignment = true }
                        if service.isCameraRunning { inlineCameraControls }
                        if let target = aimedTarget, settledTargetID == target.id {
                            aimCard(target)
                        } else { cameraStatus }
                    }
                    .padding(.horizontal,20)
                    .padding(.top,20)
                    .padding(.bottom,max(20,geometry.safeAreaInsets.bottom+12))
                }
            }
            .ignoresSafeArea()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark,for:.navigationBar)
            .toolbarBackground(.hidden,for:.navigationBar)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button("Close",systemImage:"xmark") { dismiss() }.accessibilityLabel("Close Sky Camera")
                }
                ToolbarItemGroup(placement:.topBarTrailing) {
                    Button("Visible nearby",systemImage:"list.star") { showsNearbyStars = true }
                    Menu {
                        Button("Align with a known object",systemImage:"scope") { showsAlignment = true }
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
                Button("Align with a known object") { showsAlignment = true }
                Button("Close",role:.cancel) {}
            } message: {
                Text(unknownIssue.message)
            }
            .alert("Couldn’t capture that",isPresented:$showsCaptureError) {
                Button("Try Again",role:.cancel) {}
            } message: {
                Text("Keep the light in view and try again.")
            }
            .sheet(isPresented:$showsAlignment,onDismiss:{ service.scannerPaused = false }) {
                CameraAlignmentView(service:service,stars:[.sun,.moon]+CatalogStar.planets+model.stars.filter(\.hasCommonName),initialStar:aimedTarget?.object.star)
            }
            .sheet(isPresented:$showsNearbyStars) {
                nearbyStarsSheet.presentationDetents([.medium,.large]).presentationDragIndicator(.visible)
            }
            .sheet(item:$selectedStar,onDismiss:{ service.scannerPaused = false; tappedCapture = nil }) { star in
                Group {
                    if opensNoteDirectly, let tappedCapture {
                        NavigationStack {
                            NewStarNoteView(model:model,draft:tappedCapture,onSaved:{ selectedStar = nil })
                                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { selectedStar = nil } } }
                        }
                    } else {
                        CameraCollectionFlow(model:model,star:star,capture:tappedCapture,identificationNote:identificationNote,onClose:{ selectedStar = nil })
                    }
                }.presentationDetents([.large]).presentationDragIndicator(.visible)
            }
        }
        .foregroundStyle(.white).tint(.white).preferredColorScheme(.dark)
        .task {
            service.updateVisibility(quality:model.quality,atmosphere:model.atmosphere,filters:model.visibilityFilters)
            await service.start()
        }
        .onChange(of:model.visibilityFilters) { _, _ in service.updateVisibility(quality:model.quality,atmosphere:model.atmosphere,filters:model.visibilityFilters) }
        .onChange(of:model.quality) { _, _ in service.updateVisibility(quality:model.quality,atmosphere:model.atmosphere,filters:model.visibilityFilters) }
        .onChange(of:model.atmosphere) { _, _ in service.updateVisibility(quality:model.quality,atmosphere:model.atmosphere,filters:model.visibilityFilters) }
        .onChange(of:showsNearbyStars) { _, showing in service.scannerPaused = showing }
        .onDisappear { focusTask?.cancel(); service.stop() }
        .onChange(of:phase) { _, value in
            if value == .active { Task { await service.start() } }
            else if value == .background { service.suspendForBackground() }
            else { service.stop() }
        }
        .task(id:aimIdentity) {
            settledTargetID = nil
            guard let id = aimIdentity else {
                if selectedStar == nil { pinnedTargetID = nil; tappedCapture = nil }
                return
            }
            if tappedCapture?.star.id != id { tappedCapture = nil }
            try? await Task.sleep(for:.milliseconds(300))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration:0.2)) { settledTargetID = id }
        }
        .onChange(of:service.isAdjustingCamera) { _, adjusting in
            if adjusting, selectedStar == nil { pinnedTargetID = nil; tappedCapture = nil }
        }
        .onChange(of:selectedStar?.id) { _, id in service.scannerPaused = id != nil }
        .onChange(of:service.skyDate) { _, _ in if let selectedStar { prepare(selectedStar) } }
        .onChange(of:service.alignment.generation) { _, _ in
            pinnedTargetID = nil; settledTargetID = nil; tappedCapture = nil
        }
    }
    // Only actual optical observations become collect markers; catalog predictions never do.
    private var observedWorldMarkers: [CameraSkyPrediction] {
        guard service.status == .tracking, selectedStar == nil, !service.alignment.requiresCalibration else { return [] }
        return service.annotations.compactMap { observation in
            guard let direction = observation.sourceDirection else { return nil }
            return CameraSkyPrediction(direction:direction,star:observation.star,
                guide:SkyFinderProjection(point:observation.point,arrow:.zero,separation:observation.estimatedSeparation ?? 0))
        }
    }
    private var nearbyStarsSheet: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Your surroundings",selection:Binding(get:{ model.quality },set:{ model.quality = $0 })) {
                        ForEach(SkyQuality.allCases) { quality in Text(quality.rawValue).tag(quality) }
                    }
                    Text("These objects may be visible above your horizon right now. The cyan rings use this same list. It covers the whole sky around you, not just this camera view.")
                    Text("Based on your location, the Sun, moonlight, brightness and your selected surroundings. Buildings, local lights and clouds in front of a particular star can still change what you see.")
                        .foregroundStyle(.secondary)
                    if let weatherDate = model.atmosphere.weatherDate {
                        Text("Cloud forecast: \(weatherDate.formatted(date:.abbreviated,time:.shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("No local cloud reading available. We’re using a standard atmosphere.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                VisibilityFilterSection(model:model)
                Section("Likely visible · \(service.viewableObjects.count)") {
                    if service.viewableObjects.isEmpty {
                        ContentUnavailableView("No matches right now",systemImage:"sparkles",
                            description:Text("The current light and visibility filters don’t suggest any stars or planets. A light actually seen by the camera can still be collected."))
                    }
                    ForEach(service.viewableObjects) { observation in
                        HStack(spacing:12) {
                            Circle().fill(CameraMarkerPalette.color(for:observation.star)).frame(width:10,height:10)
                                .padding(5).overlay { Circle().stroke(.cyan,lineWidth:1) }
                            VStack(alignment:.leading,spacing:4) {
                                Text(observation.star.title).font(.headline)
                                Text(observation.star.isSun ? "Sun" : observation.star.isMoon ? "Moon" : observation.star.isPlanet ? "Planet" : model.constellationName(observation.star))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment:.trailing,spacing:4) {
                                Text(String(format:"%@ · %.0f° up",observation.bearing,observation.altitude))
                                if !observation.star.isSolarDisc {
                                    Text(String(format:"Mag %.1f",observation.dimmedMagnitude)).foregroundStyle(.secondary)
                                }
                            }.font(.caption.monospacedDigit())
                        }.padding(.vertical,4)
                    }
                }
            }.navigationTitle("Visible near you").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { showsNearbyStars = false } } }
        }.preferredColorScheme(.dark)
    }
    private var aimedTarget: CameraAimTarget? { service.aimTarget(pinnedID:pinnedTargetID) }
    private var aimIdentity: Int? { aimedTarget?.id }

    private func aimCard(_ target: CameraAimTarget) -> some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                VStack(alignment:.leading,spacing:4) {
                    Text((target.detection == nil ? "" : "≈ ")+target.object.star.title).font(.title3.bold())
                    Label(target.detection == nil ? "Mapped position · not detected yet" : "Light spotted · likely match",
                          systemImage:target.detection == nil ? "location" : "camera.fill")
                        .font(.caption).foregroundStyle(target.detection == nil ? .secondary : Color.green)
                }
                Spacer()
                if pinnedTargetID != nil {
                    Button("Resume aiming",systemImage:"xmark.circle.fill") { pinnedTargetID = nil; tappedCapture = nil }
                        .labelStyle(.iconOnly).frame(width:44,height:44)
                }
            }
            Text(target.detection == nil ? "Keep this spot in view. Collect unlocks when the camera picks up a light here." : "You can collect this light. Its name is our best match, based on direction and brightness.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Details") { open(target,directly:false) }.buttonStyle(.bordered)
                Button(model.collected[target.id]?.photoFilename == nil ? "Collect" : "View Your Note") {
                    open(target,directly:model.collected[target.id]?.photoFilename == nil)
                }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                    .disabled(target.detection == nil && model.collected[target.id]?.photoFilename == nil)
            }.frame(maxWidth:.infinity,alignment:.trailing)
        }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
            .background(.regularMaterial,in:RoundedRectangle(cornerRadius:22))
            .overlay { RoundedRectangle(cornerRadius:22).stroke(target.detection == nil ? .white.opacity(0.2) : .green.opacity(0.7),lineWidth:1) }
    }

    private func note(for annotation: CameraStarAnnotation) -> String? {
        annotation.estimatedSeparation.map {
            String(format:"This looks like %@. The light is %.1f° from its expected position, so the name is still an estimate.",annotation.star.title,$0)
        }
    }
    private func pin(_ annotation: CameraStarAnnotation) {
        pinnedTargetID = annotation.id
        tappedCapture = service.captureObservation(annotation:annotation,identificationNote:note(for:annotation))
        focusTask?.cancel(); focusPoint = nil
    }
    private func open(_ target: CameraAimTarget,directly: Bool) {
        identificationNote = target.detection.flatMap { note(for:$0) }
        if tappedCapture?.star.id != target.id { tappedCapture = nil }
        if directly {
            // Capture at selection time, before presenting any sheet; never photograph the sheet.
            if tappedCapture == nil, let detection = target.detection {
                tappedCapture = service.captureObservation(annotation:detection,identificationNote:identificationNote)
            }
            guard tappedCapture != nil else { showsCaptureError = true; return }
        } else if tappedCapture == nil, let detection = target.detection {
            tappedCapture = service.captureObservation(annotation:detection,identificationNote:identificationNote)
        }
        opensNoteDirectly = directly
        prepare(target.object.star)
        selectedStar = target.object.star
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
    private func adjustExposure(translation: CGFloat,at point: CGPoint,ended: Bool) {
        guard service.maximumExposure > service.minimumExposure, zoomStart == nil else {
            exposureStart = nil
            return
        }
        focusTask?.cancel()
        if exposureStart == nil {
            exposureStart = service.exposureBias
            if focusPoint == nil { focusPoint = point }
            showsZoomRuler = false
        }
        service.setExposure((exposureStart ?? service.exposureBias)-Double(translation)/100)
        if ended {
            exposureStart = nil
            focusTask = Task { @MainActor in
                try? await Task.sleep(for:.seconds(3))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration:0.2)) { focusPoint = nil }
            }
        }
    }
    @ViewBuilder private func focusControl(at point: CGPoint,size: CGSize) -> some View {
        RoundedRectangle(cornerRadius:1).stroke(.yellow,lineWidth:1)
            .frame(width:64,height:64)
            .overlay(alignment:.top) {
                Text("Focus").font(.caption2.weight(.medium)).foregroundStyle(.yellow).offset(y:-18)
            }.position(point).allowsHitTesting(false)
        Image(systemName:"sun.max.fill")
            .font(.system(size:20)).foregroundStyle(.yellow)
            .frame(width:44,height:100).contentShape(Rectangle())
            .position(x:point.x > size.width-80 ? point.x-48 : point.x+48,y:point.y)
            .gesture(DragGesture(minimumDistance:2).onChanged { value in
                adjustExposure(translation:value.translation.height,at:point,ended:false)
            }.onEnded { value in
                adjustExposure(translation:value.translation.height,at:point,ended:true)
            })
            .accessibilityLabel("Slide up to brighten, down to darken")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: service.setExposure(service.exposureBias+0.2)
                case .decrement: service.setExposure(service.exposureBias-0.2)
                @unknown default: break
                }
            }
        if exposureStart != nil {
            Text(String(format:"%+.1f",service.exposureBias)).font(.caption.monospacedDigit()).foregroundStyle(.yellow)
                .padding(5).background(.black.opacity(0.45),in:Capsule())
                .position(x:min(size.width-32,max(32,point.x)),y:min(size.height-24,max(24,point.y+50)))
                .allowsHitTesting(false)
        }
    }
    private var inlineCameraControls: some View {
        VStack(spacing:10) {
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
                if service.alignment.requiresCalibration {
                    Text("Object identification is paused until calibration.").font(.caption)
                } else if service.isAdjustingCamera {
                    Text("Letting the camera settle…").font(.subheadline.weight(.medium))
                    Text("Hold still for a moment after changing focus, brightness or zoom.").font(.caption).foregroundStyle(.secondary)
                } else if service.annotations.isEmpty {
                    Text(service.unidentifiedLights.first?.issue.title ?? (service.detectedLightCount > 0 ? "Light spotted · hold still…" : focusPoint != nil ? "Searching around your focus point…" : "Point at a star or planet"))
                        .font(.subheadline.weight(.medium))
                    Text(service.unidentifiedLights.first?.issue.message ?? (service.detectedLightCount > 0 ? "Keeping it steady helps us hold the marker." : focusPoint != nil ? "The yellow box sets focus. Hold steady; slide the sun up if the light is too dim." : "Hold steady for a moment when you see a light."))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(service.annotations.contains(where: { $0.estimatedSeparation != nil }) ? "≈ Our best guess" : "Tap a name to take a closer look").font(.caption)
                    if service.annotations.contains(where: { $0.estimatedSeparation != nil }) {
                        Text("Tap a name to collect this light.").font(.caption).foregroundStyle(.secondary)
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


private enum CameraMarkerPalette {
    // Approximate catalog B−V colors, not a color measurement from the camera.
    static func color(for star: CatalogStar) -> Color {
        if star.isSun { return Color(red:1,green:0.86,blue:0.52) }
        if star.isMoon { return Color(red:0.9,green:0.93,blue:1) }
        guard let bv = star.bv else { return .white }
        if bv < 0.2 { return Color(red:0.62,green:0.77,blue:1) }
        if bv < 0.6 { return Color(red:0.9,green:0.94,blue:1) }
        if bv < 1 { return Color(red:1,green:0.88,blue:0.62) }
        if bv < 1.5 { return Color(red:1,green:0.7,blue:0.42) }
        return Color(red:1,green:0.5,blue:0.35)
    }
}
