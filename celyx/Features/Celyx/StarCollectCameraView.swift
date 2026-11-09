import SwiftUI
import ARKit

/// Real star collecting, styled like Figma "Camera Stand by" / "Camera Scanned" / "Camera Captured".
///
/// `SkyFinderService` does the work: GPS + true-north camera orientation (ARKit) project the HYG catalogue
/// onto the live camera image, and `CameraStarDetector` looks for an actual point of light at that spot.
/// The crosshair never moves: only what sits inside the centre circle is scanned. Star collection needs
/// fresh optical evidence. Tapping the camera captures the current frame immediately
/// and opens its album; verification happens during live scanning, before the tap.
struct StarCollectCameraView: View {
    /// What sits inside the centre circle right now.
    struct CenterTarget {
        let star: CatalogStar
        /// The actual point of light the camera sees there. Required to collect.
        let detection: CameraStarAnnotation?
        var id: Int { star.id }
    }

    /// How a successful collect hands over to the garden.
    enum CollectResult {
        /// The wormhole into the Night Sea (Home owns it from here).
        case wormhole(WormholeHandover)
        /// Reduce Motion: a plain cross-fade, then the sheet.
        case fade(itemID: Int?)
    }

    let model: HomeViewModel
    let onClose: () -> Void
    /// The running handover, if any (fades this screen's UI on its clock).
    var handover: WormholeHandover? = nil
    /// When set, a successful collect hands over to the garden (wormhole) instead of opening the album here.
    var onCollect: ((CollectResult) -> Void)? = nil
    @State private var service: SkyFinderService
    @State private var viewSize: CGSize = .zero
    @State private var errorMessage: String?
    @State private var zoomStart: Double?
    @State private var verification: Verification = .idle
    @State private var showsCalibration = false
    @State private var referenceCapture: CameraReferenceCapture?
    @State private var showsFilteredStars = false
    @State private var capturedItem: GardenCollectionItem?
    @State private var settledID: Int?
    /// Aim lock: once a star is collectible it stays the target while it's within `lockRadius` of the
    /// centre, even if a neighbour drifts closer, so small hand moves don't swap stars.
    @State private var lockedID: Int?
    /// A star the user closed with X: skipped until it leaves the lock radius, so a neighbour can be picked.
    @State private var dismissedID: Int?
    @State private var isLocking = false
    /// Capture cue ("cekrek"): when the shutter fired, and the frame frozen at that instant.
    @State private var captureStart: CFTimeInterval?
    @State private var captureImage: CGImage?
    /// The camera feed shows only once ARKit delivers real frames (no skewed first frames).
    @State private var feedReady = false
    #if DEBUG
    /// Demo sky: a fake Rigel fixed in the AR world (nil = off). Never saved.
    @State private var demoDirection: SIMD3<Float>?
    @State private var demoPoint: CGPoint?
    @State private var demoArrow: CGVector?
    @State private var demoChecking = false
    private var demoOn: Bool { demoDirection != nil }
    private var demoStar: CatalogStar? { DemoSky.star(in:model.stars) }
    #else
    private var demoOn: Bool { false }
    #endif
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Verification: Equatable { case idle, checking(Int), failed(Int) }
    /// Crosshair radius plus a little slack for hand shake.
    private let captureRadius: CGFloat = 28
    /// Hold radius for a locked star: covers hand shake, small enough that a deliberate move releases it.
    private let lockRadius: CGFloat = 56
    private var isChecking: Bool { if case .checking = verification { true } else { false } }

    init(model: HomeViewModel,handover: WormholeHandover? = nil,onCollect: ((CollectResult) -> Void)? = nil,onClose: @escaping () -> Void) {
        self.model = model
        self.handover = handover
        self.onCollect = onCollect
        self.onClose = onClose
        _service = State(initialValue:SkyFinderService(location:model.location,catalogue:model.stars,alignment:model.cameraAlignment))
    }

    private var center: CGPoint { CGPoint(x:viewSize.width/2,y:viewSize.height/2) }
    private func distance(_ point: CGPoint) -> CGFloat { hypot(point.x-center.x,point.y-center.y) }

    /// Predictions use visibility estimates. A repeatedly observed, identified night-sky
    /// light can still be collected when a cloud or light-pollution estimate disagrees.
    private var centerTarget: CenterTarget? {
        if let lockedID, let held = lockedTarget(lockedID) { return held }
        return rawCenterTarget
    }

    /// The locked star, if it's still in view within the hold radius.
    private func lockedTarget(_ id: Int) -> CenterTarget? {
        #if DEBUG
        if demoOn {
            guard let star = demoStar, star.id == id, let point = demoPoint, viewSize != .zero, distance(point) <= lockRadius else { return nil }
            return CenterTarget(star:star,detection:CameraStarAnnotation(star:star,point:point,size:CGSize(width:28,height:28)))
        }
        #endif
        guard service.status == .tracking, viewSize != .zero else { return nil }
        let observations = service.annotations + (service.reacquiredPinnedAnnotation.map { [$0] } ?? [])
        if let seen = observations.first(where:{ $0.id == id && distance($0.point) <= lockRadius }) {
            return CenterTarget(star:seen.star,detection:seen)
        }
        let tolerance = min(25,max(10,(service.cameraHeadingAccuracy ?? 15)+5))
        if let body = service.brightBodiesNearAim().first(where:{ $0.star.id == id && $0.separation <= tolerance }) {
            return CenterTarget(star:body.star,detection:nil)
        }
        return nil
    }

