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
        case fade(itemID: Int?)
    }

    let model: HomeViewModel
    let onClose: () -> Void
    /// The running handover, if any (fades this screen's UI on its clock).
    var handover: WormholeHandover? = nil
    /// When set, a successful collect hands over to the garden (wormhole) instead of opening the album here.
    var onCollect: ((CollectResult) -> Void)? = nil
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
    #if DEBUG
    /// Catalog stars at their real current horizon positions; demo bypasses optical detection.
    @State private var didPrepareDemoCollection = false
    @State private var demoFinalStarID: Int?
    @State private var demoStars: [DemoSky.Entry] = []
    @State private var demoProjections: [DemoSky.Projection] = []
    @State private var demoOn = false
    @State private var showsDemoNotice = false
    @State private var demoDate: Date?
    @State private var demoLocation: ObserverLocation?
    private var demoTargets: [DemoSky.Projection] {
        demoProjections.filter { $0.id == demoFinalStarID }
    }
    private var demoGuide: DemoSky.Projection? {
        demoTargets.filter { model.collected[$0.id] == nil && $0.id != viewModel.excludedID }
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
            guard let target = DemoSky.target(in: demoTargets,
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
                            onTap: handleCameraTap,
                            onExposureDrag: { translation, _, ended in
                                service.dragExposure(translation: translation, ended: ended)
                            },
                            zoom: service.cameraZoom
                        )
                        // Hidden behind the night colour until the camera delivers real frames, then a quick fade.
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
                        ForEach(demoTargets.filter { model.collected[$0.id] == nil }) { entry in
                            if let point = entry.point {
                                DemoStarView(color: entry.star.rgb)
                                    .position(point)
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
                        CameraCollectionPrompt(text: model.collected[target.id] != nil ? "Already in your garden"
                            : isChecking ? "Collecting…"
                            : viewModel.verification == .failed(target.id) ? "Keep the light in view and try again"
                            : "Tap anywhere to collect", ready: true)
                        sheet(for: target)
                    }
                    .padding(.horizontal, 20)
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
            #if DEBUG
            if demoOn && showsDemoNotice {
                DemoModeNotice()
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8).opacity(cameraUI)
                    .transition(.opacity)
            }
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
            if onCollect != nil {
                WormholeFeedback.shared.prepare()
                if !reduceMotion { WormholeRenderer.prepare() }
            }
            await service.start()
        }
        .task {
            // Wait for the first real AR frame, plus a couple more so the preview has its orientation.
            while !Task.isCancelled && service.session.currentFrame == nil { try? await Task.sleep(for: .milliseconds(40)) }
            try? await Task.sleep(for: .milliseconds(90))
            feedReady = true
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
        .onChange(of: shownTarget?.id) { _, id in if let id { viewModel.lockedID = id } }
        .onChange(of: centerTarget?.id) { _, id in if id == nil || id != viewModel.lockedID { viewModel.lockedID = nil } }
        .onChange(of: excludedIsNear) { _, near in if !near { viewModel.excludedID = nil } }
        #if DEBUG
        .task(id: demoOn) {
            guard demoOn else { showsDemoNotice = false; return }
            showsDemoNotice = true
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                showsDemoNotice = false
            }
        }
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
            } else if value == .background {
                if viewModel.capturedItem == nil { service.suspendForBackground() }
                else { service.stop() }
            }
            // Inactive includes screenshot editors and Control Center. Native capture
            // interruptions handle those; do not stop a live session for a brief overlay.
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
            guard service.observerLocation != nil else { return "Waiting for your location to map Libra, Aries and Capricornus" }
            if didPrepareDemoCollection && demoFinalStarID == nil {
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
            return CameraTargetSelection.canAcquireInReticle(at: point, center: center) ? "\(name) is in your circle. Tap to collect" : "Tap \(name) to collect, or bring it into your circle"
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

    private func handleCameraTap(_ point: CGPoint) {
        #if DEBUG
        if demoOn, let tapped = DemoSky.tappedTarget(in: demoTargets, at: point,
            collected: Set(model.collected.keys), excludedID: viewModel.excludedID), let position = tapped.point {
            collect(CenterTarget(star: tapped.star,
                detection: CameraStarAnnotation(star: tapped.star, point: position, size: CGSize(width: 28, height: 28))))
            return
        }
        #endif
        if let target = shownTarget { collect(target) }
        else { _ = service.focus(at: point) }
    }

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
        demoOn.toggle()
        didPrepareDemoCollection = false
        demoFinalStarID = nil
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
        if !didPrepareDemoCollection {
            do {
                demoFinalStarID = try DemoSky.prepareCollection(model: model, date: now, location: location)?.id
                didPrepareDemoCollection = true
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
        // Revalidate the selected virtual source in the current frame. A direct
        // tap can select a visible star outside the center reticle in demo mode.
        updateDemoProjections()
        guard let location = service.observerLocation,
            let current = demoTargets.first(where: { $0.id == target.id && model.collected[$0.id] == nil }),
            let point = current.point, var freeze = service.wormholeFreeze()
        else {
            viewModel.verification = .idle
            viewModel.errorMessage = "Wait for location and camera tracking, then aim at the star again."
            return
        }
        let date = Date()
        freeze.image = DemoSky.composite(freeze.image, stars: demoTargets.filter { model.collected[$0.id] == nil }.compactMap { entry in
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
