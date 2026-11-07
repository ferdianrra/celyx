import SwiftUI
import ARKit
import simd

/// Prefer an independently recognized object; otherwise compare multiple observed stars as a pattern.
struct SkyCalibrationView: View {
    enum Mode { case reference, pattern }
    enum PreviewState { case reference, pattern, matching, saved, singleLight, catalogAR }
    enum Outcome: Equatable { case none, saved(String), failed(String) }
    struct Target: Identifiable, Equatable {
        let id: Int
        let name: String
        let direction: SIMD3<Double>
        let isDisc: Bool
        var azimuth: Double { atan2(direction.x,direction.y) }
        var altitude: Double { asin(min(1,max(-1,direction.z))) }
    }
    let catalogue: [CatalogStar]
    let onClose: () -> Void
    private let previewState: PreviewState?
    @State private var engine: SkyPatternCalibrationService
    @State private var motion: MotionService?
    @State private var location: ObserverLocation?
    @State private var attitude: simd_double3x3?
    @State private var attitudeDate: Date?
    @State private var motionMessage: String?
    @State private var targets: [Target] = []
    @State private var selectedID: Int?
    @State private var mode: Mode = .reference
    @State private var choseMode = false
    @State private var outcome: Outcome = .none
    @State private var cameraDenied = false
    @State private var showsCandidates = false
    @State private var showsCandidateAR = false
    @State private var selectedFromCatalog = false
    @State private var confirmsSingleIdentity = false

    init(catalogue: [CatalogStar],alignment: CameraSkyAlignment? = nil,
         preview: PreviewState? = nil,opensCatalog: Bool = false,initialLocation: ObserverLocation? = nil,
         onClose: @escaping () -> Void) {
        self.catalogue = catalogue; self.onClose = onClose; previewState = preview
        let sharedAlignment = alignment ?? (preview == nil ? CameraSkyAlignment() : AppPreviewData.model.cameraAlignment)
        let engine = SkyPatternCalibrationService(catalogue:catalogue,alignment:sharedAlignment,preview:preview != nil || AppPreviewData.isRunning)
        if let initialLocation { engine.location = initialLocation; engine.refreshCatalog() }
        engine.isBrowsing = opensCatalog
        _engine = State(initialValue:engine)
        _location = State(initialValue:initialLocation)
        _showsCandidates = State(initialValue:opensCatalog)
        _showsCandidateAR = State(initialValue:preview == .catalogAR)
        _mode = State(initialValue:preview == nil || preview == .reference ? .reference : .pattern)
        if preview != nil {
            _targets = State(initialValue:[.init(id:CatalogStar.sun.id,name:"Sun",direction:SIMD3(0.6,0,0.8),isDisc:true)])
        }
        if preview == .saved { _outcome = State(initialValue:.saved("Pattern confirmed with 4 stars · fit RMS 0.12°")) }
    }
    // MARK: Reference and catalog projection

