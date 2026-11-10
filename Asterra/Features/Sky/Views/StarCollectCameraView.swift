import ARKit
import SwiftUI
import simd

/// Real star collecting, styled like Figma "Camera Stand by" / "Camera Scanned" / "Camera Captured".
///
/// `SkyFinderService` does the work: GPS + true-north camera orientation (ARKit) project the HYG catalogue
/// onto the live camera image, and `CameraStarDetector` looks for an actual point of light at that spot.
/// The crosshair never moves: only what sits inside the centre circle is scanned. Star collection needs
/// fresh optical evidence. Tapping the camera captures the current frame immediately
/// and opens its album; verification happens during live scanning, before the tap.
struct StarCollectCameraView: View {
    typealias CenterTarget = StarCollectViewModel.CenterTarget

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
    @State private var zoomStart: Double?
    /// Crosshair interaction: a target shows as collectible (Enable) after a short lock (Locking).
    @State private var settledID: Int?
    @State private var isLocking = false
    /// Capture cue ("cekrek"): when the shutter fired, and the frame frozen at that instant.
    @State private var captureStart: CFTimeInterval?
    @State private var captureImage: CGImage?
    /// The camera feed shows only once ARKit delivers real frames (no skewed first frames).
    @State private var feedReady = false
    #if DEBUG
    /// Catalog stars at their real current horizon positions; demo bypasses optical detection.
    @State private var didPrepareCapricornus = false
    @State private var demoStars: [DemoSky.Entry] = []
    @State private var demoProjections: [DemoSky.Projection] = []
    @State private var demoOn = false
    @State private var demoDate: Date?
    @State private var demoLocation: ObserverLocation?
    private var demoGuide: DemoSky.Projection? {
        demoProjections.filter { model.collected[$0.id] == nil && $0.id != viewModel.excludedID }
            .min { ($0.point.map(distance) ?? .infinity) < ($1.point.map(distance) ?? .infinity) }
    }
    #else
    private var demoOn: Bool { false }
    #endif
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var viewModel: StarCollectViewModel
    private var service: SkyFinderService { viewModel.service }
    private var captureRadius: CGFloat { viewModel.captureRadius }
    private var isChecking: Bool { viewModel.isChecking }

    init(
        model: HomeViewModel, handover: WormholeHandover? = nil, onCollect: ((CollectResult) -> Void)? = nil,
        onClose: @escaping () -> Void
    ) {
        self.model = model
        self.handover = handover
        self.onCollect = onCollect
        self.onClose = onClose
        _viewModel = State(initialValue: StarCollectViewModel(model: model))
    }

    private var viewSize: CGSize { viewModel.viewSize }
    private var center: CGPoint { CGPoint(x: viewSize.width / 2, y: viewSize.height / 2) }
    private var centerTarget: CenterTarget? {
        #if DEBUG
        if demoOn {
            guard let target = DemoSky.target(in: demoProjections,
                collected: Set(model.collected.keys), excludedID: viewModel.excludedID,
                lockedID: viewModel.lockedID, center: center, radius: captureRadius,
                lockRadius: viewModel.lockRadius), let point = target.point, viewSize != .zero
            else { return nil }
            return CenterTarget(star: target.star,
                detection: CameraStarAnnotation(star: target.star, point: point, size: CGSize(width: 28, height: 28)))
        }
        #endif
        return viewModel.centerTarget
    }
    /// The target shows as collectible (Enable) once it has held for the short lock.
    private var shownTarget: CenterTarget? {
        guard let target = centerTarget, target.id == settledID else { return nil }
        return target
    }
    private func distance(_ point: CGPoint) -> CGFloat { viewModel.distance(point) }

    /// How far the locked star sits from the screen centre (zero when nothing is locked, or for a body
    /// matched by angle with no light on screen).
    private var lockOffset: CGSize {
        guard let point = shownTarget?.detection?.point, viewSize != .zero else { return .zero }
        return CGSize(width: point.x - center.x, height: point.y - center.y)
    }

    var body: some View {
        NavigationStack {
            TimelineView(.animation(paused: handover == nil && captureStart == nil)) { _ in
                let frame = handover.map { $0.frame($0.tt()) }
                let shutter = captureStart.map { (CACurrentMediaTime() - $0) * 1000 }
                cameraContent(cameraUI: frame?.cameraUI ?? 1, crosshair: frame?.crossAlpha ?? 1, shutter: shutter)
            }
        }
    }

