import ARKit
import SwiftUI
import simd

struct SkyCalibrationView: View {
    typealias Mode = SkyCalibrationViewModel.Mode
    typealias PreviewState = SkyCalibrationViewModel.PreviewState
    typealias Outcome = SkyCalibrationViewModel.Outcome
    typealias Target = SkyCalibrationViewModel.Target
    let onClose: () -> Void
    @State private var viewModel: SkyCalibrationViewModel

    init(
        catalogue: [CatalogStar], alignment: CameraSkyAlignment? = nil,
        preview: PreviewState? = nil, opensCatalog: Bool = false,
        initialLocation: ObserverLocation? = nil,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        _viewModel = State(
            initialValue: SkyCalibrationViewModel(
                catalogue: catalogue, alignment: alignment,
                preview: preview, opensCatalog: opensCatalog, initialLocation: initialLocation))
    }

    private var catalogMarkers: [CameraSkyPrediction] {
        let predictions = viewModel.engine.predictions
        var visible = predictions.filter { $0.guide.point != nil }
        if let id = viewModel.engine.selectedCatalogID, !visible.contains(where: { $0.id == id }),
            let selected = predictions.first(where: { $0.id == id })
        {
            visible.append(selected)
        }
        return visible
    }
    private var catalogLabels: Set<Int> {
        var points: [CGPoint] = []
        return Set(
            catalogMarkers.sorted {
                $0.id == viewModel.engine.selectedCatalogID && $1.id != viewModel.engine.selectedCatalogID
            }.filter {
                guard let point = $0.guide.point, points.count < 12,
                    !points.contains(where: { hypot($0.x - point.x, $0.y - point.y) < 65 })
                else { return false }
                points.append(point)
                return true
            }.map(\.id))
    }
    private var reticleState: CrosshairState {
        if viewModel.saved { return .enable }
        if viewModel.mode == .pattern
            && (viewModel.progress > 0
                || viewModel.engine.centerDirection != nil
                    && viewModel.engine.lights.count >= SkyPatternMatcher.minimumAutomaticPatternStars)
        {
            return .validating
        }
        return viewModel.engine.referenceReady
            ? .enable : viewModel.engine.centerDirection != nil ? .locking : .default
    }
    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { geometry in
                ZStack {
                    if viewModel.previewState == nil {
                        SkyCameraPreview(
                            session: viewModel.engine.session,
                            onViewport: { size, orientation in
                                viewModel.engine.viewport = size
                                viewModel.engine.orientation = orientation
                            }, skyMarkers: viewModel.showsCandidateAR ? catalogMarkers : [],
                            labeledMarkerIDs: viewModel.showsCandidateAR ? catalogLabels : [],
                            selectedMarkerID: viewModel.engine.selectedCatalogID,
                            onSelectMarker: { viewModel.engine.selectedCatalogID = $0 })
                    } else {
                        Color(red: 0.025, green: 0.04, blue: 0.1)
                    }
                    if viewModel.previewState == .catalogAR {
                        ForEach(Array(viewModel.engine.candidates.prefix(4).enumerated()), id: \.element.id) {
                            index, candidate in
                            VStack(spacing: 5) {
                                Circle().stroke(.cyan, lineWidth: 1).frame(width: 16, height: 16)
                                Text(candidate.star.title).font(.caption).foregroundStyle(.cyan)
                            }.position(
                                x: geometry.size.width * (0.23 + Double(index) * 0.17),
                                y: geometry.size.height * (index.isMultiple(of: 2) ? 0.31 : 0.45))
                        }
                    }
                    if viewModel.mode == .pattern && !viewModel.showsCandidateAR {
                        ForEach(viewModel.engine.lights) { light in
                            Circle().stroke(.cyan, lineWidth: 1).frame(width: 14, height: 14).position(
                                light.point
                            )
                            .allowsHitTesting(false)
                        }
                        if viewModel.previewState != nil {
                            ForEach(0..<(viewModel.previewState == .singleLight ? 1 : 4), id: \.self) {
                                index in
                                Circle().fill(.white).frame(width: 4, height: 4)
                                    .position(
                                        x: geometry.size.width * (0.25 + Double(index) * 0.16),
                                        y: geometry.size.height * (index.isMultiple(of: 2) ? 0.35 : 0.48))
                            }
                        }
                    }
                    if !viewModel.showsCandidateAR {
                        CrosshairView(
                            state: viewModel.previewState == .matching ? .validating : reticleState,
                            soundEnabled: false, hapticsEnabled: false,
                            idleLoops: viewModel.previewState == nil
                        )
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2 + 10)
                        .accessibilityHidden(true)
                    }
                }
                .onAppear { viewModel.engine.viewport = geometry.size }
            }.ignoresSafeArea()
            VStack {
                HStack {
                    CelyxBackButton {
                        if viewModel.showsCandidateAR { viewModel.showsCandidateAR = false } else { close() }
                    }
                    Spacer()
                    if viewModel.showsCandidateAR {
                        Text("Calibration AR").font(.headline).foregroundStyle(.white)
                        Spacer()
                    }
                    CelyxGlassButton(action: { viewModel.showsCandidates = true }) {
                        Image(systemName: "list.star").font(.system(size: 20)).foregroundStyle(.white)
                    }.accessibilityLabel("Calibration Stars")
                }.padding(.horizontal, 20)
                Spacer()
            }
            Group {
                if viewModel.showsCandidateAR { catalogARPanel } else { panel }
            }.padding(.horizontal, 6).padding(.bottom, 6).ignoresSafeArea(edges: .bottom)
        }
        .background(.black).preferredColorScheme(.dark)
        .task { await viewModel.start() }
        .task(id: viewModel.location?.coordinateLabel) {
            guard viewModel.previewState == nil else { return }
            while !Task.isCancelled {
                viewModel.refreshTargets()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .onChange(of: viewModel.engine.solution) { _, solution in
            guard viewModel.mode == .pattern, !viewModel.showsCandidates, !viewModel.showsCandidateAR,
                let solution, !viewModel.saved
            else { return }
            viewModel.save(
                offset: solution.headingOffset, label: "\(solution.matches.count)-star pattern",
                message: String(
                    format: "Pattern confirmed with %d stars · fit RMS %.2f°", solution.matches.count,
                    solution.residualDegrees))
        }
        .sheet(isPresented: $viewModel.showsCandidates) {
            CalibrationCatalogView(
                engine: viewModel.engine, onChoose: viewModel.chooseCandidate,
                onViewAR: {
                    viewModel.showsCandidateAR = true
                    viewModel.showsCandidates = false
                }
            ).celyxSheet(detents: [.large])
        }
        .onChange(of: viewModel.showsCandidates) { _, _ in
            viewModel.engine.isBrowsing = viewModel.showsCandidates || viewModel.showsCandidateAR
        }
        .onChange(of: viewModel.showsCandidateAR) { _, _ in
            viewModel.engine.isBrowsing = viewModel.showsCandidates || viewModel.showsCandidateAR
        }
        .confirmationDialog(
            "Use \(viewModel.target?.name ?? "this candidate") as the detected light?",
            isPresented: $viewModel.confirmsSingleIdentity, titleVisibility: .visible
        ) {
            Button("Confirm single-object reference") { viewModel.calibrate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "A single light cannot independently establish its catalog identity. This saves a manual correction for the candidate you confirm."
            )
        }
        .onDisappear(perform: stop)
        .onChange(of: phase) { _, value in
            guard viewModel.previewState == nil else { return }
            if value == .active, !viewModel.cameraDenied {
                viewModel.engine.start()
            } else {
                viewModel.outcome = .none
                viewModel.engine.stop()
                viewModel.engine.alignment.enterBackground()
            }
        }
    }
    @Environment(\.scenePhase) private var phase

    // MARK: Calibration controls

    private var panel: some View {
        ZStack(alignment: .top) {
            CelyxBluePanel(cornerRadius: 34)
            CelyxGrabber()
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    viewModel.mode == .reference
                        ? "Calibrate with a reference" : "Calibrate with visible lights"
                )
                .font(.system(size: 22, weight: .bold)).foregroundStyle(CelyxColor.primaryLabel)
                Text(viewModel.instruction).font(.system(size: 13)).foregroundStyle(
                    CelyxColor.secondaryLabel
                )
                .fixedSize(horizontal: false, vertical: true)
                if viewModel.mode == .reference { referenceControls } else { patternControls }
                statusLine
                if viewModel.saved {
                    CelyxPillButton(title: "Done", style: .primary, action: close)
                } else if SkyCalibration.isCalibrated {
                    Button("Reset saved calibration") {
                        guard viewModel.previewState == nil else { return }
                        SkyCalibration.reset()
                        viewModel.outcome = .none
                        viewModel.engine.resetSearch()
                    }
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
                }
            }.padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 22)
        }.fixedSize(horizontal: false, vertical: true)
    }
    @ViewBuilder private var referenceControls: some View {

        if viewModel.referenceTargets.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.referenceTargets) { item in
                        Button {
                            viewModel.selectedID = item.id
                            viewModel.selectedFromCatalog = !viewModel.targets.contains(where: {
                                $0.id == item.id
                            })
                            viewModel.outcome = .none
                            viewModel.engine.resetSearch()
                        } label: {
                            Text(item.name).font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12).frame(height: 32)
                        }.buttonStyle(.plain)
                            .glassEffect(
                                item.id == viewModel.target?.id
                                    ? .regular.tint(.white.opacity(0.3)).interactive()
                                    : .regular.interactive(),
                                in: Capsule())
                    }
                }
            }
        }
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in readout }
        CelyxPillButton(
            title: viewModel.engine.referenceReady || viewModel.previewState != nil
                ? "Confirm reference identity" : "Put the object in the circle",
            style: viewModel.target != nil
                && (viewModel.engine.referenceReady || viewModel.previewState != nil)
                && !viewModel.saved ? .primary : .disabled,
            action: {
                if viewModel.selectedFromCatalog {
                    viewModel.confirmsSingleIdentity = true
                } else {
                    viewModel.calibrate()
                }
            })
        Button("Choose another candidate or compare visible lights") {
            viewModel.choose(.pattern)
        }
        .font(.system(size: 13, weight: .semibold)).foregroundStyle(CelyxColor.primaryLabel)
    }
    @ViewBuilder private var patternControls: some View {

        HStack {
            Text("Detected lights").foregroundStyle(.white.opacity(0.65))
            Spacer()
            Text(
                "\(viewModel.previewState == nil ? viewModel.engine.lights.count : viewModel.previewState == .singleLight ? 1 : 4) · one or more"
            ).foregroundStyle(.white).monospacedDigit()
        }.font(.system(size: 13))
        if !viewModel.saved {
            ProgressView(value: viewModel.progress).tint(CelyxColor.ready)
            Text(
                viewModel.previewState == .matching
                    ? "Comparing 4 lights with nearby catalog patterns… Hold steady."
                    : viewModel.engine.message
            )
            .font(.system(size: 13)).foregroundStyle(.white.opacity(0.8)).fixedSize(
                horizontal: false, vertical: true)
        }
        Text(
            "One light can be used after you choose and confirm its reference. Additional lights help the app compare patterns automatically."
        )
        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
        CelyxPillButton(title: "Choose a reference · Calibration Stars", style: .primary) {
            viewModel.showsCandidates = true
        }
        if !viewModel.targets.isEmpty {
            Button("Use a known Sun, Moon or star instead") { viewModel.choose(.reference) }
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(
                    CelyxColor.primaryLabel)
        }
    }

    private var catalogARPanel: some View {
        ZStack(alignment: .top) {
            CelyxBluePanel(cornerRadius: 34)
            CelyxGrabber()
            catalogARContent.padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 22)
        }.fixedSize(horizontal: false, vertical: true)
    }

    private var catalogARContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Calibration catalog").font(.system(size: 22, weight: .bold))
            Text(
                "This maps the separate Calibration Stars list. Markers are possible reference positions, not camera identifications."
            )
            .font(.system(size: 13)).foregroundStyle(CelyxColor.secondaryLabel)
            .fixedSize(horizontal: false, vertical: true)
            if let candidate = viewModel.engine.candidates.first(where: {
                $0.id == viewModel.engine.selectedCatalogID
            }) {
                Text(candidate.star.title).font(.system(size: 17, weight: .semibold))
                Text(String(format: "%.0f° up · %.0f° azimuth", candidate.altitude, candidate.azimuth))
                    .font(.system(size: 13)).foregroundStyle(CelyxColor.secondaryLabel)
                if let guide = viewModel.engine.predictions.first(where: { $0.id == candidate.id })?.guide {
                    Text(
                        guide.isAligned
                            ? "Near the center of your view"
                            : abs(guide.arrow.dx) > abs(guide.arrow.dy)
                                ? (guide.arrow.dx > 0
                                    ? "Turn right toward this candidate" : "Turn left toward this candidate")
                                : (guide.arrow.dy > 0
                                    ? "Point lower toward this candidate"
                                    : "Point higher toward this candidate")
                    )
                    .font(.system(size: 13)).foregroundStyle(CelyxColor.secondaryLabel)
                }
                CelyxPillButton(title: "Use as a reference", style: .primary) {
                    viewModel.chooseCandidate(candidate)
                }
            }
            Button("Open Calibration Stars") { viewModel.showsCandidates = true }
                .font(.system(size: 13, weight: .semibold))
        }.foregroundStyle(CelyxColor.primaryLabel)
    }
    // MARK: Reference selection

    @ViewBuilder private var readout: some View {
        if let target = viewModel.target {
            VStack(alignment: .leading, spacing: 4) {
                row(
                    "\(target.name) is at",
                    String(format: "%.0f° · %.0f° up", degrees(target.azimuth), target.altitude * 180 / .pi))
                if let ar = viewModel.arAim() {
                    let turn =
                        SkyCalibration.wrap(target.azimuth - (ar.azimuth + SkyCalibration.arHeadingOffset))
                        * 180 / .pi
                    row("Estimated turn", String(format: "%.0f° %@", abs(turn), turn > 0 ? "right" : "left"))
                }
                row(
                    "Camera light",
                    viewModel.engine.referenceReady ? "Steady in circle" : "Waiting for a steady light")
            }
        }
    }
    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.white.opacity(0.55))
            Spacer()
            Text(value).foregroundStyle(.white).monospacedDigit()
        }
        .font(.system(size: 13))
    }
    @ViewBuilder private var statusLine: some View {
        switch viewModel.outcome {
        case .saved(let message):
            Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(CelyxColor.ready)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange)
        case .none:
            if let motionMessage = viewModel.motionMessage {
                Text(motionMessage).foregroundStyle(.white.opacity(0.55))
            }
        }
    }
    private func stop() { viewModel.stop(preservingAlignment: phase == .active) }
    private func close() {
        stop()
        onClose()
    }
    private func degrees(_ value: Double) -> Double {
        (value * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}

#Preview("Calibration · known object") {
    SkyCalibrationView(catalogue: [], preview: .reference) {}
}
#Preview("Calibration · star pattern") {
    SkyCalibrationView(catalogue: [], preview: .pattern) {}
}
#Preview("Calibration · matching") {
    SkyCalibrationView(catalogue: [], preview: .matching) {}
}
#Preview("Calibration · saved") {
    SkyCalibrationView(catalogue: [], preview: .saved) {}
}

#Preview("Calibration · one light") {
    SkyCalibrationView(catalogue: AppPreviewData.model.stars, preview: .singleLight) {}
}
#Preview("Calibration · catalog AR") {
    SkyCalibrationView(catalogue: AppPreviewData.model.stars, preview: .catalogAR) {}
}