    private var target: Target? {
        if let candidate = engine.candidates.first(where:{ $0.id == selectedID }) {
            let d = candidate.direction
            return Target(id:candidate.id,name:candidate.star.title,direction:SIMD3(Double(d.x),Double(-d.z),Double(d.y)),isDisc:false)
        }
        return targets.first(where:{ $0.id == selectedID }) ?? targets.first
    }
    private var referenceTargets: [Target] {
        guard let target, !targets.contains(where:{ $0.id == target.id }) else { return targets }
        return [target]+targets
    }
    private var catalogMarkers: [CameraSkyPrediction] {
        let predictions = engine.predictions
        var visible = predictions.filter { $0.guide.point != nil }
        if let id = engine.selectedCatalogID, !visible.contains(where:{ $0.id == id }),
           let selected = predictions.first(where:{ $0.id == id }) { visible.append(selected) }
        return visible
    }
    private var catalogLabels: Set<Int> {
        var points: [CGPoint] = []
        return Set(catalogMarkers.sorted { $0.id == engine.selectedCatalogID && $1.id != engine.selectedCatalogID }.filter {
            guard let point = $0.guide.point, points.count < 12,
                  !points.contains(where:{ hypot($0.x-point.x,$0.y-point.y) < 65 }) else { return false }
            points.append(point); return true
        }.map(\.id))
    }
    private var progress: Double { previewState == .matching ? 0.55 : engine.progress }
    private var saved: Bool { if case .saved = outcome { true } else { false } }
    private var reticleState: CrosshairState {
        if saved { return .enable }
        if mode == .pattern && (progress > 0 || engine.centerDirection != nil && engine.lights.count >= SkyPatternMatcher.minimumAutomaticPatternStars) { return .validating }
        return engine.referenceReady ? .enable : engine.centerDirection != nil ? .locking : .default
    }
    var body: some View {
        ZStack(alignment:.bottom) {
            GeometryReader { geometry in
                ZStack {
                    if previewState == nil {
                        SkyCameraPreview(session:engine.session,onViewport:{ size,orientation in
                            engine.viewport = size; engine.orientation = orientation
                        },skyMarkers:showsCandidateAR ? catalogMarkers : [],
                            labeledMarkerIDs:showsCandidateAR ? catalogLabels : [],selectedMarkerID:engine.selectedCatalogID,
                            onSelectMarker:{ engine.selectedCatalogID = $0 })
                    } else { Color(red:0.025,green:0.04,blue:0.1) }
                    if previewState == .catalogAR {
                        ForEach(Array(engine.candidates.prefix(4).enumerated()),id:\.element.id) { index,candidate in
                            VStack(spacing:5) {
                                Circle().stroke(.cyan,lineWidth:1).frame(width:16,height:16)
                                Text(candidate.star.title).font(.caption).foregroundStyle(.cyan)
                            }.position(x:geometry.size.width*(0.23+Double(index)*0.17),y:geometry.size.height*(index.isMultiple(of:2) ? 0.31 : 0.45))
                        }
                    }
                    if mode == .pattern && !showsCandidateAR {
                        ForEach(engine.lights) { light in
                            Circle().stroke(.cyan,lineWidth:1).frame(width:14,height:14).position(light.point)
                                .allowsHitTesting(false)
                        }
                        if previewState != nil {
                            ForEach(0..<(previewState == .singleLight ? 1 : 4),id:\.self) { index in
                                Circle().fill(.white).frame(width:4,height:4)
                                    .position(x:geometry.size.width*(0.25+Double(index)*0.16),y:geometry.size.height*(index.isMultiple(of:2) ? 0.35 : 0.48))
                            }
                        }
                    }
                    if !showsCandidateAR {
                        CrosshairView(state:previewState == .matching ? .validating : reticleState,
                            soundEnabled:false,hapticsEnabled:false,idleLoops:previewState == nil)
                            .position(x:geometry.size.width/2,y:geometry.size.height/2+10).accessibilityHidden(true)
                    }
                }
                .onAppear { engine.viewport = geometry.size }
            }.ignoresSafeArea()
            VStack {
                HStack {
                    CelyxBackButton { if showsCandidateAR { showsCandidateAR = false } else { close() } }
                    Spacer()
                    if showsCandidateAR { Text("Calibration AR").font(.headline).foregroundStyle(.white); Spacer() }
                    CelyxGlassButton(action:{ showsCandidates = true }) {
                        Image(systemName:"list.star").font(.system(size:20)).foregroundStyle(.white)
                    }.accessibilityLabel("Calibration Stars")
                }.padding(.horizontal,20)
                Spacer()
            }
            Group {
                if showsCandidateAR { catalogARPanel } else { panel }
            }.padding(.horizontal,6).padding(.bottom,6).ignoresSafeArea(edges:.bottom)
        }
        .background(.black).preferredColorScheme(.dark)
        .task { await start() }
        .task(id:location?.coordinateLabel) {
            guard previewState == nil else { return }
            while !Task.isCancelled { refreshTargets(); try? await Task.sleep(for:.seconds(5)) }
        }
        .onChange(of:engine.solution) { _, solution in
            guard mode == .pattern, !showsCandidates, !showsCandidateAR, let solution, !saved else { return }
            save(offset:solution.headingOffset,label:"\(solution.matches.count)-star pattern",
                message:String(format:"Pattern confirmed with %d stars · fit RMS %.2f°",solution.matches.count,solution.residualDegrees))
        }
        .sheet(isPresented:$showsCandidates) {
            CalibrationCatalogView(engine:engine,onChoose:chooseCandidate,onViewAR:{
                showsCandidateAR = true; showsCandidates = false
            }).celyxSheet(detents:[.large])
        }
        .onChange(of:showsCandidates) { _, _ in engine.isBrowsing = showsCandidates || showsCandidateAR }
        .onChange(of:showsCandidateAR) { _, _ in engine.isBrowsing = showsCandidates || showsCandidateAR }
        .confirmationDialog("Use \(target?.name ?? "this candidate") as the detected light?",isPresented:$confirmsSingleIdentity,titleVisibility:.visible) {
            Button("Confirm single-object reference") { calibrate() }
            Button("Cancel",role:.cancel) {}
        } message: {
            Text("A single light cannot independently establish its catalog identity. This saves a manual correction for the candidate you confirm.")
        }
        .onDisappear(perform:stop)
        .onChange(of:phase) { _, value in
            guard previewState == nil else { return }
            if value == .active, !cameraDenied { engine.start() }
            else { engine.stop(); if value == .background { engine.alignment.enterBackground() } }
        }
    }
    @Environment(\.scenePhase) private var phase