    private func cameraContent(cameraUI: Double, crosshair: Double, shutter: Double?) -> some View {
        ZStack(alignment: .bottom) {
            GeometryReader { geometry in
                ZStack {
                    if service.isCameraRunning {
                        SkyCameraPreview(
                            session: service.session, onViewport: service.updateViewport,
                            onTap: { point in
                                if let target = shownTarget {
                                    collect(target)
                                } else {
                                    _ = service.focus(at: point)
                                }
                            },
                            onExposureDrag: { translation, _, ended in
                                service.dragExposure(translation: translation, ended: ended)
                            },
                            zoom: service.cameraZoom, showsTrackingCoach: true,
                            onTrackingReset: service.resetTrackingForCalibration
                        )
                        // Hidden behind the night colour until ARKit delivers real frames, then a quick fade.
                        .opacity(feedReady ? 1 : 0)
                        .animation(.easeOut(duration: 0.2), value: feedReady)
                        #if DEBUG
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in toggleDemoSky() })
                        #endif
                        .simultaneousGesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    if zoomStart == nil { zoomStart = service.cameraZoom }
                                    service.setZoom((zoomStart ?? 1) * value.magnification)
                                }
                                .onEnded { _ in zoomStart = nil })
                    } else {
                        CelyxColor.night
                    }
                    #if DEBUG
                    if demoOn, handover == nil {
                        ForEach(demoProjections) { entry in
                            if let point = entry.point {
                                DemoStarView(color: entry.star.rgb)
                                    .opacity(model.collected[entry.id] == nil ? 1 : 0.25)
                                    .position(point)
                            }
                        }
                    }
                    #endif
                    // Cekrek: the frame freezes at the click and over-exposes until the wormhole takes it.
                    if let shutter, shutter < CaptureFlash.duration { CaptureFlashView(image: captureImage, t: shutter) }
                    if let handover { WormholeHandoverView(handover: handover) }
                    // CrosshairView's reticle sits 10pt above its own centre (see crosshair README).
                    // Gimbal lock: once a star is collectible the crosshair, its label and the pill ride on the
                    // star itself; they glide over on a spring when it locks and glide home when it lets go.
                    let lock = lockOffset
                    reticle.position(x: geometry.size.width / 2 + lock.width, y: geometry.size.height / 2 + 10 + lock.height)
                        .allowsHitTesting(false)
                        .opacity(crosshair)
                        .animation(.spring(duration: 0.45, bounce: 0.12), value: shownTarget?.id)
                    // The collect button hangs just under the crosshair's star label (reticle centre + 80pt).
                    if let target = shownTarget, !isChecking, handover == nil, captureStart == nil,
                        model.collected[target.star.id] == nil
                    {
                        CollectPill(title: "Collect \(target.star.title)") { collect(target) }
                            .id(target.star.id)
                            .position(x: geometry.size.width / 2 + lock.width, y: geometry.size.height / 2 + 80 + lock.height)
                            .animation(.spring(duration: 0.45, bounce: 0.12), value: shownTarget?.id)
                            .opacity(crosshair)
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
                    }
                    if !demoOn, service.pinnedLight != nil, let guide = service.pinnedLightGuide {
                        CameraPinnedLightOverlay(
                            guide: guide, title: pinnedLightTitle, isRecognizing: isAnalyzingLight,
                            subtitle: service.retainedCaptureAnnotation != nil ? "Ready to collect" : nil)

                    }
                }
                .scaleEffect(shutter.map(CaptureFlash.squeeze) ?? 1)
                .overlay { Color.white.opacity(shutter.map(CaptureFlash.white) ?? 0).allowsHitTesting(false) }
                .onAppear { viewModel.viewSize = geometry.size }
                .onChange(of: geometry.size) { _, size in viewModel.viewSize = size }
            }
            .ignoresSafeArea()

            Group {
            if service.alignment.requiresCalibration, service.status == .tracking, shownTarget == nil, !demoOn {
                VStack(spacing: 12) {
                    CelyxHintPill(
                        text: service.automaticMappingMessage,
                        isLoading: service.isMappingSky || service.isDetectingOnDemand)
                    if service.canRequestDetection { detectStarButton }
                }.padding(.horizontal, 20).padding(.bottom, 45)
            } else if let target = shownTarget, centerTarget?.id == target.id {
                sheet(for: target)
                    .padding(.horizontal, 6).padding(.bottom, 6)
                    .ignoresSafeArea(edges: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if !demoOn, service.pinnedLight != nil {
                pinnedLightPanel.padding(.horizontal, 6).padding(.bottom, 6)
            } else {
                CelyxHintPill(text: hintText, isLoading: isAnalyzingLight).padding(.bottom, 59).transition(
                    .opacity)
            }
            }
            .opacity(cameraUI)
            #if DEBUG
            if demoOn { DemoSkyPill().frame(maxHeight: .infinity, alignment: .top).padding(.top, 8).opacity(cameraUI) }
            #endif
        }
        .allowsHitTesting(handover == nil && captureStart == nil)
        .overlay(alignment: .trailing) {
            if service.exposureControlVisible {
                CameraExposureControl(
                    minimum: service.minimumExposure, maximum: service.maximumExposure,
                    value: Binding(get: { service.exposureBias }, set: { service.setExposure($0) }),
                    message: service.cameraControlMessage, onReset: { service.setExposure(0) },
                    onEditingChanged: service.setExposureEditing
                )
                .padding(.trailing, 12).transition(.opacity)
            }
        }
        .background(CelyxColor.night)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(handover == nil && captureStart == nil ? .automatic : .hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.left") {
                    service.stop()
                    onClose()
                }.labelStyle(.iconOnly)
            }

        }
        .tint(.white)
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: shownTarget?.id)
        .task {
            service.updateVisibility(quality: model.quality, atmosphere: model.atmosphere)
            viewModel.onSaved = { target in handleSaved(target) }
            if onCollect != nil { WormholeFeedback.shared.prepare() }
            await service.start()
        }
        .task {
            // Wait for the first real AR frame, plus a couple more so the preview has its orientation.
            while !Task.isCancelled && service.session.currentFrame == nil { try? await Task.sleep(for: .milliseconds(40)) }
            try? await Task.sleep(for: .milliseconds(90))
            feedReady = true
        }
        .task(id: centerTarget?.id) {
            guard let target = centerTarget else {
                isLocking = false
                settledID = nil
                return
            }
            if settledID == target.id { return }
            settledID = nil
            isLocking = true
            try? await Task.sleep(for: .seconds(0.7))
            guard !Task.isCancelled else { return }
            isLocking = false
            settledID = target.id
        }
        // Lock the star the moment it becomes collectible; release it once it leaves the hold radius.
        .onChange(of: shownTarget?.id) { _, id in if let id { viewModel.lockedID = id } }
        .onChange(of: centerTarget?.id) { _, id in if id == nil || id != viewModel.lockedID { viewModel.lockedID = nil } }
        .onChange(of: excludedIsNear) { _, near in if !near { viewModel.excludedID = nil } }
        #if DEBUG
        .task(id: demoOn) {
            // Refresh real sky positions with time and GPS, then project through the live camera.
            while demoOn && !Task.isCancelled {
                updateDemoProjections()
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
        #endif
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)
        ) { _ in
            service.restartAfterScreenshot()
        }
        .onDisappear { service.stop() }
        .onChange(of: phase) { _, value in
            if value == .active, viewModel.capturedItem == nil {
                Task { await service.start() }
            } else if viewModel.capturedItem == nil {
                service.suspendForBackground()
            } else {
                service.stop()
            }
        }
        .sheet(item: $viewModel.capturedItem, onDismiss: { Task { await service.start() } }) {
            item in
            CollectedObjectSheet(item: item, direction: nil, collection: model, startsWithNoteEntry: true,
                onSaveNote: { model.updateObservationNote(id: item.id, note: $0) },
                onSavePlace: { model.updateObservationPlace(id: item.id, name: $0) },
                onDelete: { model.deleteCollected(id: item.id); viewModel.capturedItem = nil })
        }
        .alert(
            "Camera",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })
        ) {
            Button("Try Again", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: Crosshair (always fixed at the centre of the screen)

    /// Figma "Crosshair" component (node 922:1567) with its own motion, sound and haptics.
    private var reticle: some View {
        let star = shownTarget?.star
        let label = star?.id == service.pinnedLight?.match?.star.id ? "" : star?.title ?? ""
        // During the wormhole the handover owns the audio and haptics: the crosshair stays silent.
        return CrosshairView(
            state: crosshairState, label: label, soundEnabled: handover == nil, hapticsEnabled: handover == nil)
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
            guard service.observerLocation != nil else { return "Waiting for your location to map Libra, Aries and Capricornus" }
            if !demoStars.isEmpty, demoStars.allSatisfy({ model.collected[$0.id] != nil }) {
                return "All demo stars collected"
            }
            guard let guide = demoGuide else {
                return "Waiting for camera tracking to map Libra, Aries and Capricornus"
            }
            let name = guide.star.title
            guard let point = guide.point else {
                if let arrow = guide.arrow {
                    let way = abs(arrow.dx) > abs(arrow.dy) ? (arrow.dx > 0 ? "right" : "left") : (arrow.dy > 0 ? "down" : "up")
                    return "Turn \(way) to find \(name)"
                }
                return "Look around to find \(name)"
            }
            return distance(point) <= captureRadius ? "\(name) is in your circle. Tap to collect" : "\(name) is close. Put it in your circle"
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
            case .compass: return "Light found. Move slowly while compass direction recovers."
            case .noCandidate: return "Light found. Keep it in view while we check catalog candidates."
            case .ambiguous: return "Several stars fit this light. Hold steady while we check."
            case .alignment: return "Light found. Move slowly while tracking recovers."
            }
        }
        if isAnalyzingLight { return "Scanning faint starlight… Hold steady for a moment" }
        let sun = service.sunAltitude ?? -90
        if sun >= -0.833 { return "It’s daytime. Only the Sun can be collected now" }
        if sun >= -6 { return "The sky is still too bright for stars" }
        return service.pointScanProgress >= 1
            ? "No steady point yet. Adjust your aim, or tap the star to focus."
            : "Point your circle at a star"
    }

    private var centeredLightIssue: CameraIdentificationIssue? {
        service.unidentifiedLights.filter { distance($0.point) <= captureRadius }
            .min { distance($0.point) < distance($1.point) }?.issue
    }
    private var isAnalyzingLight: Bool {
        guard service.status == .tracking else { return false }
        if service.pinnedLight?.isIdentified == true { return false }
        if service.alignment.requiresCalibration { return service.isMappingSky }
        if service.isScanningNewLight { return true }
        if service.isAdjustingCamera { return true }
        if service.pinnedLight != nil {
            if service.reacquiredPinnedAnnotation != nil { return false }
            return service.isRecognizingPinnedLight
        }
        if let issue = centeredLightIssue { return issue == .stabilizing }
        return service.isGatheringInitialLight && service.pointScanProgress > 0
            && service.pointScanProgress < 1
    }

    // MARK: Sheet

    private var pinIsInReticle: Bool {
        service.pinnedLightGuide?.point.map { distance($0) <= captureRadius } ?? false
    }
    private var pinnedLightTitle: String {
        if let ready = service.retainedCaptureAnnotation, ready.id == service.pinnedLight?.match?.star.id {
            return ready.star.title
        }
        return "Detected light"
    }

    private var detectStarButton: some View {
        CelyxPillButton(
            title: service.isDetectingOnDemand ? "Detecting…" : "Detect star",
            systemImage: "sparkle.magnifyingglass", style: service.isDetectingOnDemand ? .disabled : .primary
        ) {
            viewModel.detectStar()
        }
        .frame(maxWidth: 260)
        .accessibilityIdentifier("detect-star")
    }

    private var pinnedLightPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let issue = service.newLightIssue {
                HStack(spacing: 8) {
                    if service.isScanningNewLight {
                        ProgressView().tint(CelyxColor.primaryLabel)
                    } else {
                        Image(systemName: "sparkle.magnifyingglass")
                    }
                    Text(
                        issue == .stabilizing
                            ? "New light · matching its direction…" : "New light · \(issue.title)"
                    )
                    .font(.system(size: 13))
                }
            }
            HStack(spacing: 10) {
                if isAnalyzingLight { ProgressView().tint(CelyxColor.primaryLabel) }
                Text(pinnedLightTitle)
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("Clear pin") { service.clearPinnedLight() }
                    .font(.system(size: 13, weight: .semibold))
            }
            Text(pinnedLightInstruction)
                .font(.system(size: 13)).foregroundStyle(CelyxColor.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
            if service.canRequestDetection { detectStarButton }

        }.padding(20).foregroundStyle(CelyxColor.primaryLabel).background(
            CelyxBluePanel(cornerRadius: 28))
    }

    private var pinnedLightInstruction: String {
        if !service.hasReferenceAlignment {
            if let issue = service.pinnedLight?.issue, service.pinnedLight?.match == nil {
                return issue == .stabilizing
                    ? "Light detected. Checking nearby catalog candidates…" : issue.message
            }
            return
                "Its name is estimated from direction, time and location. You can aim at another light to scan it."
        }
        guard service.status == .tracking else {
            return "Tracking is adjusting. Your last light is saved; move slowly to steady the guide."
        }
        if service.isAdjustingCamera {
            return "Applying camera settings. Your last light stays pinned."
        }
        if service.pinnedLight?.isIdentified == true {
            return pinIsInReticle
                ? "Identification saved. Waiting for fresh light in the circle before collecting."
                : "Identification saved. Follow the arrow back to the last detected light."
        }
        if pinIsInReticle {
            if service.reacquiredPinnedAnnotation != nil {
                return "Light detected again. Getting your collection ready."
            }
            if service.pinnedLight?.issue == .ambiguous {
                return "Light found, but several names fit. Check direction calibration to identify it."
            }
            return "Back at the saved position. Checking fresh camera frames for this light…"
        }
        if service.isRecognizingPinnedLight {
            return "Checking the saved direction. You can move; the last light stays pinned."
        }
        if service.pinnedLight?.match != nil {
            return
                "Follow the arrow back to this light. Collecting needs a fresh sighting inside the circle."
        }
        return
            "No clear identity yet. Return to the pin or aim at another light. Check calibration if needed."
    }

    private func sheet(for target: CenterTarget) -> some View {
        let star = target.star
        let isCollected = model.collected[star.id] != nil
        let checking = viewModel.verification == .checking(star.id)
        let failed = viewModel.verification == .failed(star.id)
        return ZStack(alignment: .top) {
            CelyxBluePanel(cornerRadius: 34)
            CelyxGrabber()
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    StarPortraitView(star: star)
                        .frame(width: 64, height: 64)
                        .shadow(
                            color: Color(red: star.rgb.x, green: star.rgb.y, blue: star.rgb.z).opacity(0.8),
                            radius: 10
                        )
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(star.title).font(.system(size: 28, weight: .bold)).tracking(0.38)
                            .foregroundStyle(
                                CelyxColor.primaryLabel
                            )
                            .lineLimit(1).minimumScaleFactor(0.6).frame(height: 34)
                        Text(subtitle(for: star)).font(.system(size: 15, weight: .medium)).tracking(-0.23)
                            .foregroundStyle(CelyxColor.subtitle).frame(height: 20)
                    }
                    .padding(.horizontal, 16)
                    Spacer(minLength: 0)
                    // Several stars close together: X lets go of this one so the next can lock.
                    CelyxCloseButton {
                        withAnimation(.smooth(duration: 0.3)) {
                            viewModel.verification = .idle
                            viewModel.excludedID = star.id
                            viewModel.lockedID = nil
                            settledID = nil
                            service.clearPinnedLight()
                        }
                    }
                    .accessibilityLabel("Not this star")
                }
                .padding(.horizontal, 16).frame(height: 64).padding(.top, 24).padding(.bottom, 8)
                HStack(spacing: 6) {
                    let color = failed ? Color.orange : CelyxColor.ready
                    Circle().fill(color).frame(width: 6, height: 6).shadow(color: color, radius: 3)
                    Text(
                        "\(Text(statusText(for:star,checking:checking,failed:failed,collected:isCollected,fresh:target.detection != nil)).foregroundStyle(CelyxColor.primaryLabel))\(Text(directionText(for:star)).foregroundStyle(CelyxColor.secondaryLabel))"
                    )
                    .font(.system(size: 12)).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                .frame(height: 16).padding(16)
                // The capture action lives on the crosshair; the sheet only says what it is.
                if isCollected {
                    CelyxPillButton(title: "Collected", systemImage: "checkmark", style: .collected) {}
                        .allowsHitTesting(false)
                        .padding(.horizontal, 16)
                }
            }
        }
        .frame(height: (star.isSolarDisc ? 228 : 248) - (isCollected ? 0 : 56))
        .contentShape(Rectangle())
        .onTapGesture { collect(target) }
    }

    private func statusText(
        for star: CatalogStar, checking: Bool, failed: Bool, collected: Bool, fresh: Bool
    ) -> String {
        if collected { return "In your garden · " }
        if checking { return "Hold steady, checking its light · " }
        if failed { return "Couldn’t see it in the circle. Try again · " }
        if service.retainedCaptureAnnotation?.id == star.id { return "Ready to collect · " }
        if star.isSun { return "Visible now · Never look straight at it · " }
        if !fresh { return "Rechecking light · " }
        return "Visible now · "
    }
    private func subtitle(for star: CatalogStar) -> String {
        if star.isSolarSystemBody { return star.kind }
        if let code = star.con, let name = ConstellationNames.name(for: code) {
            return "Star in \(name)"
        }
        return "Star"
    }
    /// e.g. "High in the west", from the object's real altitude/azimuth at this place and time.
    private func directionText(for star: CatalogStar) -> String {
        guard let observation = service.viewableObjects.first(where: { $0.id == star.id }) else {
            return "In your view"
        }
        let points = [
            "north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest",
        ]
        let bearing = points[Int((observation.azimuth + 22.5) / 45) % 8]
        let height = observation.altitude >= 50 ? "High" : observation.altitude >= 20 ? "Up" : "Low"
        return "\(height) in the \(bearing)"
    }


    private var excludedIsNear: Bool {
        #if DEBUG
        if demoOn {
            return demoProjections.contains { $0.id == viewModel.excludedID && $0.point.map { distance($0) <= viewModel.lockRadius } == true }
        }
        #endif
        return viewModel.excludedIsNear
    }

    // MARK: Actions

    private func collect(_ target: CenterTarget) {
        #if DEBUG
        if demoOn {
            // Simulated stars use the capture animation and persist in the real collection.
            guard !isChecking, captureStart == nil, handover == nil, model.collected[target.id] == nil else { return }
            viewModel.verification = .checking(target.id)
            captureDemo(target)
            return
        }
        #endif
        guard captureStart == nil, handover == nil else { return }
        viewModel.collect(target)
    }

    /// After Ferdi's save succeeds: from Home, cekrek -> wormhole -> land on the star -> its card.
    /// Returns false to let the view model celebrate and open the album here (camera opened elsewhere).
    private func handleSaved(_ target: CenterTarget) -> Bool {
        guard let onCollect else { return false }
        if reduceMotion {
            // Reduce Motion: a plain fade into the garden, then the card.
            CrosshairFeedback.shared.suppress(.back, for: 0.6)
            CrosshairFeedback.shared.play(CrosshairSound.collect)
            CrosshairFeedback.shared.play(CrosshairHaptic.collect)
            viewModel.verification = .idle
            onCollect(.fade(itemID: target.star.id))
            return true
        }
        captureThenHandover(
            itemID: target.star.id, point: target.detection?.point ?? center,
            freeze: service.wormholeFreeze() ?? .placeholder(size: viewSize))
        return true
    }

    // MARK: Wormhole handover

    /// Capture cue ("cekrek"), shared by the real flow and the demo: the frame freezes at the click and
    /// over-exposes (+1.5 stops, bloom, vignette pulse, chromatic edges), a white flash (.65, held 60 ms),
    /// a 1 → 0.98 → 1 shutter squeeze, rigid haptic + mechanical shutter click; the wormhole opens 350 ms later.
    private func captureThenHandover(itemID: Int?,point: CGPoint,freeze: WormholeFreeze,
                                     then finish: @escaping () -> Void = {}) {
        WormholeFeedback.shared.playShutter()
        captureImage = freeze.image
        captureStart = CACurrentMediaTime()
        Task { @MainActor in
            try? await Task.sleep(for:.milliseconds(Int(CaptureFlash.handoverDelay)))
            beginHandover(itemID:itemID,point:point,freeze:freeze)
            viewModel.verification = .idle
            finish()
            try? await Task.sleep(for:.milliseconds(Int(CaptureFlash.duration-CaptureFlash.handoverDelay)+20))
            captureStart = nil; captureImage = nil
        }
    }

    /// Freezes the camera frame and opens the wormhole at the collected star's screen point.
    private func beginHandover(itemID: Int?,point: CGPoint,freeze frozen: WormholeFreeze? = nil) {
        guard handover == nil, let onCollect, viewSize != .zero else { return }
        let freeze = frozen ?? service.wormholeFreeze() ?? .placeholder(size:viewSize)
        let handover = WormholeHandover(freeze:freeze,star:point,itemID:itemID,
                                        scene:GardenSkyView.wormholeScene(model:model,newID:itemID,location:service.observerLocation))
        // The wormhole owns the audio from success onward: silence every crosshair cue already scheduled.
        for sound in CrosshairSound.allCases { CrosshairFeedback.shared.suppress(sound,for:4) }
        WormholeFeedback.shared.play(landing:handover.landing)
        onCollect(.wormhole(handover))
    }

    #if DEBUG
    // MARK: Demo sky

    private func toggleDemoSky() {
        guard handover == nil, !isChecking else { return }
        viewModel.lockedID = nil
        viewModel.excludedID = nil
        settledID = nil
        demoOn.toggle()
        didPrepareCapricornus = false
        demoDate = nil
        demoLocation = nil
        demoStars = []; demoProjections = []
        if demoOn { updateDemoProjections() }
        CrosshairFeedback.shared.play(CrosshairHaptic.acquire)
    }

    private func updateDemoProjections() {
        guard let location = service.observerLocation else {
            demoStars = []; demoProjections = []; demoDate = nil; demoLocation = nil
            return
        }
        let now = Date()
        if !didPrepareCapricornus {
            do {
                try DemoSky.prepareCollection(model: model, date: now, location: location)
                didPrepareCapricornus = true
            } catch {
                viewModel.errorMessage = error.localizedDescription
                return
            }
        }
        if demoDate == nil || now.timeIntervalSince(demoDate ?? now) >= 1 || demoLocation != location {
            demoStars = DemoSky.entries(in: model.stars, date: now, location: location)
            demoDate = now
            demoLocation = location
        }
        demoProjections = demoStars.compactMap { entry in
            guard let guide = service.demoProjection(horizon: entry.direction) else { return nil }
            return DemoSky.Projection(star: entry.star, point: guide.point, arrow: guide.arrow)
        }
    }

    private func captureDemo(_ target: CenterTarget) {
        // Revalidate after the lock delay; never capture against a stale fix or a placeholder camera.
        updateDemoProjections()
        guard let location = service.observerLocation,
            let current = centerTarget, current.id == target.id,
            let point = current.detection?.point, var freeze = service.wormholeFreeze()
        else {
            viewModel.verification = .idle
            viewModel.errorMessage = "Wait for location and camera tracking, then aim at the star again."
            return
        }
        let date = Date()
        freeze.image = DemoSky.composite(freeze.image, stars: demoProjections.compactMap { entry in
            entry.point.map { (point: $0, color: entry.star.rgb) }
        }, viewSize: viewSize)
        do {
            guard let image = freeze.image else { throw CocoaError(.fileWriteUnknown) }
            try DemoSky.save(star: target.star, image: image, date: date, location: location, model: model)
            if reduceMotion {
                if !handleSaved(target) { showDemoAlbum(target) }
            } else if onCollect != nil {
                captureThenHandover(itemID: target.id, point: point, freeze: freeze) {
                    demoOn = false; demoStars = []; demoProjections = []
                }
            } else {
                showDemoAlbum(target)
            }
        } catch {
            viewModel.verification = .idle
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func showDemoAlbum(_ target: CenterTarget) {
        viewModel.verification = .idle
        viewModel.capturedItem = model.collectionItems.first { $0.id == target.id }
        service.stop()
    }
    #endif


}

#Preview("Collect stars") {
    StarCollectCameraView(model: AppPreviewData.model, onClose: {})
        .preferredColorScheme(.dark)
}