    /// How far the locked star sits from the screen centre (zero when nothing is locked, or for a body
    /// matched by angle with no light on screen).
    private var lockOffset: CGSize {
        guard let point = shownTarget?.detection?.point, viewSize != .zero else { return .zero }
        return CGSize(width:point.x-center.x,height:point.y-center.y)
    }

    /// Is the star the user dismissed still near the centre?
    private var dismissedIsNear: Bool {
        guard let dismissedID else { return false }
        #if DEBUG
        if demoOn { return demoStar?.id == dismissedID && demoPoint.map { distance($0) <= lockRadius } == true }
        #endif
        return (service.annotations+(service.reacquiredPinnedAnnotation.map { [$0] } ?? []))
            .contains { $0.id == dismissedID && distance($0.point) <= lockRadius }
            || service.brightBodiesNearAim().contains { $0.star.id == dismissedID && $0.separation <= 25 }
    }

    private var rawCenterTarget: CenterTarget? {
        #if DEBUG
        if demoOn {
            // The demo star feeds the real flow: it counts as a detected light only while it sits in the circle.
            guard let star = demoStar, star.id != dismissedID, let point = demoPoint, viewSize != .zero, distance(point) <= captureRadius else { return nil }
            return CenterTarget(star:star,detection:CameraStarAnnotation(star:star,point:point,size:CGSize(width:28,height:28)))
        }
        #endif
        if service.isPinnedLightCentered,
           let pin = service.pinnedLight, pin.isIdentified, let star = pin.match?.star,
           let point = service.pinnedLightGuide?.point, distance(point) <= 40 {
            return CenterTarget(star:star,detection:service.reacquiredPinnedAnnotation
                ?? service.annotations.first(where:{ $0.id == star.id && distance($0.point) <= captureRadius }))
        }
        guard service.status == .tracking, !service.isAdjustingCamera, viewSize != .zero else { return nil }
        let visible = Set(service.viewableObjects.map(\.id))
        let observations = service.annotations + (service.reacquiredPinnedAnnotation.map { [$0] } ?? [])
        if let seen = observations
            .filter({ annotation in
                let observedAtNight = (service.sunAltitude ?? 90) < -6 && !annotation.star.isSolarDisc
                    && (annotation.sourceDirection?.y ?? -1) > sin(5 * Float.pi/180)
                return annotation.id != dismissedID
                    && (visible.contains(annotation.id) || observedAtNight) && distance(annotation.point) <= captureRadius
            })
            .min(by:{ distance($0.point) < distance($1.point) }) {
            return CenterTarget(star:seen.star,detection:seen)
        }
        // While returning to an observed pin, a different catalog marker alone
        // must not replace that light or expose an unrelated Collect action.
        if service.pinnedLight != nil { return nil }
        // Sun, Moon and planets: judged by angle, tolerant to the phone compass error.
        // The Collect check then demands the real bright light inside the circle.
        let tolerance = min(25,max(10,(service.cameraHeadingAccuracy ?? 15)+5))
        if let body = service.brightBodiesNearAim()
            .filter({ $0.star.id != dismissedID && visible.contains($0.star.id) && $0.separation <= tolerance })
            .min(by:{ $0.separation < $1.separation }) {
            return CenterTarget(star:body.star,detection:nil)
        }
        // An ordinary star's predicted position is never presented as a detection.
        // The filtered catalog remains available in the separate AR map.
        return nil
    }
    /// Crosshair interaction (ours): his target shows as collectible (Enable) after a short lock (Locking).
    private var shownTarget: CenterTarget? {
        guard let target = centerTarget, target.id == settledID else { return nil }
        return target
    }
    /// The native target sheet shows while a target is collectible and nothing else is on screen.
    private var showsTargetSheet: Bool {
        shownTarget != nil && handover == nil && captureStart == nil && !showsCalibration && !showsFilteredStars
            && referenceCapture == nil && capturedItem == nil
    }

    var body: some View {
        NavigationStack {
            TimelineView(.animation(paused:handover == nil && captureStart == nil)) { _ in
                let frame = handover.map { $0.frame($0.tt()) }
                let shutter = captureStart.map { (CACurrentMediaTime()-$0)*1000 }
                cameraContent(cameraUI:frame?.cameraUI ?? 1,crosshair:frame?.crossAlpha ?? 1,shutter:shutter)
            }
        }
    }

