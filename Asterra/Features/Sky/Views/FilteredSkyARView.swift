import SwiftUI

struct FilteredSkyARView: View {
    let model: HomeViewModel
    @State private var service: SkyFinderService
    @State private var selectedID: Int?
    @State private var zoomStart: Double?
    @State private var showsCalibration = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @Environment(\.openURL) private var openURL

    init(model: HomeViewModel, selectedID: Int? = nil) {
        self.model = model
        _selectedID = State(initialValue: selectedID)
        _service = State(
            initialValue: SkyFinderService(
                location: model.location, catalogue: model.stars,
                showsPredictions: true, alignment: model.cameraAlignment))
    }

    private var markers: [CameraSkyPrediction] {
        let ids = Set(model.predictedVisibleObjects.map(\.id))
        return service.predictions.filter { ids.contains($0.id) }
    }
    private var target: CameraSkyPrediction? {
        markers.first(where: { $0.id == selectedID })
            ?? markers.min { $0.guide.separation < $1.guide.separation }
    }
    private var labels: Set<Int> {
        var points: [CGPoint] = []
        return Set(
            markers.sorted {
                if $0.id == $1.id { return false }
                if $0.id == selectedID { return true }
                if $1.id == selectedID { return false }
                return $0.guide.separation < $1.guide.separation
            }.filter {
                guard let point = $0.guide.point, points.count < 12,
                    !points.contains(where: { hypot($0.x - point.x, $0.y - point.y) < 65 })
                else { return false }
                points.append(point)
                return true
            }.map(\.id))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            CelyxColor.night.ignoresSafeArea()
            if service.isCameraRunning {
                SkyCameraPreview(
                    session: service.session, onViewport: service.updateViewport,
                    onExposureDrag: { translation, _, ended in
                        service.dragExposure(translation: translation, ended: ended)
                    },
                    skyMarkers: markers, labeledMarkerIDs: labels, selectedMarkerID: selectedID,
                    onSelectMarker: { selectedID = $0 }, zoom: service.cameraZoom
                )
                .ignoresSafeArea()
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            if zoomStart == nil { zoomStart = service.cameraZoom }
                            service.setZoom((zoomStart ?? 1) * value.magnification)
                        }.onEnded { _ in zoomStart = nil })
            }
            VStack {
                HStack {
                    CelyxBackButton {
                        service.stop()
                        dismiss()
                    }
                    Spacer()
                    Text("Filtered Stars AR").font(.system(size: 17, weight: .semibold))
                    Spacer()
                    CelyxGlassButton(action: {
                        service.stop()
                        showsCalibration = true
                    }) {
                        Image(systemName: "scope").foregroundStyle(CelyxColor.primaryLabel)
                    }.accessibilityLabel("Calibrate direction")
                }.padding(.horizontal, 20)
                Spacer()
            }
            statusPanel.padding(.horizontal, 6).padding(.bottom, 6)
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
        .foregroundStyle(CelyxColor.primaryLabel).preferredColorScheme(.dark)
        .task { await start() }
        .onChange(of: model.visibilityFilters) { _, _ in updateVisibility() }
        .onChange(of: model.quality) { _, _ in updateVisibility() }
        .onChange(of: model.atmosphere) { _, _ in updateVisibility() }
        .onDisappear { service.stop() }
        .onChange(of: phase) { _, value in
            if value == .active, !showsCalibration {
                Task { await start() }
            } else if value == .background {
                service.suspendForBackground()
            } else {
                service.stop()
            }
        }
        .fullScreenCover(isPresented: $showsCalibration, onDismiss: { Task { await start() } }) {
            SkyCalibrationView(catalogue: model.stars, alignment: model.cameraAlignment) {
                showsCalibration = false
            }
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(model.predictedVisibleObjects.count) filtered objects").font(
                .system(size: 17, weight: .semibold))
            Text(
                "The same visibility filters as your list. Markers show predicted positions, not camera detections."
            )
            .font(.system(size: 13)).foregroundStyle(CelyxColor.secondaryLabel)
            if service.alignment.requiresCalibration {
                Text("Calibrate direction to restore the sky markers.").font(.system(size: 13))
                CelyxPillButton(title: "Calibrate direction") {
                    service.stop()
                    showsCalibration = true
                }
            } else {
                status
            }
            if let target {
                Text(target.star.title).font(.system(size: 17, weight: .semibold))
                Text(target.guide.isAligned ? "Near the center of your view" : instruction(target.guide))
                    .font(.system(size: 13)).foregroundStyle(CelyxColor.secondaryLabel)
            }
        }.padding(20).background(CelyxBluePanel(cornerRadius: 28))
    }

    @ViewBuilder private var status: some View {
        switch service.status {
        case .tracking:
            if markers.isEmpty, !model.predictedVisibleObjects.isEmpty {
                Text("Waiting for reliable direction. Calibrate if markers do not appear.")
                    .font(.system(size: 13)).foregroundStyle(CelyxColor.secondaryLabel)
            }
        case .preparing, .requestingPermission:
            ProgressView("Getting the camera and location ready…").tint(CelyxColor.primaryLabel)
        case .limited(let message), .unavailable(let message):
            Text(message).font(.system(size: 13))
        case .denied(let message):
            Text(message).font(.system(size: 13))
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        }
    }

    private func instruction(_ guide: SkyFinderProjection) -> String {
        if abs(guide.arrow.dx) > abs(guide.arrow.dy) {
            return guide.arrow.dx > 0 ? "Turn right" : "Turn left"
        }
        return guide.arrow.dy > 0 ? "Point lower" : "Point higher"
    }
    private func start() async {
        updateVisibility()
        await service.start()
    }
    private func updateVisibility() {
        service.updateVisibility(
            quality: model.quality, atmosphere: model.atmosphere, filters: model.visibilityFilters)
    }
}

#Preview("Filtered stars AR") {
    FilteredSkyARView(model: AppPreviewData.model)
}
