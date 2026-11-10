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
        ZStack {
            if usesCamera {
                GardenCameraLayer(
                    placed: viewModel.placed, selectedID: viewModel.selected?.id,
                    connections: shownConnections, zodiacFigures: shownZodiacFigures,
                    equatorial: viewModel.equatorial, isActive: isActive,
                    onCameraUpdate: handover == nil ? nil : { pose in handover?.liveCamera = pose }
                ) { viewModel.selected = $0 }
                .opacity(showsCaptureSequence ? 0 : 1)
                .allowsHitTesting(!showsCaptureSequence)
            }
            if !usesCamera || showsCaptureSequence {
                virtualGarden.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: usesCamera)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: showsCaptureSequence)
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
        .onChange(of: isActive && (!usesCamera || showsCaptureSequence), initial: true) { _, active in
            active ? viewModel.startGyro(usesGyro: usesGyro) : viewModel.stopGyro()
        }
        .onChange(of: usesGyro) { _, _ in
            if isActive && (!usesCamera || showsCaptureSequence) { viewModel.setGyroMode(usesGyro) }
        }
        .onChange(of: viewModel.usesGyro) { _, enabled in onModeChange?(enabled) }
        .onChange(of: resetRequest) { _, _ in viewModel.resetCamera() }
        .onChange(of: viewModel.camera) { _, value in if camera != value { camera = value } }
        .onChange(of: camera) { _, value in if viewModel.camera != value { viewModel.camera = value } }
        .onChange(of: reduceMotion, initial: true) { _, value in viewModel.reduceMotion = value }
        .onDisappear(perform: viewModel.stopGyro)
        .onChange(of: handover?.phase, initial: true) { _, phase in
            if phase == .landed, let next = handover?.demo {
                viewModel.demo = next
                viewModel.place()
            }
            if phase == .landed, let handover {
                viewModel.place()
                let id = handover.itemID
                let completed = viewModel.completedZodiacFigures.first { $0.requiredStarIDs.contains(id ?? Int.min) }
                let edges = viewModel.constellationConnections.filter { $0.startID == id || $0.endID == id }
                var ids = completed?.requiredStarIDs ?? Set(edges.flatMap { [$0.startID, $0.endID] })
                if let id { ids.insert(id) }
                handover.configureFocus(directions: handover.scene.objects.filter { ids.contains($0.id) }.map(\.direction))
            }
        }
        // The handover requests the album only after the reveal and return to live tracking.
        .onChange(of: sheetRequest) { _, request in
            guard let request,
                model.collectionItems.contains(where: { $0.id == request.itemID }) || request.demoItem != nil
            else { return }
            albumRequest = request
        }
        .fullScreenCover(item: $albumRequest, onDismiss: { endDemo(); handover?.finish() }) { request in
            if let item = model.collectionItems.first(where: { $0.id == request.itemID }) {
                StarAlbumView(
                    item: item, photo: request.photo,
                    onSaveNote: { model.updateObservationNote(id: item.id, note: $0) },
                    onSavePlace: { model.updateObservationPlace(id: item.id, name: $0) },
                    flyHome: nil)
            } else if let demo = request.demoItem {
                // Demo: never saved.
                StarAlbumView(item: demo, photo: request.photo, onSaveNote: { _ in }, onSavePlace: { _ in }, flyHome: nil)
            }
        }
        .overlay {
            // The collected star finishing its flight into place after the hand-off from the camera.
            if let handover, !reduceMotion, handover.phase < .focusing { LandingStarFlight(handover: handover).ignoresSafeArea() }
        }
        .sheet(item: $viewModel.selected) { item in
            CollectedObjectSheet(
                item: item,
                direction: viewModel.placed.first(where: { $0.id == item.id })?.object.direction,
                collection: model,
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

    private var showsCaptureSequence: Bool {
        handover != nil && handover!.phase < .presenting && !reduceMotion
    }

    /// Collected objects to draw; the one just collected waits until its flight lands (LandingStarFlight).
    private var shownPlaced: [NightSeaObject] {
        let objects = viewModel.placed.map(\.object)
        guard let handover, let id = handover.scene.newID, handover.phase < .releasing,
            handover.tt() < handover.landing + WormholeTimeline.flyEnd
        else { return objects }
        return objects.filter { $0.id != id }
    }

    /// Reveal newly collected threads only after placement and focus settle.
    private var shownConnections: [GardenConstellationConnection] {
        guard let handover, !handover.revealIsVisible, let id = handover.itemID else {
            return viewModel.constellationConnections
        }
        return viewModel.constellationConnections.filter { $0.startID != id && $0.endID != id }
    }

    private var shownZodiacFigures: [GardenZodiacFigure] {
        guard let handover, !handover.revealIsVisible, let id = handover.itemID else {
            return viewModel.completedZodiacFigures
        }
        return viewModel.completedZodiacFigures.filter { !$0.requiredStarIDs.contains(id) }
    }

    /// The camera actually rendered: the handover's while it lands and reframes, then the garden's own.
    private func viewCamera() -> NightSeaCamera {
        guard let handover, handover.phase >= .landed, handover.phase < .presenting, !reduceMotion else { return viewModel.camera }
        handover.target = handover.phase >= .releasing ? (usesCamera ? handover.liveCamera ?? viewModel.camera : viewModel.camera) : nil
        return handover.camera(handover.tt())
    }

    private var virtualGarden: some View {
        TimelineView(.animation(paused: handover == nil || (handover?.phase ?? .done) >= .presenting)) { _ in
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
                GardenZodiacFigures(unlocked: shownZodiacFigures,
                    projected: GardenZodiacFigure.project(shownZodiacFigures, basis: viewModel.equatorial,
                        size: geometry.size, point: { shown.project($0, in: geometry.size) }),
                    skyClip: GardenZodiacFigure.skyClip(size: geometry.size) { point in
                        let center = shown.center(in: geometry.size)
                        let focal = shown.focalLength(in: geometry.size)
                        return shown.forward.z + Double(point.x - center.x) / focal * shown.right.z
                            + Double(center.y - point.y) / focal * shown.up.z
                    }, isActive: isActive)
                GardenConstellationLines(connections: shownConnections,
                    positions: Dictionary(uniqueKeysWithValues: shownPlaced.compactMap { object in
                        guard object.isAboveHorizon,
                            let point = shown.project(object.direction, in: geometry.size)
                        else { return nil }
                        return (object.id, point)
                    }), isActive: isActive)
                labels(in: geometry.size, camera: shown)
            }
            .allowsHitTesting(handover == nil || handover!.phase >= .presenting)
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