    private func cameraContent(cameraUI: Double,crosshair: Double,shutter: Double?) -> some View {
        ZStack(alignment:.bottom) {
            GeometryReader { geometry in
                ZStack {
                    if service.isCameraRunning {
                        SkyCameraPreview(session:service.session,onViewport:service.updateViewport,
                            onTap:{ point in
                                if let target = shownTarget { collect(target) }
                                else { _ = service.focus(at:point) }
                            },
                            onExposureDrag:{ translation,_,ended in service.dragExposure(translation:translation,ended:ended) },
                            zoom:service.cameraZoom)
                            // Hidden behind the night colour until ARKit delivers real frames, then a quick fade.
                            .opacity(feedReady ? 1 : 0)
                            .animation(.easeOut(duration:0.2),value:feedReady)
                            #if DEBUG
                            .simultaneousGesture(LongPressGesture(minimumDuration:0.6).onEnded { _ in toggleDemoSky() })
                            #endif
                            .simultaneousGesture(MagnifyGesture()
                                .onChanged { value in
                                    if zoomStart == nil { zoomStart = service.cameraZoom }
                                    service.setZoom((zoomStart ?? 1)*value.magnification)
                                }
                                .onEnded { _ in zoomStart = nil })
                    } else {
                        CelyxColor.night
                    }
                    #if DEBUG
                    if let point = demoPoint, let star = demoStar, handover == nil {
                        DemoStarView(color:star.rgb).position(point)
                    }
                    #endif
                    // Cekrek: the frame freezes at the click and over-exposes until the wormhole takes it.
                    if let shutter, shutter < CaptureFlash.duration { CaptureFlashView(image:captureImage,t:shutter) }
                    if let handover { WormholeHandoverView(handover:handover) }
                    // CrosshairView's reticle sits 10pt above its own centre (see crosshair README).
                    // Gimbal lock: once a star is collectible the crosshair, its label and the pill ride on the
                    // star itself; they glide over on a spring when it locks and glide home when it lets go.
                    let lock = lockOffset
                    reticle.position(x:geometry.size.width/2+lock.width,y:geometry.size.height/2+10+lock.height).allowsHitTesting(false)
                        .opacity(crosshair)
                        .animation(.spring(duration:0.45,bounce:0.12),value:shownTarget?.id)
                    // "Collect Rigel" hangs just under the crosshair's star label (reticle centre + 80pt).
                    if let target = shownTarget, !isChecking, handover == nil, captureStart == nil,
                       model.collected[target.star.id] == nil || demoOn {
                        CollectPill(title:"Collect \(target.star.title)") { collect(target) }
                            .id(target.star.id)
                            .position(x:geometry.size.width/2+lock.width,y:geometry.size.height/2+80+lock.height)
                            .animation(.spring(duration:0.45,bounce:0.12),value:shownTarget?.id)
                            .opacity(crosshair)
                            .transition(.opacity.combined(with:.scale(scale:0.9,anchor:.top)))
                    }
                    if service.pinnedLight != nil, let guide = service.pinnedLightGuide {
                        CameraPinnedLightOverlay(guide:guide,title:pinnedLightTitle,isRecognizing:isAnalyzingLight,
                            subtitle:service.pinnedLight?.match == nil ? nil : "Estimated identity")
                    }
                }
                .scaleEffect(shutter.map(CaptureFlash.squeeze) ?? 1)
                .overlay { Color.white.opacity(shutter.map(CaptureFlash.white) ?? 0).allowsHitTesting(false) }
                .onAppear { viewSize = geometry.size }
                .onChange(of:geometry.size) { _, size in viewSize = size }
            }
            .ignoresSafeArea()

            Group {
                if shownTarget != nil {
                    EmptyView()                                     // shown in the native sheet below
                } else if service.pinnedLight != nil {
                    pinnedLightPanel.padding(.horizontal,6).padding(.bottom,6)
                } else {
                    CelyxHintPill(text:hintText,isLoading:isAnalyzingLight).padding(.bottom,59).transition(.opacity)
                }
            }
            .opacity(cameraUI)
            #if DEBUG
            if demoOn { DemoSkyPill().frame(maxHeight:.infinity,alignment:.top).padding(.top,8).opacity(cameraUI) }
            #endif
        }
        .allowsHitTesting(handover == nil && captureStart == nil)
        .overlay(alignment:.trailing) {
            if service.exposureControlVisible {
                CameraExposureControl(minimum:service.minimumExposure,maximum:service.maximumExposure,
                    value:Binding(get:{ service.exposureBias },set:{ service.setExposure($0) }),
                    message:service.cameraControlMessage,onReset:{ service.setExposure(0) },
                    onEditingChanged:service.setExposureEditing)
                    .padding(.trailing,12).transition(.opacity)
            }
        }
        .background(CelyxColor.night)
        // Ferdi's collectible sheet, presented natively: fixed height, no grabber, no close; the camera behind it
        // stays tappable (tap anywhere to capture) and it closes by itself when the star leaves the circle.
        .sheet(isPresented:Binding(get:{ showsTargetSheet },set:{ _ in })) {
            Group {
                if let target = shownTarget { sheet(for:target) } else { Color.clear.frame(height:1) }
            }
            .presentationDetents([.height(targetSheetHeight)])
            .presentationDragIndicator(.hidden)
            .presentationBackgroundInteraction(.enabled)
            .presentationBackground { CelyxBluePanel(cornerRadius:34) }
            .presentationCornerRadius(34)
            .interactiveDismissDisabled()
        }
        .toolbarBackground(.hidden,for:.navigationBar)
        .toolbar(handover == nil && captureStart == nil ? .automatic : .hidden,for:.navigationBar)
        .toolbar {
            ToolbarItem(placement:.topBarLeading) {
                Button("Back",systemImage:"chevron.left") { service.stop(); onClose() }.labelStyle(.iconOnly)
            }
            ToolbarItemGroup(placement:.topBarTrailing) {
                Button("Filtered Stars",systemImage:"list.star") { service.stop(); showsFilteredStars = true }
                Button("Calibrate direction",systemImage:"scope") { service.stop(); showsCalibration = true }.labelStyle(.iconOnly)
                #if DEBUG
                // Debug: one tap toggles the demo sky (a fake Rigel to try the whole collect flow indoors).
                Button(demoOn ? "Demo on" : "Demo",systemImage:demoOn ? "sparkles" : "sparkle") { toggleDemoSky() }
                #endif
            }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .spring(duration:0.35),value:shownTarget?.id)
        .task {
            if onCollect != nil { WormholeFeedback.shared.prepare() }
            service.updateVisibility(quality:model.quality,atmosphere:model.atmosphere)
            await service.start()
        }
        .onDisappear { service.stop() }
        // Lock the star the moment it becomes collectible; release it once it leaves the hold radius.
        .onChange(of:shownTarget?.id) { _, id in if let id { lockedID = id } }
        .onChange(of:centerTarget?.id) { _, id in if id == nil || id != lockedID { lockedID = nil } }
        .onChange(of:dismissedIsNear) { _, near in if !near { dismissedID = nil } }
        .task(id:centerTarget?.id) {
            guard let target = centerTarget else { isLocking = false; settledID = nil; return }
            if settledID == target.id { return }
            settledID = nil; isLocking = true
            try? await Task.sleep(for:.seconds(0.7))
            guard !Task.isCancelled else { return }
            isLocking = false; settledID = target.id
        }
        .task {
            // Wait for the first real AR frame, plus a couple more so the preview has its orientation.
            while !Task.isCancelled && service.session.currentFrame == nil { try? await Task.sleep(for:.milliseconds(40)) }
            try? await Task.sleep(for:.milliseconds(90))
            feedReady = true
        }
        #if DEBUG
        .task(id:demoOn) {
            // Keep the demo star glued to its place in the sky while the phone moves.
            while demoOn && !Task.isCancelled {
                if let direction = demoDirection, let projection = service.demoProjection(world:direction) {
                    demoPoint = projection.point; demoArrow = projection.arrow
                }
                try? await Task.sleep(for:.milliseconds(33))
            }
        }
        #endif
        .onChange(of:phase) { _, value in
            if value == .active, !showsCalibration, !showsFilteredStars, capturedItem == nil { Task { await service.start() } }
            else if value == .background { service.suspendForBackground() }
            else { service.stop() }
        }
        .sheet(item:$referenceCapture) { capture in
            CameraReferencePickerView(capture:capture,onConfirm:{ service.confirmFirstReference(capture,star:$0) })
                .celyxSheet(detents:[.large])
        }
        .fullScreenCover(isPresented:$showsCalibration,onDismiss:{ Task { await service.start() } }) {
            SkyCalibrationView(catalogue:model.stars,alignment:model.cameraAlignment) { showsCalibration = false }
        }
        .fullScreenCover(isPresented:$showsFilteredStars,onDismiss:{ Task { await service.start() } }) {
            FilteredStarsView(model:model)
        }
        .fullScreenCover(item:$capturedItem,onDismiss:{ Task { await service.start() } }) { item in
            StarAlbumView(item:item,onSaveNote:{ model.updateObservationNote(id:item.id,note:$0) },
                onSavePlace:{ model.updateObservationPlace(id:item.id,name:$0) })
        }
        .alert("Camera",isPresented:Binding(get:{ errorMessage != nil },set:{ if !$0 { errorMessage = nil } })) {
            Button("Try Again",role:.cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Crosshair (always fixed at the centre of the screen)

    /// Figma "Crosshair" component (node 922:1567) with its own motion, sound and haptics.
    private var reticle: some View {
        let star = shownTarget?.star
        let label = star?.id == service.pinnedLight?.match?.star.id ? "" : star?.title ?? ""
        // During the wormhole the handover owns the audio and haptics: the crosshair stays silent.
        return CrosshairView(state:crosshairState,label:label,soundEnabled:handover == nil,hapticsEnabled:handover == nil)
    }
    private var crosshairState: CrosshairState {
        if isChecking { return .validating }
        if shownTarget != nil { return .enable }
        if isLocking || isAnalyzingLight { return .locking }
        return .default
    }

    private var hintText: String {
        #if DEBUG
        if demoOn {
            guard let point = demoPoint else {
                if let arrow = demoArrow {
                    let way = abs(arrow.dx) > abs(arrow.dy) ? (arrow.dx > 0 ? "right" : "left") : (arrow.dy > 0 ? "down" : "up")
                    return "Turn \(way) to find Rigel"
                }
                return "Look around to find Rigel"
            }
            return distance(point) <= captureRadius ? "Rigel is in your circle. Tap to collect" : "Rigel is close. Put it in your circle"
        }
        #endif
        switch service.status {
        case .tracking: break
        case .preparing: return "Finding your place under the sky…"
        case .requestingPermission: return "Allow camera and location to find stars"
        case .limited(let message), .unavailable(let message), .denied(let message): return message
        }
        if service.isAdjustingCamera { return "Letting the camera settle… Hold steady" }
        if let issue = centeredLightIssue {
            switch issue {
            case .stabilizing: return "Light found. Checking its name… Hold steady"
            case .compass: return "Light found. Tap the scope to calibrate direction."
            case .noCandidate: return "Light found, but no clear catalog match. Check alignment."
            case .ambiguous: return "Several stars fit this light. Calibrate direction to check."
            case .alignment: return "Light found, but its position is off. Recalibrate direction."
            }
        }
        if isAnalyzingLight { return "Scanning faint starlight… Hold steady for a moment" }
        let sun = service.sunAltitude ?? -90
        if sun >= -0.833 { return "It’s daytime. Only the Sun can be collected now" }
        if sun >= -6 { return "The sky is still too bright for stars" }
        return service.pointScanProgress >= 1 ? "No steady point yet. Adjust your aim, or tap the star to focus." : "Point your circle at a star"
    }

    private var centeredLightIssue: CameraIdentificationIssue? {
        service.unidentifiedLights.filter { distance($0.point) <= captureRadius }
            .min { distance($0.point) < distance($1.point) }?.issue
    }
    private var isAnalyzingLight: Bool {
        guard service.status == .tracking else { return false }
        if service.isScanningNewLight { return true }
        if service.pinnedLight?.isIdentified == true { return false }
        if service.isAdjustingCamera { return true }
        if service.pinnedLight != nil {
            if service.reacquiredPinnedAnnotation != nil { return false }
            return service.isRecognizingPinnedLight
        }
        if let issue = centeredLightIssue { return issue == .stabilizing }
        return service.isGatheringInitialLight && service.pointScanProgress > 0 && service.pointScanProgress < 1
    }

    // MARK: Sheet

    private var pinIsInReticle: Bool {
        service.pinnedLightGuide?.point.map { distance($0) <= captureRadius } ?? false
    }
    private var pinnedLightTitle: String {
        guard let star = service.pinnedLight?.match?.star else { return "Last seen light" }
        return star.title
    }

    private var pinnedLightPanel: some View {
        VStack(alignment:.leading,spacing:12) {
            if let issue = service.newLightIssue {
                HStack(spacing:8) {
                    if service.isScanningNewLight { ProgressView().tint(CelyxColor.primaryLabel) }
                    else { Image(systemName:"sparkle.magnifyingglass") }
                    Text(issue == .stabilizing ? "New light · matching its direction…" : "New light · \(issue.title)")
                        .font(.system(size:13))
                }
            }
            HStack(spacing:10) {
                if isAnalyzingLight { ProgressView().tint(CelyxColor.primaryLabel) }
                Text(pinnedLightTitle)
                    .font(.system(size:17,weight:.semibold))
                Spacer()
                Button("Clear pin") { service.clearPinnedLight() }
                    .font(.system(size:13,weight:.semibold))
            }
            if service.pinnedLight?.match != nil {
                Text("Estimated identity").font(.system(size:12,weight:.medium))
                    .foregroundStyle(CelyxColor.secondaryLabel)
            }
            Text(pinnedLightInstruction)
                .font(.system(size:13)).foregroundStyle(CelyxColor.secondaryLabel)
                .fixedSize(horizontal:false,vertical:true)
            if !service.hasReferenceAlignment {
                Button {
                    if let capture = service.captureFirstReference() { referenceCapture = capture }
                    else { errorMessage = "Keep the light visible, then try aligning again." }
                } label: {
                    Label("Improve direction (optional)",systemImage:"scope")
                        .font(.system(size:13,weight:.semibold))
                }.buttonStyle(.plain)
            }
        }.padding(20).foregroundStyle(CelyxColor.primaryLabel).background(CelyxBluePanel(cornerRadius:28))
    }

    private var pinnedLightInstruction: String {
        if !service.hasReferenceAlignment {
            if let issue = service.pinnedLight?.issue, service.pinnedLight?.match == nil {
                return issue == .stabilizing ? "Light detected. Checking nearby catalog candidates…" : issue.message
            }
            return "The light is detected. Its name is an estimate from direction, time and location. Aligning is optional and improves accuracy."
        }
        guard service.status == .tracking else {
            return "Tracking is adjusting. Your last light is saved; move slowly to steady the guide."
        }
        if service.isAdjustingCamera { return "Applying camera settings. Your last light stays pinned." }
        if service.pinnedLight?.isIdentified == true {
            return pinIsInReticle
                ? "Identification saved. Waiting for fresh light in the circle before collecting."
                : "Identification saved. Follow the arrow back to the last detected light."
        }
        if pinIsInReticle {
            if service.reacquiredPinnedAnnotation != nil { return "Light detected again. Getting your collection ready." }
            if service.pinnedLight?.issue == .ambiguous {
                return "Light found, but several names fit. Check direction calibration to identify it."
            }
            return "Back at the saved position. Checking fresh camera frames for this light…"
        }
        if service.isRecognizingPinnedLight {
            return "Checking the saved direction. You can move; the last light stays pinned."
        }
        if service.pinnedLight?.match != nil {
            return "Follow the arrow back to this light. Collecting needs a fresh sighting inside the circle."
        }
        return "No clear identity yet. Return to the pin or aim at another light. Check calibration if needed."
    }

    /// Ferdi's sheet heights, minus the 48pt action row that moved onto the crosshair (kept for "Collected").
    private var targetSheetHeight: CGFloat {
        guard let star = shownTarget?.star else { return 228 }
        let base: CGFloat = star.isSolarDisc ? 208 : 228
        return model.collected[star.id] != nil && !demoOn ? base : base-48
    }

    private func sheet(for target: CenterTarget) -> some View {
        let star = target.star
        let isCollected = model.collected[star.id] != nil && !demoOn
        let checking = verification == .checking(star.id)
        let failed = verification == .failed(star.id)
        return ZStack(alignment:.top) {
            VStack(spacing:0) {
                HStack(spacing:0) {
                    StarPortraitView(star:star)
                        .frame(width:64,height:64)
                        .shadow(color:Color(red:star.rgb.x,green:star.rgb.y,blue:star.rgb.z).opacity(0.8),radius:10)
                        .accessibilityHidden(true)
                    VStack(alignment:.leading,spacing:0) {
                        Text(star.title).font(.system(size:28,weight:.bold)).tracking(0.38).foregroundStyle(CelyxColor.primaryLabel)
                            .lineLimit(1).minimumScaleFactor(0.6).frame(height:34)
                        Text(subtitle(for:star)).font(.system(size:15,weight:.medium)).tracking(-0.23).foregroundStyle(CelyxColor.subtitle).frame(height:20)
                    }
                    .padding(.horizontal,16)
                    Spacer(minLength:0)
                    // Several stars close together: X lets go of this one so the next can lock.
                    CelyxCloseButton {
                        withAnimation(.smooth(duration:0.3)) {
                            dismissedID = star.id; lockedID = nil; settledID = nil
                        }
                    }
                    .accessibilityLabel("Not this star")
                }
                .padding(.horizontal,16).frame(height:64).padding(.top,24).padding(.bottom,8)
                if !star.isSolarDisc {
                    Text(service.hasReferenceAlignment ? "Estimated identity · direction aligned" : "Estimated identity · not independently confirmed")
                        .font(.system(size:12)).foregroundStyle(CelyxColor.secondaryLabel)
                        .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,16).padding(.top,4)
                }
                HStack(spacing:6) {
                    let color = failed ? Color.orange : CelyxColor.ready
                    Circle().fill(color).frame(width:6,height:6).shadow(color:color,radius:3)
                    Text("\(Text(statusText(for:star,checking:checking,failed:failed,collected:isCollected,fresh:target.detection != nil)).foregroundStyle(CelyxColor.primaryLabel))\(Text(directionText(for:star)).foregroundStyle(CelyxColor.secondaryLabel))")
                        .font(.system(size:12)).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength:0)
                }
                .frame(height:16).padding(16)
                // The capture action lives on the crosshair ("Collect Rigel"); the sheet only says what it is.
                if isCollected {
                    CelyxPillButton(title:"Collected",systemImage:"checkmark",style:.collected) {}
                        .allowsHitTesting(false)
                        .padding(.horizontal,16)
                }
            }
        }
        .frame(maxWidth:.infinity,alignment:.top)
        .contentShape(Rectangle())
        .onTapGesture { collect(target) }
    }

    private func statusText(for star: CatalogStar,checking: Bool,failed: Bool,collected: Bool,fresh: Bool) -> String {
        if collected { return "In your garden · " }
        if checking { return "Hold steady, checking its light · " }
        if failed { return "Couldn’t see it in the circle. Try again · " }
        if star.isSun { return "Visible now · Never look straight at it · " }
        if !fresh { return "Rechecking light · " }
        return "Visible now · "
    }
    private func subtitle(for star: CatalogStar) -> String {
        if star.isSolarSystemBody { return star.kind }
        if let code = star.con, let name = ConstellationNames.name(for:code) { return "Star in \(name)" }
        return "Star"
    }
    /// e.g. "High in the west", from the object's real altitude/azimuth at this place and time.
    private func directionText(for star: CatalogStar) -> String {
        guard let observation = service.viewableObjects.first(where:{ $0.id == star.id }) else { return "In your view" }
        let points = ["north","northeast","east","southeast","south","southwest","west","northwest"]
        let bearing = points[Int((observation.azimuth+22.5)/45) % 8]
        let height = observation.altitude >= 50 ? "High" : observation.altitude >= 20 ? "Up" : "Low"
        return "\(height) in the \(bearing)"
    }

    // MARK: Actions

    /// Capture this exact moment. Scanning already checked independent optical frames;
    /// a retained pin without fresh evidence cannot trigger a shutter.
    private func collect(_ target: CenterTarget) {
        #if DEBUG
        if demoOn {
            // Demo Rigel: the same path as a real collect (cekrek -> wormhole -> card), never saved.
            guard !isChecking, captureStart == nil, handover == nil else { return }
            verification = .checking(target.id)
            captureDemo(target)
            return
        }
        #endif
        guard !isChecking, capturedItem == nil, captureStart == nil, handover == nil, model.collected[target.id] == nil,
              service.status == .tracking, !service.isAdjustingCamera else { return }
        guard let current = centerTarget, current.id == target.id,
              current.detection != nil || (current.star.isSolarDisc && lightIsInCircle(for:current.star)) else {
            fail(target.id); return
        }
        verification = .checking(target.id)
        save(current)
    }

    /// Soft "not this time" cue (sound + two dull taps) instead of the harsh system error buzz,
    /// and mute the crosshair's automatic "back" sound so the two don't stack.
    private func fail(_ id: Int) {
        CrosshairFeedback.shared.suppress(.back,for:0.6)
        CrosshairFeedback.shared.play(CrosshairSound.fail)
        CrosshairFeedback.shared.play(CrosshairHaptic.fail)
        verification = .failed(id)
    }

    private func save(_ target: CenterTarget) {
        // The confirmed light: a detected source, or the bright source we just measured at the centre.
        let annotation = target.detection ?? CameraStarAnnotation(star:target.star,point:center,size:CGSize(width:28,height:28))
        let detail = target.detection?.estimatedSeparation.map {
            String(format:"Our best match is %@, based on direction and brightness. Direction offset: %.1f°.",target.star.title,$0)
        } ?? "Confirmed by direction, time and place, with a bright light seen in the circle."
        let note = (service.hasReferenceAlignment ? "" : "Uncalibrated catalog estimate; identity not independently confirmed. ")+detail
        guard let draft = service.captureObservation(annotation:annotation,identificationNote:note) else {
            fail(target.id)
            return
        }
        do {
            try model.saveCameraObservation(draft,note:"")
            if onCollect != nil && !reduceMotion {
                // From Home: cekrek -> wormhole -> land on the star -> its card (the Album opens from the card).
                captureThenHandover(itemID:target.star.id,point:target.detection?.point ?? center,
                                    freeze:service.wormholeFreeze() ?? .placeholder(size:viewSize))
                return
            }
            // Celebrate: our own chime + haptic, and mute the crosshair's automatic "back" on the way to Enable.
            CrosshairFeedback.shared.suppress(.back,for:0.6)
            CrosshairFeedback.shared.play(CrosshairSound.collect)
            CrosshairFeedback.shared.play(CrosshairHaptic.collect)
            verification = .idle
            if let onCollect {
                // Reduce Motion: a plain fade into the garden, then the card (Album from the card).
                onCollect(.fade(itemID:target.star.id))
                return
            }
            if let record = model.collected[target.id] {
                capturedItem = GardenCollectionItem(star:target.star,record:record)
                service.stop()
            }
        } catch {
            verification = .idle
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Wormhole handover

    /// Capture cue ("cekrek"), shared by the real flow and the demo: the frame freezes at the click and
    /// over-exposes (+1.5 stops, bloom, vignette pulse, chromatic edges), a white flash (.65, held 60 ms),
    /// a 1 → 0.98 → 1 shutter squeeze, rigid haptic + mechanical shutter click; the wormhole opens 350 ms later.
    private func captureThenHandover(itemID: Int?,point: CGPoint,demoStar: CatalogStar? = nil,freeze: WormholeFreeze,
                                     then finish: @escaping () -> Void = {}) {
        WormholeFeedback.shared.playShutter()
        captureImage = freeze.image
        captureStart = CACurrentMediaTime()
        Task { @MainActor in
            try? await Task.sleep(for:.milliseconds(Int(CaptureFlash.handoverDelay)))
            beginHandover(itemID:itemID,point:point,demoStar:demoStar,freeze:freeze)
            verification = .idle
            finish()
            try? await Task.sleep(for:.milliseconds(Int(CaptureFlash.duration-CaptureFlash.handoverDelay)+20))
            captureStart = nil; captureImage = nil
        }
    }

    /// Freezes the camera frame and opens the wormhole at the collected star's screen point.
    private func beginHandover(itemID: Int?,point: CGPoint,demoStar: CatalogStar? = nil,freeze frozen: WormholeFreeze? = nil) {
        guard handover == nil, let onCollect, viewSize != .zero else { return }
        let freeze = frozen ?? service.wormholeFreeze() ?? .placeholder(size:viewSize)
        let demo = demoStar.map { WormholeDemo.make(star:$0,freeze:freeze,location:model.location) }
        let id = demo?.item.id ?? itemID
        let handover = WormholeHandover(freeze:freeze,star:point,itemID:id,
                                        scene:GardenSkyView.wormholeScene(model:model,newID:id,demo:demo),demo:demo)
        // The wormhole owns the audio from success onward: silence every crosshair cue already scheduled.
        for sound in CrosshairSound.allCases { CrosshairFeedback.shared.suppress(sound,for:4) }
        WormholeFeedback.shared.play(landing:handover.landing)
        onCollect(.wormhole(handover))
    }

    #if DEBUG
    // MARK: Demo sky

    private func toggleDemoSky() {
        guard handover == nil, !isChecking else { return }
        if demoOn {
            demoDirection = nil; demoPoint = nil; demoArrow = nil; demoChecking = false
        } else if demoStar != nil {
            // ~22° to the side of where the phone points now, fixed in the AR world.
            demoDirection = DemoSky.direction(from:service.demoForwardWorld() ?? SIMD3(0,0,-1))
            if service.demoForwardWorld() == nil { demoPoint = CGPoint(x:center.x+90,y:center.y-140) }   // Simulator
        }
        CrosshairFeedback.shared.play(CrosshairHaptic.acquire)
    }

    /// Demo success: the capture cue ("cekrek"), then the wormhole 250 ms later from the frozen frame.
    private func captureDemo(_ target: CenterTarget) {
        guard onCollect != nil, !reduceMotion else {
            CrosshairFeedback.shared.play(CrosshairSound.collect)
            onCollect?(.fade(itemID:nil)); verification = .idle; return
        }
        let star = target.star
        let point = target.detection?.point ?? center
        var freeze = service.wormholeFreeze() ?? .placeholder(size:viewSize)
        freeze.image = DemoSky.composite(freeze.image,star:point,viewSize:viewSize,color:star.rgb)
        captureThenHandover(itemID:star.id,point:point,demoStar:star,freeze:freeze) {
            demoDirection = nil; demoPoint = nil; demoArrow = nil
        }
    }
    #endif

    /// Reads the live camera frame: is there really a light inside the circle?
    private func lightIsInCircle(for star: CatalogStar) -> Bool {
        guard let buffer = service.session.currentFrame?.capturedImage, viewSize != .zero,
              CameraSkyContext.permits(CGPoint(x:0.5,y:0.5),in:buffer,isDisc:star.isSolarDisc),
              let sample = CenterLightProbe.measure(buffer,viewSize:viewSize,radius:captureRadius) else { return false }
        if star.isSun {
            // A saturated disc filling a good part of the circle.
            return sample.peak >= 245 && sample.saturatedFraction >= 0.10
        }
        // A point or disc clearly brighter than the sky right around it.
        return sample.peak >= 60 && sample.peak-sample.surroundingMedian >= 35
    }
}

/// Measures brightness in the centre of a camera frame (luma plane), mapped from the on-screen circle.
nonisolated enum CenterLightProbe {
    struct Sample { let peak: Double; let saturatedFraction: Double; let surroundingMedian: Double }

    static func measure(_ buffer: CVPixelBuffer,viewSize: CGSize,radius: CGFloat) -> Sample? {
        guard CVPixelBufferGetPlaneCount(buffer) >= 1 else { return nil }
        CVPixelBufferLockBaseAddress(buffer,.readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer,.readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer,0) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(buffer,0), height = CVPixelBufferGetHeightOfPlane(buffer,0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer,0)
        let pixels = base.assumingMemoryBound(to:UInt8.self)
        // The preview is aspect-filled and rotated; the frame centre is the screen centre.
        let long = Double(max(width,height)), short = Double(min(width,height))
        let scale = max(long/Double(max(viewSize.height,viewSize.width)),short/Double(min(viewSize.width,viewSize.height)))
        let r = max(4,Double(radius)*scale)
        let cx = width/2, cy = height/2
        let outer = Int(r*3)
        var peak = 0.0, core = 0, saturated = 0
        var ring: [UInt8] = []
        ring.reserveCapacity(4096)
        let step = max(1,Int(r/20))
        for dy in stride(from:-outer,through:outer,by:step) {
            let y = cy+dy
            guard y >= 0, y < height else { continue }
            let row = pixels+y*rowBytes
            for dx in stride(from:-outer,through:outer,by:step) {
                let x = cx+dx
                guard x >= 0, x < width else { continue }
                let distance = (Double(dx*dx+dy*dy)).squareRoot()
                let value = row[x]
                if distance <= r {
                    core += 1
                    peak = max(peak,Double(value))
                    if value >= 235 { saturated += 1 }
                } else if distance >= r*2 && distance <= r*3 {
                    ring.append(value)
                }
            }
        }
        guard core > 0, !ring.isEmpty else { return nil }
        ring.sort()
        return Sample(peak:peak,saturatedFraction:Double(saturated)/Double(core),surroundingMedian:Double(ring[ring.count/2]))
    }
}

/// Glass hint capsule used at the bottom of the camera screens.
struct CelyxHintPill: View {
    let text: String
    var isLoading = false
    var body: some View {
        HStack(spacing:12) {
            if isLoading { ProgressView().tint(CelyxColor.primaryLabel) }
            else { Image(systemName:"scope") }
            Text(text).lineLimit(2).multilineTextAlignment(.leading)
        }
        .font(.system(size:15,weight:.semibold)).tracking(-0.23).foregroundStyle(.white)
        .padding(12)
        .background(Capsule().fill(.white.opacity(0.2)))
        .glassEffect(.regular,in:Capsule())
        .padding(.horizontal,24)
    }
}

/// Latin constellation names from the bundled Stellarium metadata (e.g. "Ori" → "Orion").
enum ConstellationNames {
    private static let names: [String:String] = {
        guard let url = try? SkyAssets.url("constellations",extension:"json"),
              let data = try? Data(contentsOf:url),
              let entries = try? JSONDecoder().decode([String:Constellation].self,from:data) else { return [:] }
        return entries.compactMapValues { $0.name ?? $0.english }
    }()
    static func name(for code: String) -> String? { names[code] }
}

#Preview("Collect stars") {
    StarCollectCameraView(model:AppPreviewData.model,onClose:{})
        .preferredColorScheme(.dark)
}

#Preview("Camera hint") {
    CelyxHintPill(text:"Hold steady while we compare the stars").padding().background(.black)
        .preferredColorScheme(.dark)
}

#Preview("Camera hint · scanning faint light") {
    CelyxHintPill(text:"Scanning faint starlight… Hold steady for a moment",isLoading:true)
        .padding().background(CelyxColor.night).preferredColorScheme(.dark)
}
