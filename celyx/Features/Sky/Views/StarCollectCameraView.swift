import ARKit
import SwiftUI

/// Real star collecting, styled like Figma "Camera Stand by" / "Camera Scanned" / "Camera Captured".
///
/// `SkyFinderService` does the work: GPS + true-north camera orientation (ARKit) project the HYG catalogue
/// onto the live camera image, and `CameraStarDetector` looks for an actual point of light at that spot.
/// The crosshair never moves: only what sits inside the centre circle is scanned. Star collection needs
/// fresh optical evidence. Tapping the camera captures the current frame immediately
/// and opens its album; verification happens during live scanning, before the tap.
struct StarCollectCameraView: View {
    typealias CenterTarget = StarCollectViewModel.CenterTarget

    let model: HomeViewModel
    let onClose: () -> Void
    @State private var zoomStart: Double?
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var viewModel: StarCollectViewModel
    private var service: SkyFinderService { viewModel.service }
    private var captureRadius: CGFloat { viewModel.captureRadius }
    private var isChecking: Bool { viewModel.isChecking }

    init(model: HomeViewModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        _viewModel = State(initialValue: StarCollectViewModel(model: model))
    }

    private var centerTarget: CenterTarget? { viewModel.centerTarget }
    private var shownTarget: CenterTarget? { viewModel.centerTarget }
    private func distance(_ point: CGPoint) -> CGFloat { viewModel.distance(point) }
    private func collect(_ target: CenterTarget) { viewModel.collect(target) }

    var body: some View {
        NavigationStack { cameraContent }
    }

    private var cameraContent: some View {
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
                    // CrosshairView's reticle sits 10pt above its own centre (see crosshair README).
                    reticle.position(x: geometry.size.width / 2, y: geometry.size.height / 2 + 10)
                        .allowsHitTesting(false)
                    if service.pinnedLight != nil, let guide = service.pinnedLightGuide {
                        CameraPinnedLightOverlay(
                            guide: guide, title: pinnedLightTitle, isRecognizing: isAnalyzingLight,
                            subtitle: service.retainedCaptureAnnotation != nil ? "Ready to collect" : nil)

                    }
                }
                .onAppear { viewModel.viewSize = geometry.size }
                .onChange(of: geometry.size) { _, size in viewModel.viewSize = size }
            }
            .ignoresSafeArea()

            if service.alignment.requiresCalibration, service.status == .tracking, shownTarget == nil {
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
            } else if service.pinnedLight != nil {
                pinnedLightPanel.padding(.horizontal, 6).padding(.bottom, 6)
            } else {
                CelyxHintPill(text: hintText, isLoading: isAnalyzingLight).padding(.bottom, 59).transition(
                    .opacity)
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
            await service.start()
        }
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
        .fullScreenCover(item: $viewModel.capturedItem, onDismiss: { Task { await service.start() } }) {
            item in
            StarAlbumView(
                item: item, onSaveNote: { model.updateObservationNote(id: item.id, note: $0) },
                onSavePlace: { model.updateObservationPlace(id: item.id, name: $0) })
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
        return CrosshairView(state: crosshairState, label: label)
    }
    private var crosshairState: CrosshairState {
        if isChecking { return .validating }
        if shownTarget != nil { return .enable }
        if isAnalyzingLight { return .locking }
        return .default
    }

    private var hintText: String {
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
                    CelyxCloseButton {
                        viewModel.verification = .idle
                        service.clearPinnedLight()
                    }
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
                Group {
                    if isCollected {
                        CelyxPillButton(title: "Collected", systemImage: "checkmark", style: .collected) {}
                            .allowsHitTesting(false)
                    } else {
                        CelyxPillButton(
                            title: checking ? "Saving…" : "Collect \(star.title)",
                            systemImage: "plus", style: checking ? .disabled : .primary
                        ) { collect(target) }
                        .accessibilityIdentifier("capture-star")
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .frame(height: star.isSolarDisc ? 228 : 248)
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

}

#Preview("Collect stars") {
    StarCollectCameraView(model: AppPreviewData.model, onClose: {})
        .preferredColorScheme(.dark)
}