    // MARK: Calibration controls

    private var panel: some View {
        ZStack(alignment:.top) {
            CelyxBluePanel(cornerRadius:34)
            CelyxGrabber()
            VStack(alignment:.leading,spacing:12) {
                Text(mode == .reference ? "Calibrate with a reference" : "Calibrate with visible lights")
                    .font(.system(size:22,weight:.bold)).foregroundStyle(CelyxColor.primaryLabel)
                Text(instruction).font(.system(size:13)).foregroundStyle(CelyxColor.secondaryLabel)
                    .fixedSize(horizontal:false,vertical:true)
                if mode == .reference {
                    if referenceTargets.count > 1 {
                        ScrollView(.horizontal,showsIndicators:false) {
                            HStack(spacing:8) {
                                ForEach(referenceTargets) { item in
                                    Button {
                                        selectedID = item.id; selectedFromCatalog = !targets.contains(where:{ $0.id == item.id })
                                        outcome = .none; engine.resetSearch()
                                    } label: {
                                        Text(item.name).font(.system(size:13,weight:.medium)).foregroundStyle(.white)
                                            .padding(.horizontal,12).frame(height:32)
                                    }.buttonStyle(.plain)
                                        .glassEffect(item.id == target?.id ? .regular.tint(.white.opacity(0.3)).interactive() : .regular.interactive(),in:Capsule())
                                }
                            }
                        }
                    }
                    TimelineView(.periodic(from:.now,by:0.2)) { _ in readout }
                    CelyxPillButton(title:engine.referenceReady || previewState != nil ? "Confirm reference identity" : "Put the object in the circle",
                        style:target != nil && (engine.referenceReady || previewState != nil) && !saved ? .primary : .disabled,action:{
                            if selectedFromCatalog { confirmsSingleIdentity = true } else { calibrate() }
                        })
                    Button("Choose another candidate or compare visible lights") { choose(.pattern) }
                        .font(.system(size:13,weight:.semibold)).foregroundStyle(CelyxColor.primaryLabel)
                } else {
                    HStack {
                        Text("Detected lights").foregroundStyle(.white.opacity(0.65))
                        Spacer()
                        Text("\(previewState == nil ? engine.lights.count : previewState == .singleLight ? 1 : 4) · one or more").foregroundStyle(.white).monospacedDigit()
                    }.font(.system(size:13))
                    if !saved {
                        ProgressView(value:progress).tint(CelyxColor.ready)
                        Text(previewState == .matching ? "Comparing 4 lights with nearby catalog patterns… Hold steady." : engine.message)
                            .font(.system(size:13)).foregroundStyle(.white.opacity(0.8)).fixedSize(horizontal:false,vertical:true)
                    }
                    Text("One light can be used after you choose and confirm its reference. Additional lights help the app compare patterns automatically.")
                        .font(.system(size:12)).foregroundStyle(.white.opacity(0.55))
                    CelyxPillButton(title:"Choose a reference · Calibration Stars",style:.primary) { showsCandidates = true }
                    if !targets.isEmpty {
                        Button("Use a known Sun, Moon or star instead") { choose(.reference) }
                            .font(.system(size:13,weight:.semibold)).foregroundStyle(CelyxColor.primaryLabel)
                    }
                }
                statusLine
                if saved {
                    CelyxPillButton(title:"Done",style:.primary,action:close)
                } else if SkyCalibration.isCalibrated {
                    Button("Reset saved calibration") {
                        guard previewState == nil else { return }
                        SkyCalibration.reset(); outcome = .none; engine.resetSearch()
                    }
                        .font(.system(size:13)).foregroundStyle(.white.opacity(0.7))
                }
            }.padding(.horizontal,20).padding(.top,28).padding(.bottom,22)
        }.fixedSize(horizontal:false,vertical:true)
    }
    private var catalogARPanel: some View {
        ZStack(alignment:.top) {
            CelyxBluePanel(cornerRadius:34)
            CelyxGrabber()
            catalogARContent.padding(.horizontal,20).padding(.top,28).padding(.bottom,22)
        }.fixedSize(horizontal:false,vertical:true)
    }

