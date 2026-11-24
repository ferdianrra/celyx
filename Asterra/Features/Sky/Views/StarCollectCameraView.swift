import AVFoundation
import SwiftUI
import simd

/// Real star collecting, styled like Figma "Camera Stand by" / "Camera Scanned" / "Camera Captured".
///
/// `SkyFinderService` does the work: GPS + true-north camera orientation (Core Motion) project the HYG catalogue
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
        case fade(itemID: Int?, captureID: UUID?)
    }

    let model: HomeViewModel
    let onClose: () -> Void
    let onboardingGuide: OnboardingCameraGuide?
    let guideTarget: CatalogStar?
    /// The running handover, if any (fades this screen's UI on its clock).
    var handover: WormholeHandover? = nil
    /// When set, a successful collect hands over to the garden (wormhole) instead of opening the album here.
    var onCollect: ((CollectResult) -> Void)? = nil
    /// Event mode ("Collect this event"): guide the camera to the event and collect it during its window.
    var event: SkyEvent? = nil
    var eventStore: SkyEventStore? = nil
    var onEventCollected: (() -> Void)? = nil
    @State private var eventGuide: EventCameraGuide?
    @State private var eventNow = Date()
    @State private var isCollectingEvent = false
    @State private var zoomStart: Double?
    @State private var targetCrosshairState: CrosshairState = .default
    private struct TargetAnimationKey: Equatable {
        let targetID: Int?
        let reduceMotion: Bool
    }
    /// Capture cue ("cekrek"): when the shutter fired, and the frame frozen at that instant.
    @State private var captureStart: CFTimeInterval?
    @State private var captureImage: CGImage?
    /// The camera feed shows only once the camera delivers real frames (no skewed first frames).
    @State private var feedReady = false
    @State private var isClosing = false
    #if DEBUG
    @State private var demoCaptureTask: Task<Void, Never>?
    /// Catalog stars at their real current horizon positions.
    @State private var demoStars: [DemoSky.Entry] = []
    @State private var demoProjections: [DemoSky.Projection] = []
    private var demoOn: Bool { event == nil && onboardingGuide == nil && guideTarget == nil }
    @State private var demoDate: Date?
    @State private var demoLocation: ObserverLocation?
    private var demoGuide: DemoSky.Projection? {
        demoProjections.filter { $0.id != viewModel.excludedID }
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
        event: SkyEvent? = nil, eventStore: SkyEventStore? = nil, onEventCollected: (() -> Void)? = nil,
        onboardingGuide: OnboardingCameraGuide? = nil, guideTarget: CatalogStar? = nil,
        onClose: @escaping () -> Void
    ) {
        self.model = model
        self.handover = handover
        self.onCollect = onCollect
        self.event = event
        self.eventStore = eventStore
        self.onEventCollected = onEventCollected
        self.onClose = onClose
        self.onboardingGuide = onboardingGuide
        self.guideTarget = guideTarget
        _viewModel = State(initialValue: StarCollectViewModel(model: model))
    }

    private var viewSize: CGSize { viewModel.viewSize }
    private var center: CGPoint { CGPoint(x: viewSize.width / 2, y: viewSize.height / 2) }
    private var centerTarget: CenterTarget? {
        #if DEBUG
        if demoOn {
            guard let target = DemoSky.target(in: demoProjections,
                collected: [], excludedID: viewModel.excludedID,
                lockedID: viewModel.lockedID, center: center, radius: captureRadius,
                lockRadius: viewModel.lockRadius), let point = target.point, viewSize != .zero
            else { return nil }
            return CenterTarget(star: target.star,
                detection: CameraStarAnnotation(star: target.star, point: point, size: CGSize(width: 28, height: 28)))
        }
        #endif
        guard let target = viewModel.centerTarget,
            guideTarget == nil || guideTarget?.id == target.id else { return nil }
        return target
    }
    /// Enter at the fixed center reticle. Once locked, use the existing exit/
    /// retained-photo rules rather than restarting on small hand movements.
    private var shownTarget: CenterTarget? {
        guard let target = centerTarget else { return nil }
        if viewModel.lockedID == target.id { return target }
        guard let point = target.detection?.point else { return target }
        return CameraTargetSelection.canAcquireInReticle(at: point, center: center) ? target : nil
    }
    private func distance(_ point: CGPoint) -> CGFloat { viewModel.distance(point) }

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
                            onPreviewingChanged: { previewing in
                                if previewing { feedReady = true }
                            },
                            onTap: handleCameraTap,
                            onExposureDrag: { translation, _, ended in
                                service.dragExposure(translation: translation, ended: ended)
                            },
                            zoom: service.cameraZoom
                        )
                        // Hidden behind the night colour until the camera delivers real frames, then a quick fade.
                        .opacity(feedReady ? 1 : 0)
                        .animation(.easeOut(duration: 0.2), value: feedReady)
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
                                DemoStarView(color: entry.star.rgb).position(point)
                            }
                        }
                    }
                    #endif
                    // Cekrek: the frame freezes at the click and over-exposes until the wormhole takes it.
                    if let shutter, shutter < CaptureFlash.duration { CaptureFlashView(image: captureImage, t: shutter) }
                    if let handover { WormholeHandoverView(handover: handover) }
                    // The reticle stays at screen center; only its visual state animates.
                    // CrosshairView's own canvas places the reticle 10pt above its center.
                    reticle
                        .shadow(color: .black.opacity(0.35), radius: 1.5, x: 0, y: 0.5)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2 + 10)
                        .allowsHitTesting(false)
                        .opacity(crosshair)
                    if !demoOn, let title = event?.title ?? guideTarget?.title,
                        let guide = eventGuide, handover == nil, guide.altitude > 0
                    {
                        if let point = guide.point {
                            EventGuideMarker(title: title, isAimed: guide.isAimed).position(point)
                        }
                        // A big arrow around the circle always points the way until the event is in it.
                        if !guide.isAimed {
                            EventDirectionArrow(
                                arrow: guide.pointing(from: CGPoint(
                                    x: geometry.size.width / 2, y: geometry.size.height / 2 + 10)),
                                size: geometry.size)
                        }
                    }
                }
                .scaleEffect(shutter.map(CaptureFlash.squeeze) ?? 1)
                .overlay { Color.white.opacity(shutter.map(CaptureFlash.white) ?? 0).allowsHitTesting(false) }
                .onAppear { viewModel.viewSize = geometry.size }
                .onChange(of: geometry.size) { _, size in viewModel.viewSize = size }
            }
            .ignoresSafeArea()

            Group {
                if let target = shownTarget, centerTarget?.id == target.id {
                    VStack(spacing: 38) {
                        CameraCollectionPrompt(text: isChecking ? "Collecting…"
                            : viewModel.verification == .failed(target.id) ? "Keep the light in view and try again"
                            : "Tap anywhere to collect", ready: true)
                        sheet(for: target)
                    }
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if !demoOn, let event {
                    EventCollectPanel(event: event, guide: service.status == .tracking ? eventGuide : nil,
                        now: eventNow, isCollected: eventStore?.collected.contains(event.id) == true,
                        onCollect: collectEvent)
                        .padding(.horizontal, 20).padding(.bottom, 40)
                        .transition(.opacity)
                } else if !demoOn, let onboardingGuide {
                    onboardingGuide
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    CameraCollectionPrompt(text: demoOn ? hintText : service.status == .tracking
                        ? (isAnalyzingLight ? service.automaticMappingMessage : "Find a star or planet in the sky")
                        : hintText)
                        .padding(.bottom, 70)
                        .transition(.opacity)
                }
            }
            .opacity(cameraUI)
        }
        .allowsHitTesting(!isClosing && handover == nil && captureStart == nil)
        .overlay(alignment: .top) {
            if !demoOn, let event, handover == nil {
                EventWindowBanner(event: event, now: eventNow)
                    .padding(.horizontal, 16).padding(.top, 8)
            }
        }
        .task(id: event?.id ?? guideTarget?.id.description) {
            // Event guide: the event's sky position (refreshed each second) projected through the live camera.
            guard event != nil || guideTarget != nil else { return }
            var direction: SIMD3<Double>?
            var position: (azimuth: Double, altitude: Double) = (0, -90)
            var computed = Date.distantPast
            while !Task.isCancelled {
                let now = Date()
                if now.timeIntervalSince(computed) >= 1,
                    let location = service.observerLocation ?? SkyEventCatalog.shared.location ?? model.location
                {
                    if let event {
                        let sky = SkyEventCatalog.horizon(of: event.target, at: now, location: location)
                        direction = sky.direction
                        position = (sky.azimuth, sky.altitude)
                    } else if let star = guideTarget {
                        let sky = AstronomyService.snapshot(date: now, location: location)
                        let geometric = star.isSun ? sky.sunDirection : star.isMoon ? sky.moonDirection
                            : star.isPlanet ? sky.planets.first { $0.star.id == star.id }?.direction
                            : sky.direction(ra: star.ra_deg, dec: star.dec_deg)
                        direction = geometric.map(Refraction.apparent)
                        if let direction {
                            position = (atan2(direction.x, direction.y) * 180 / .pi,
                                        asin(min(1, max(-1, direction.z))) * 180 / .pi)
                        }
                    }
                    computed = now
                    eventNow = now
                }
                if let direction, let projection = service.demoProjection(horizon: direction) {
                    let guide = EventCameraGuide(point: projection.point, arrow: projection.arrow,
                        separation: projection.separation, azimuth: position.azimuth, altitude: position.altitude)
                    if guide != eventGuide { eventGuide = guide }
                } else if eventGuide != nil {
                    eventGuide = nil
                }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
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
                    guard !isClosing else { return }
                    isClosing = true
                    #if DEBUG
                    demoCaptureTask?.cancel()
                    #endif
                    viewModel.onSaved = nil
                    onClose()
                }.labelStyle(.iconOnly)
                .disabled(isClosing)
            }

        }
        .tint(.white)
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: shownTarget?.id)
        .task {
            #if DEBUG
            service.setDemoSkyEnabled(demoOn)
            #endif
            service.updateVisibility(quality: model.quality, atmosphere: model.atmosphere)
            viewModel.onSaved = { target, record, freeze in
                handleSaved(target, captureID: record.captureID, freeze: freeze)
            }
            if onCollect != nil {
                WormholeFeedback.shared.prepare()
                if !reduceMotion { WormholeRenderer.prepare() }
            }
            await service.start()
        }
        .task {
            // Sensor delivery is a fallback; the native preview can appear before motion/GPS are ready.
            do {
                while service.session.currentFrame == nil {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(40))
                }
                try await Task.sleep(for: .milliseconds(90))
                feedReady = true
            } catch { return }
        }
        .task(id: phase == .active) {
            guard phase == .active else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard !Task.isCancelled, !isClosing, handover == nil, captureStart == nil else { return }
                service.session.recoverIfStalled()
            }
        }
        .task(id: TargetAnimationKey(targetID: shownTarget?.id, reduceMotion: reduceMotion)) {
            guard shownTarget != nil else { targetCrosshairState = .default; return }
            guard !reduceMotion else { targetCrosshairState = .enable; return }
            // Use all four Figma variants: acquire, green lock, then green loader.
            // Presentation only: optical verification and Collect stay independent.
            targetCrosshairState = .locking
            do {
                try await Task.sleep(for: .milliseconds(350))
                targetCrosshairState = .enable
                // Let the lock's label/focus animation finish before spinning.
                try await Task.sleep(for: .milliseconds(850))
                targetCrosshairState = .validating
            } catch { return } // A changed/lost target cancels the old sequence.
        }
        // Lock the star the moment it becomes collectible; release it once it leaves the hold radius.
        .onChange(of: shownTarget?.id) { _, id in viewModel.lockedID = id }
        .onChange(of: excludedIsNear) { _, near in if !near { viewModel.excludedID = nil } }
        #if DEBUG
        .task(id: demoOn) {
            // Refresh real sky positions with time and GPS, then project through the live camera.
            while demoOn && !Task.isCancelled {
                if !isChecking && handover == nil && captureStart == nil && viewModel.capturedItem == nil {
                    updateDemoProjections()
                }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
        #endif
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)
        ) { _ in
            service.restartAfterScreenshot()
        }
        .onDisappear {
            clearCaptureFlash()
            #if DEBUG
            demoCaptureTask?.cancel()
            #endif
            service.stop()
        }
        .onChange(of: phase) { _, value in
            guard !isClosing else { return }
            if value == .active, viewModel.capturedItem == nil, handover == nil {
                Task { await service.start() }
            } else if value == .background {
                clearCaptureFlash()
                #if DEBUG
                demoCaptureTask?.cancel()
                #endif
                if viewModel.capturedItem == nil { service.suspendForBackground() }
                else { service.stop() }
            }
            // Inactive includes screenshot editors and Control Center. Native capture
            // interruptions handle those; do not stop a live session for a brief overlay.
        }
        .sheet(item: $viewModel.capturedItem, onDismiss: { Task { await service.start() } }) {
            item in
            CaptureDetailView(item: item, model: model, startsWithNoteEntry: true) {
                viewModel.capturedItem = nil
            }
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
        let label = star?.title ?? ""
        // During the wormhole the handover owns the audio and haptics: the crosshair stays silent.
        return CrosshairView(
            state: crosshairState, label: label, soundEnabled: handover == nil, hapticsEnabled: handover == nil)
    }
    private var crosshairState: CrosshairState {
        if isChecking { return .validating }
        if shownTarget != nil { return targetCrosshairState == .default ? .locking : targetCrosshairState }
        if isAnalyzingLight { return .locking }
        return .default
    }

    private var hintText: String {
        #if DEBUG
        if demoOn {
            guard service.observerLocation != nil else { return "Waiting for your location to map the sky" }
            guard let guide = demoGuide else {
                return "Waiting for camera tracking"
            }
            let name = guide.star.title
            guard guide.point != nil else {
                if let arrow = guide.arrow {
                    let way = abs(arrow.dx) > abs(arrow.dy) ? (arrow.dx > 0 ? "right" : "left") : (arrow.dy > 0 ? "down" : "up")
                    return "Turn \(way) to find \(name)"
                }
                return "Look around to find \(name)"
            }
            return "Bring \(name) into your circle"
        }
        #endif
        switch service.status {
        case .tracking: break
        case .preparing: return "Finding your place under the sky…"
        case .requestingPermission: return "Allow camera and location to find stars"
        case .limited(let message), .unavailable(let message), .denied(let message): return message
        }
        if let guideTarget, let eventGuide, !eventGuide.isAimed {
            return eventGuide.altitude <= 0 ? "\(guideTarget.title) is below the horizon"
                : "Turn toward \(guideTarget.title)"
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
        guard !demoOn, service.status == .tracking else { return false }
        if service.pinnedLight?.isIdentified == true || service.automaticallyIdentifiedAnnotation != nil
            || service.retainedCaptureAnnotation != nil { return false }
        if service.alignment.requiresCalibration { return service.pinnedLight != nil || service.isMappingSky }
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

    private func sheet(for target: CenterTarget) -> some View {
        let star = target.star
        return CameraCollectionCard(star: star, onCollect: { collect(target) }, onDismiss: {
            guard !isChecking else { return }
            withAnimation(.smooth(duration: 0.3)) {
                viewModel.verification = .idle
                viewModel.excludedID = star.id
                viewModel.lockedID = nil
                service.clearPinnedLight()
            }
        })
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

    /// Collects the event: only inside its viewing window and while the camera faces it.
    private func collectEvent() {
        guard let event, let eventStore, !isCollectingEvent, event.isOpen(at: Date()),
            eventGuide?.isAimed == true
        else { return }
        isCollectingEvent = true
        CrosshairFeedback.shared.play(CrosshairSound.collect)
        CrosshairFeedback.shared.play(CrosshairHaptic.collect)
        withAnimation(.snappy) { eventStore.collect(event) }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            service.stop()
            if let onEventCollected { onEventCollected() } else { onClose() }
        }
    }

    private func handleCameraTap(_ point: CGPoint) {
        if let target = shownTarget { collect(target) }
        else { _ = service.focus(at: point) }
    }

    private func collect(_ target: CenterTarget) {
        guard !isClosing, !isChecking, viewModel.capturedItem == nil,
            captureStart == nil, handover == nil else { return }
        #if DEBUG
        if demoOn {
            captureDemo(target)
            return
        }
        #endif
        viewModel.collect(target)
    }

    /// After Ferdi's save succeeds: from Home, cekrek -> wormhole -> land on the star -> its card.
    /// Returns false to let the view model celebrate and open the album here (camera opened elsewhere).
    private func handleSaved(_ target: CenterTarget, captureID: UUID?, freeze: WormholeFreeze?) -> Bool {
        guard let onCollect else { return false }
        if reduceMotion {
            // Reduce Motion: a plain fade into the garden, then the card.
            CrosshairFeedback.shared.suppress(.back, for: 0.6)
            CrosshairFeedback.shared.play(CrosshairSound.collect)
            CrosshairFeedback.shared.play(CrosshairHaptic.collect)
            viewModel.verification = .idle
            onCollect(.fade(itemID: target.star.id, captureID: captureID))
            return true
        }
        captureThenHandover(
            itemID: target.star.id, captureID: captureID, point: target.detection?.point ?? center,
            freeze: freeze ?? service.wormholeFreeze() ?? .placeholder(size: viewSize))
        return true
    }

    // MARK: Wormhole handover

    /// Capture cue ("cekrek"), shared by the real flow and the demo: the frame freezes at the click and
    /// over-exposes (+1.5 stops, bloom, vignette pulse, chromatic edges), a white flash (.65, held 60 ms),
    /// a 1 → 0.98 → 1 shutter squeeze, rigid haptic + mechanical shutter click; the wormhole opens 350 ms later.
    private func captureThenHandover(itemID: Int?, captureID: UUID?, point: CGPoint, freeze: WormholeFreeze) {
        WormholeFeedback.shared.playShutter()
        let startedAt = CACurrentMediaTime()
        captureImage = freeze.image
        captureStart = startedAt
        // Keep the shutter delay on the main queue. The async closure here aborted
        // in Swift's task deallocator on iOS 27.2 when returning from the handover.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(CaptureFlash.handoverDelay))) {
            guard captureStart == startedAt, !isClosing, phase != .background else { return }
            beginHandover(itemID: itemID, captureID: captureID, point: point, freeze: freeze)
            viewModel.verification = .idle
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(CaptureFlash.duration) + 20)) {
            guard captureStart == startedAt else { return }
            clearCaptureFlash()
        }
    }

    private func clearCaptureFlash() {
        guard captureStart != nil else { return }
        captureStart = nil
        captureImage = nil
        viewModel.verification = .idle
    }

    /// Freezes the camera frame and opens the wormhole at the collected star's screen point.
    private func beginHandover(itemID: Int?, captureID: UUID?, point: CGPoint,freeze frozen: WormholeFreeze? = nil) {
        guard handover == nil, let onCollect, viewSize != .zero else { return }
        let freeze = frozen ?? service.wormholeFreeze() ?? .placeholder(size:viewSize)
        let handover = WormholeHandover(freeze:freeze,star:point,itemID:itemID,
                                        scene:GardenSkyView.wormholeScene(model:model,newID:itemID,location:service.observerLocation))
        handover.captureID = captureID
        // The wormhole renders from the frozen frame. Release the camera before the garden lands.
        service.stop()
        service.session.pause()
        // The wormhole owns the audio from success onward: silence every crosshair cue already scheduled.
        for sound in CrosshairSound.allCases { CrosshairFeedback.shared.suppress(sound,for:4) }
        WormholeFeedback.shared.play(landing:handover.landing)
        onCollect(.wormhole(handover))
    }

    #if DEBUG
    // MARK: Demo sky

    private func updateDemoProjections() {
        guard let location = service.observerLocation else {
            demoStars = []; demoProjections = []; demoDate = nil; demoLocation = nil
            return
        }
        let now = Date()
        if demoDate.map({ now < $0 || now.timeIntervalSince($0) >= 1 }) != false || demoLocation != location {
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
        guard service.status == .tracking, let location = service.observerLocation,
            let current = shownTarget, current.id == target.id,
            let freeze = service.wormholeFreeze()
        else {
            viewModel.errorMessage = "Wait for location and camera tracking, then aim at the star again."
            return
        }
        let date = Date()
        let stars = demoProjections.compactMap { entry in
            entry.point.map { (point: $0, color: entry.star.rgb) }
        }
        viewModel.verification = .checking(current.id)
        demoCaptureTask = Task {
            defer { demoCaptureTask = nil }
            let image = await DemoSky.composite(freeze.image, stars: stars, viewSize: freeze.size)
            guard !Task.isCancelled, phase != .background else {
                viewModel.verification = .idle
                return
            }
            guard let image else {
                viewModel.verification = .idle
                viewModel.errorMessage = "The camera couldn’t prepare the photo. Try again."
                return
            }
            var demoFreeze = freeze
            demoFreeze.image = image
            let draft = DemoSky.observation(star: current.star, image: image, date: date, location: location)
            viewModel.saveCapture(draft, for: current, freeze: demoFreeze)
        }
    }
    #endif


}

#Preview("Collect stars") {
    StarCollectCameraView(model: AppPreviewData.model, onClose: {})
        .preferredColorScheme(.dark)
}
