import AVFoundation
import SwiftUI

/// The personal garden behind Home: the Night Sea environment (sky, islands, reflective sea) whose sky
/// only holds what the user has collected, each at its REAL position right now for the user's location.
/// The phone's gyro + compass (true north) drive the view; dragging adds an offset. Tap an object for details.
struct GardenSkyView: View {
    let model: HomeViewModel
    @Binding var camera: NightSeaCamera
    var isActive = true
    /// Bump to face north (no gyro) or clear the drag offset (gyro).
    var resetRequest = 0
    /// Live camera behind the collected objects instead of the virtual Night Sea.
    var usesCamera = false
    var usesGyro = true
    var onUseTouch: (() -> Void)?

    @State private var viewModel: GardenViewModel
    @State private var failed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        model: HomeViewModel, camera: Binding<NightSeaCamera>, isActive: Bool = true,
        resetRequest: Int = 0, usesCamera: Bool = false, usesGyro: Bool = true,
        onUseTouch: (() -> Void)? = nil
    ) {
        self.model = model
        _camera = camera
        self.isActive = isActive
        self.resetRequest = resetRequest
        self.usesCamera = usesCamera
        self.usesGyro = usesGyro
        self.onUseTouch = onUseTouch
        _viewModel = State(initialValue: GardenViewModel(model: model, camera: camera.wrappedValue))
    }

    var body: some View {
        Group {
            if usesCamera {
                GardenCameraLayer(
                    placed: viewModel.placed, selectedID: viewModel.selected?.id, isActive: isActive
                ) { viewModel.selected = $0 }
                .transition(.opacity)
            } else {
                virtualGarden.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: usesCamera)
        .overlay(alignment: .bottom) {
            if let gyroMessage = viewModel.gyroMessage, isActive, !usesCamera, usesGyro,
                !viewModel.gyroLive
            {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        if viewModel.gyroStage != .blocked { ProgressView().tint(.white) }
                        Text(gyroMessage).font(.system(size: 13, weight: .medium))
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                    if viewModel.gyroStage == .settling {
                        ProgressView(value: viewModel.gyroProgress).tint(.white)
                    }
                    if let onUseTouch {
                        Button("Use Touch instead", action: onUseTouch).font(.subheadline.weight(.semibold))
                    }
                }
                .foregroundStyle(.white).padding(14)
                .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 28).padding(.bottom, 135)
                .accessibilityIdentifier("garden-gyro-status")
            }
        }
        // Real positions: recomputed every second from GPS + clock (the sky turns ~0.25° a minute).
        .task(id: isActive) {
            guard isActive else { return }
            while !Task.isCancelled {
                viewModel.place()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onChange(of: model.collectionItems.count) { old, new in
            viewModel.place()
            // Something new: without gyro, turn to face it.
            if new > old, viewModel.camera.orientation == nil,
                let latest = viewModel.placed.first(where: { $0.id == model.collectionItems.first?.id })
            {
                viewModel.camera.azimuth = atan2(latest.object.direction.x, latest.object.direction.y)
            }
        }
        // The camera mode orients itself with ARKit; the gyro only drives the virtual garden.
        .onChange(of: isActive && !usesCamera, initial: true) { _, active in
            active ? viewModel.startGyro(usesGyro: usesGyro) : viewModel.stopGyro()
        }
        .onChange(of: usesGyro) { _, _ in
            if isActive && !usesCamera { viewModel.startGyro(usesGyro: usesGyro) }
        }
        .onChange(of: resetRequest) { _, _ in viewModel.resetCamera() }
        .onChange(of: viewModel.camera) { _, value in if camera != value { camera = value } }
        .onChange(of: camera) { _, value in if viewModel.camera != value { viewModel.camera = value } }
        .onChange(of: reduceMotion, initial: true) { _, value in viewModel.reduceMotion = value }
        .onDisappear(perform: viewModel.stopGyro)
        .sheet(item: $viewModel.selected) { item in
            CollectedObjectSheet(
                item: item,
                direction: viewModel.placed.first(where: { $0.id == item.id })?.object.direction,
                onSaveNote: { model.updateObservationNote(id: item.id, note: $0) },
                onSavePlace: { model.updateObservationPlace(id: item.id, name: $0) }
            ) {
                model.deleteCollected(id: item.id)
                viewModel.selected = nil
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your garden sky")
    }

    private var virtualGarden: some View {
        GeometryReader { geometry in
            ZStack {
                if failed {
                    Image("celyx-home-sky").resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .trailing)
                        .clipped()
                } else {
                    NightSeaView(
                        camera: viewModel.camera, objects: viewModel.placed.map(\.object),
                        selectedID: viewModel.selected?.id, moon: viewModel.moon,
                        equatorial: viewModel.equatorial, isActive: isActive
                    ) { _ in failed = true }
                }
                labels(in: geometry.size)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in viewModel.drag(value.translation, in: geometry.size) }
                    .onEnded { _ in viewModel.dragStart = nil }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        if viewModel.camera.orientation != nil {
                            if viewModel.zoomStart == nil { viewModel.zoomStart = viewModel.camera.zoom }
                            viewModel.camera.zoom = min(
                                4, max(0.5, (viewModel.zoomStart ?? 1) * value.magnification))
                        } else {
                            if viewModel.zoomStart == nil {
                                viewModel.zoomStart = viewModel.camera.fieldOfView
                            }
                            viewModel.camera.fieldOfView = min(
                                110, max(24, (viewModel.zoomStart ?? 72) / value.magnification))
                        }
                    }
                    .onEnded { _ in viewModel.zoomStart = nil }
            )
            .simultaneousGesture(
                SpatialTapGesture().onEnded { value in viewModel.tap(at: value.location, in: geometry.size)
                })
        }
    }

    // MARK: Labels

    @ViewBuilder private func labels(in size: CGSize) -> some View {
        ForEach(viewModel.placed.filter(\.object.isAboveHorizon)) { entry in
            if let point = viewModel.camera.project(entry.object.direction, in: size),
                point.x > -40, point.x < size.width + 40, point.y > -40, point.y < size.height + 40
            {
                Button {
                    viewModel.selected = entry.item
                } label: {
                    Text(entry.item.star.title)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.7), radius: 3)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(x: point.x, y: point.y + entry.object.radius * 0.45 + 14)
                .accessibilityLabel("\(entry.item.star.title), collected \(entry.item.collectedDate)")
                .accessibilityHint("Shows details")
            }
        }
    }

}

#Preview("Garden sky") {
    GardenSkyView(model: AppPreviewData.collectedModel, camera: .constant(NightSeaCamera()))
        .preferredColorScheme(.dark)
}