    private var catalogARContent: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("Calibration catalog").font(.system(size:22,weight:.bold))
            Text("This maps the separate Calibration Stars list. Markers are possible reference positions, not camera identifications.")
                .font(.system(size:13)).foregroundStyle(CelyxColor.secondaryLabel)
                .fixedSize(horizontal:false,vertical:true)
            if let candidate = engine.candidates.first(where:{ $0.id == engine.selectedCatalogID }) {
                Text(candidate.star.title).font(.system(size:17,weight:.semibold))
                Text(String(format:"%.0f° up · %.0f° azimuth",candidate.altitude,candidate.azimuth))
                    .font(.system(size:13)).foregroundStyle(CelyxColor.secondaryLabel)
                if let guide = engine.predictions.first(where:{ $0.id == candidate.id })?.guide {
                    Text(guide.isAligned ? "Near the center of your view" : abs(guide.arrow.dx) > abs(guide.arrow.dy)
                         ? (guide.arrow.dx > 0 ? "Turn right toward this candidate" : "Turn left toward this candidate")
                         : (guide.arrow.dy > 0 ? "Point lower toward this candidate" : "Point higher toward this candidate"))
                        .font(.system(size:13)).foregroundStyle(CelyxColor.secondaryLabel)
                }
                CelyxPillButton(title:"Use as a reference",style:.primary) { chooseCandidate(candidate) }
            }
            Button("Open Calibration Stars") { showsCandidates = true }
                .font(.system(size:13,weight:.semibold))
        }.foregroundStyle(CelyxColor.primaryLabel)
    }
    // MARK: Reference selection

    private func chooseCandidate(_ candidate: CalibrationCandidate) {
        selectedID = candidate.id; engine.selectedCatalogID = candidate.id
        selectedFromCatalog = true; choseMode = true; mode = .reference; outcome = .none
        engine.patternEnabled = false; showsCandidateAR = false; showsCandidates = false
    }
    private var instruction: String {
        if cameraDenied { return "Allow camera access in Settings to calibrate." }
        if saved { return "Direction correction saved. Check another part of the sky before collecting." }
        if mode == .pattern {
            return "Put a real light in the circle. If only one is visible, choose its possible identity from Calibration Stars and confirm it. If more are visible, the app also checks their relative positions."
        }
        guard location != nil || previewState != nil else { return "Finding your location…" }
        guard let target else { return "No suitable bright reference is above the horizon. Use the star-pattern method." }
        return "If you can recognize \(target.name), aim at its real light and hold steady. The direction below is an estimate until you confirm the object."
    }
    @ViewBuilder private var readout: some View {
        if let target {
            VStack(alignment:.leading,spacing:4) {
                row("\(target.name) is at",String(format:"%.0f° · %.0f° up",degrees(target.azimuth),target.altitude*180 / .pi))
                if let ar = arAim() {
                    let turn = SkyCalibration.wrap(target.azimuth-(ar.azimuth+SkyCalibration.arHeadingOffset))*180 / .pi
                    row("Estimated turn",String(format:"%.0f° %@",abs(turn),turn > 0 ? "right" : "left"))
                }
                row("Camera light",engine.referenceReady ? "Steady in circle" : "Waiting for a steady light")
            }
        }
    }
    private func row(_ label: String,_ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.white.opacity(0.55)); Spacer(); Text(value).foregroundStyle(.white).monospacedDigit() }
            .font(.system(size:13))
    }
    @ViewBuilder private var statusLine: some View {
        switch outcome {
        case .saved(let message): Label(message,systemImage:"checkmark.circle.fill").foregroundStyle(CelyxColor.ready)
        case .failed(let message): Label(message,systemImage:"exclamationmark.circle.fill").foregroundStyle(.orange)
        case .none:
            if let motionMessage { Text(motionMessage).foregroundStyle(.white.opacity(0.55)) }
        }
    }
    private func choose(_ value: Mode) {
        choseMode = true; mode = value; outcome = .none; engine.patternEnabled = value == .pattern
    }
    private func start() async {
        guard previewState == nil else { return }
        if AppPreviewData.isRunning {
            targets = [.init(id:CatalogStar.sun.id,name:"Sun",direction:SIMD3(0.6,0,0.8),isDisc:true)]
            return
        }
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for:.video) {
        case .authorized: granted = true
        case .notDetermined: granted = await AVCaptureDevice.requestAccess(for:.video)
        default: granted = false
        }
        guard granted else { cameraDenied = true; return }
        engine.start()
        let service = motion ?? MotionService(); motion = service
        service.onLocation = { fix in location = fix; engine.location = fix; refreshTargets() }
        service.onCalibration = { ready,_,message,_ in motionMessage = ready ? nil : message }
        service.onAttitude = { value in attitude = value; attitudeDate = Date() }
        service.start { _,_,_ in }
    }
    private func stop() { engine.stop(); motion?.stop() }
    private func close() { stop(); onClose() }
    private func arAim() -> (azimuth: Double,altitude: Double)? {
        guard let frame = engine.session.currentFrame, case .normal = frame.camera.trackingState else { return nil }
        let d = -frame.camera.transform.columns.2
        return (atan2(Double(d.x),Double(-d.z)),asin(min(1,max(-1,Double(d.y)))))
    }
    private func motionAim() -> Double? {
        guard let attitude, let attitudeDate, abs(attitudeDate.timeIntervalSinceNow) < 0.5 else { return nil }
        let d = -attitude.columns.2
        return atan2(d.x,d.y)
    }
    private func refreshTargets() {
        guard let location else { return }
        let sky = AstronomyService.snapshot(date:Date(),location:location)
        func make(_ star: CatalogStar,_ direction: SIMD3<Double>,disc: Bool) -> Target {
            Target(id:star.id,name:star.title,direction:Refraction.apparent(direction),isDisc:disc)
        }
        var list: [Target] = []
        if sky.sunAltitude > 5 { list.append(make(.sun,sky.sunDirection,disc:true)) }
        if asin(sky.moonDirection.z)*180 / .pi > 5 && sky.moonIllumination > 0.15 { list.append(make(.moon,sky.moonDirection,disc:true)) }
        if sky.sunAltitude < -6 {
            list += sky.planets.filter { $0.star.mag < 1.5 && $0.direction.z > sin(10 * .pi/180) }
                .sorted { $0.star.mag < $1.star.mag }.map { make($0.star,$0.direction,disc:false) }
            list += catalogue.filter { $0.mag < 1.3 }.sorted { $0.mag < $1.mag }
                .map { ($0,sky.direction(ra:$0.ra_deg,dec:$0.dec_deg)) }
                .filter { $0.1.z > sin(15 * .pi/180) }.prefix(6).map { make($0.0,$0.1,disc:false) }
        }
        targets = list
        if !list.contains(where:{ $0.id == selectedID }) && !engine.candidates.contains(where:{ $0.id == selectedID }) {
            selectedID = list.first?.id
        }
        if !choseMode { mode = list.isEmpty ? .pattern : .reference; engine.patternEnabled = mode == .pattern }
    }
    // MARK: Save calibration

    private func calibrate() {
        guard previewState == nil, let target, engine.referenceReady, let ray = engine.centerDirection else { return }
        let d = target.direction
        let expected = SIMD3(Float(d.x),Float(d.z),Float(-d.y))
        guard let offset = CalibrationReference.correction(expected:expected,observed:ray), !target.isDisc || engine.centerIsDisc else {
            outcome = .failed("The light does not fit this reference’s height or shape. Check the object, or use pattern matching."); return
        }
        save(offset:offset,label:target.name,
            message:"Calibrated using the confirmed reference \(target.name).")
    }
    private func save(offset: Double,label: String,message: String) {
        guard previewState == nil else { return }
        let garden = arAim().flatMap { ar in motionAim().map { SkyCalibration.wrap(ar.azimuth+offset-$0) } }
        SkyCalibration.save(arOffset:offset,motionOffset:garden,target:label)
        // Replace the old local quaternion without resetting the AR world we just calibrated.
        engine.alignment.save(rotation:simd_quatf(angle:0,axis:SIMD3(0,1,0)),reference:label,date:Date(),location:location)
        outcome = .saved(message+(garden == nil ? " Garden direction still needs a fresh motion reading." : " Camera and garden updated."))
    }
    private func degrees(_ value: Double) -> Double { (value*180 / .pi+360).truncatingRemainder(dividingBy:360) }
}

#Preview("Calibration · known object") {
    SkyCalibrationView(catalogue:[],preview:.reference) {}
}
#Preview("Calibration · star pattern") {
    SkyCalibrationView(catalogue:[],preview:.pattern) {}
}
#Preview("Calibration · matching") {
    SkyCalibrationView(catalogue:[],preview:.matching) {}
}
#Preview("Calibration · saved") {
    SkyCalibrationView(catalogue:[],preview:.saved) {}
}

#Preview("Calibration · one light") {
    SkyCalibrationView(catalogue:AppPreviewData.model.stars,preview:.singleLight) {}
}
#Preview("Calibration · catalog AR") {
    SkyCalibrationView(catalogue:AppPreviewData.model.stars,preview:.catalogAR) {}
}
