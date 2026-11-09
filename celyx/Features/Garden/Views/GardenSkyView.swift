import AVFoundation
import simd
import SwiftUI

/// The personal garden behind Home: the Night Sea environment (sky, islands, reflective sea) whose sky
/// only holds what the user has collected, each at its REAL position right now for the user's location.
/// The phone's gyro + compass (true north) drive the view; swiping switches to touch mode. Tap an object for details.
struct GardenSkyView: View {
    let model: HomeViewModel
    @Binding var camera: NightSeaCamera
    var isActive = true
    /// Bump to face north (no gyro) or keep the real direction (gyro).
    var resetRequest = 0
    /// Live camera behind the collected objects instead of the virtual Night Sea.
    var usesCamera = false
    var usesGyro = true
    var onModeChange: ((Bool) -> Void)?
    /// Wormhole handover from the collect camera: drives the view during landing + reframe.
    var handover: WormholeHandover?
    /// Shows a collected object's album after a handover (or the Reduce Motion fade).
    var sheetRequest: GardenSheetRequest?
    /// Called when the demo object's album closes (debug replay).
    var onDemoEnded: () -> Void = {}

    @State private var viewModel: GardenViewModel
    @State private var failed = false
    /// The album shown right after a capture's wormhole lands.
    @State private var albumRequest: GardenSheetRequest?
    /// The card has just flown home: a small bloom where the star lands.
    @State private var landing: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        model: HomeViewModel, camera: Binding<NightSeaCamera>, isActive: Bool = true,
        resetRequest: Int = 0, usesCamera: Bool = false, usesGyro: Bool = true,
        onModeChange: ((Bool) -> Void)? = nil, handover: WormholeHandover? = nil,
        sheetRequest: GardenSheetRequest? = nil, onDemoEnded: @escaping () -> Void = {}
    ) {
        self.handover = handover
        self.sheetRequest = sheetRequest
        self.onDemoEnded = onDemoEnded
        self.model = model
        _camera = camera
        self.isActive = isActive
        self.resetRequest = resetRequest
        self.usesCamera = usesCamera
        self.usesGyro = usesGyro
        self.onModeChange = onModeChange
        _viewModel = State(initialValue: GardenViewModel(model: model, camera: camera.wrappedValue))
    }

    var body: some View {
        Group {
            if usesCamera {
                GardenCameraLayer(
                    placed: viewModel.placed, selectedID: viewModel.selected?.id,
                    connections: shownConnections, isActive: isActive
                ) { viewModel.selected = $0 }
                .transition(.opacity)
            } else {
                virtualGarden.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: usesCamera)
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
        // The camera mode orients itself with Core Motion; the gyro only drives the virtual garden.
        .onChange(of: isActive && !usesCamera, initial: true) { _, active in
            active ? viewModel.startGyro(usesGyro: usesGyro) : viewModel.stopGyro()
        }
        .onChange(of: usesGyro) { _, _ in
            if isActive && !usesCamera { viewModel.setGyroMode(usesGyro) }
        }
        .onChange(of: viewModel.usesGyro) { _, enabled in onModeChange?(enabled) }
        .onChange(of: resetRequest) { _, _ in viewModel.resetCamera() }
        .onChange(of: viewModel.camera) { _, value in if camera != value { camera = value } }
        .onChange(of: camera) { _, value in if viewModel.camera != value { viewModel.camera = value } }
        .onChange(of: reduceMotion, initial: true) { _, value in viewModel.reduceMotion = value }
        .onDisappear(perform: viewModel.stopGyro)
        .onChange(of: handover?.phase) { _, phase in
            if phase == .landed, let next = handover?.demo {
                viewModel.demo = next
                viewModel.place()
            }
            if phase == .releasing { prepareRelease() }
        }
        // After a capture: the sky album (photo, place and time, note, share) right after landing.
        .onChange(of: sheetRequest) { _, request in
            guard let request,
                model.collectionItems.contains(where: { $0.id == request.itemID }) || request.demoItem != nil
            else { return }
            albumRequest = request
        }
        .fullScreenCover(item: $albumRequest, onDismiss: { endDemo(); handover?.beginRelease() }) { request in
            if let item = model.collectionItems.first(where: { $0.id == request.itemID }) {
                StarAlbumView(
                    item: item, photo: request.photo,
                    onSaveNote: { model.updateObservationNote(id: item.id, note: $0) },
                    onSavePlace: { model.updateObservationPlace(id: item.id, name: $0) },
                    flyHome: flyHome)
            } else if let demo = request.demoItem {
                // Demo: never saved.
                StarAlbumView(item: demo, photo: request.photo, onSaveNote: { _ in }, onSavePlace: { _ in }, flyHome: flyHome)
            }
        }
        .overlay {
            // The collected star finishing its flight into place after the hand-off from the camera.
            if let handover, handover.phase < .releasing { LandingStarFlight(handover: handover).ignoresSafeArea() }
        }
        .overlay { landingBloom }
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

    /// Collected objects to draw; the one just collected waits until its flight lands (LandingStarFlight).
    private var shownPlaced: [NightSeaObject] {
        let objects = viewModel.placed.map(\.object)
        guard let handover, let id = handover.scene.newID, handover.phase < .releasing,
            handover.tt() < handover.landing + WormholeTimeline.flyEnd
        else { return objects }
        return objects.filter { $0.id != id }
    }

    /// Let the star land and its album close before drawing the new threads into the garden.
    private var shownConnections: [GardenConstellationConnection] {
        guard let handover, handover.phase < .releasing, let id = handover.itemID else {
            return viewModel.constellationConnections
        }
        return viewModel.constellationConnections.filter { $0.startID != id && $0.endID != id }
    }

    /// The camera actually rendered: the handover's while it lands and reframes, then the garden's own.
    private func viewCamera() -> NightSeaCamera {
        guard let handover, handover.phase >= .landed, handover.phase < .done else { return viewModel.camera }
        handover.target = handover.phase >= .releasing ? viewModel.camera : nil
        return handover.camera(handover.tt())
    }

    private var virtualGarden: some View {
        TimelineView(.animation(paused: handover == nil || handover?.phase == .done)) { _ in
            virtualGarden(shown: viewCamera())
        }
    }

    private func virtualGarden(shown: NightSeaCamera) -> some View {
        GeometryReader { geometry in
            ZStack {
                if failed {
                    Image("celyx-home-sky").resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .trailing)
                        .clipped()
                } else {
                    NightSeaView(
                        camera: shown, objects: viewModel.background + shownPlaced,
                        selectedID: viewModel.selected?.id, moon: viewModel.moon,
                        equatorial: viewModel.equatorial, isActive: isActive
                    ) { _ in failed = true }
                }
                GardenConstellationLines(connections: shownConnections,
                    positions: Dictionary(uniqueKeysWithValues: shownPlaced.compactMap { object in
                        guard object.isAboveHorizon,
                            let point = shown.project(object.direction, in: geometry.size)
                        else { return nil }
                        return (object.id, point)
                    }), isActive: isActive)
                labels(in: geometry.size, camera: shown)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        viewModel.drag(value.translation, in: geometry.size)
                        // A finger on the water trails through it while looking around.
                        if let p = waterPoint(at: value.location, in: geometry.size) { NightSeaWater.shared.trail(at: p) }
                    }
                    .onEnded { _ in
                        viewModel.dragStart = nil
                        NightSeaWater.shared.endTrail()
                    }
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
                SpatialTapGesture().onEnded { value in
                    if viewModel.tap(at: value.location, in: geometry.size) { return }
                    // Not a star: a tap on the water drops a stone where the finger's ray meets the surface.
                    if let p = waterPoint(at: value.location, in: geometry.size) { NightSeaWater.shared.tap(at: p) }
                })
        }
    }

    // MARK: Labels

    @ViewBuilder private func labels(in size: CGSize, camera: NightSeaCamera) -> some View {
        ForEach(viewModel.placed.filter(\.object.isAboveHorizon)) { entry in
            if let point = camera.project(entry.object.direction, in: size),
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
                .position(x: point.x, y: point.y + entry.object.radius * (entry.object.kind == .star ? 7 / 1.3 : 1) * 0.45 + 14)
                .accessibilityLabel("\(entry.item.star.title), collected \(entry.item.collectedDate)")
                .accessibilityHint("Shows details")
            }
        }
    }


    /// The Night Sea as the wormhole should show it (see GardenViewModel.wormholeScene).
    static func wormholeScene(model: HomeViewModel, newID: Int?, demo: WormholeDemo? = nil, location: ObserverLocation? = nil) -> WormholeScene {
        GardenViewModel.wormholeScene(model: model, newID: newID, demo: demo, location: location)
    }

    /// Where a screen point's view ray meets the water plane (horizon frame metres), if it's on the water.
    private func waterPoint(at point: CGPoint, in size: CGSize) -> SIMD2<Double>? {
        guard !usesCamera, handover == nil else { return nil }
        let camera = viewModel.camera
        let f = camera.focalLength(in: size), c = camera.center(in: size)
        let d = simd_normalize(camera.forward + ((point.x - c.x) / f) * camera.right + ((c.y - point.y) / f) * camera.up)
        return NightSeaWater.waterPoint(d)
    }

    // MARK: Handover

    /// While the card is open the wormhole holds the collected star at (0.5, sheetStarY) of the screen.
    /// Closing the card shrinks it into a point of light that arcs there; then the cover goes without its slide.
    private var flyHome: StarAlbumView.FlyHome? {
        guard handover != nil, !reduceMotion else { return nil }
        return .init(target: UnitPoint(x: 0.5, y: WormholeTimeline.sheetStarY)) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { albumRequest = nil }
            landing = (landing ?? 0) + 1
        }
    }

    @ViewBuilder private var landingBloom: some View {
        if let landing {
            GeometryReader { geometry in
                LandingBloom()
                    .id(landing)
                    .position(x: geometry.size.width * 0.5, y: geometry.size.height * WormholeTimeline.sheetStarY)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .task(id: landing) {
                try? await Task.sleep(for: .seconds(1.2))
                if self.landing == landing { self.landing = nil }
            }
        }
    }

    /// The card closed: line the garden's own camera up with the star view (no gyro offset, no zoom), so the
    /// blend back to gyro/drag has no jump.
    private func prepareRelease() {
        guard let handover else { return }
        if viewModel.camera.orientation != nil {
            viewModel.camera.zoom = 1
        } else {
            let forward = handover.restingCamera.forward
            viewModel.camera.azimuth = atan2(forward.x, forward.y)
            viewModel.camera.altitude = min(88 * .pi / 180, max(-35 * .pi / 180, asin(min(1, max(-1, forward.z)))))
            viewModel.camera.fieldOfView = WormholeTimeline.landingFieldOfView
        }
    }

    private func endDemo() {
        guard viewModel.demo != nil else { return }
        viewModel.demo = nil
        viewModel.place()
        onDemoEnded()
    }
}

/// One request to show the collected object's album (a new value every time).
struct GardenSheetRequest: Equatable, Identifiable {
    let id = UUID()
    let itemID: Int
    /// Debug replay: an in-memory object that isn't in the collection.
    var demoItem: GardenCollectionItem? = nil
    /// Photo to show in the album (the demo's frozen frame; real captures use their saved photo).
    var photo: UIImage? = nil
    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
}

#Preview("Garden sky") {
    GardenSkyView(model: AppPreviewData.collectedModel, camera: .constant(NightSeaCamera()))
        .preferredColorScheme(.dark)
}
