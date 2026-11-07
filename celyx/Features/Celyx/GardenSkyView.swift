import SwiftUI
import AVFoundation

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
    /// Wormhole handover from the collect camera: drives the view during landing + reframe.
    var handover: WormholeHandover?
    /// Shows a collected object's sheet with a spring (after a handover or the Reduce Motion fade).
    var sheetRequest: GardenSheetRequest?
    /// Called when the demo object's sheet closes (debug replay).
    var onDemoEnded: () -> Void = {}

    struct Placed: Identifiable {
        let item: GardenCollectionItem
        let object: NightSeaObject
        var id: Int { item.id }
    }

    @State private var placed: [Placed] = []
    @State private var moon: (direction: SIMD3<Double>, illumination: Double)?
    @State private var equatorial: simd_double3x3?
    @State private var gpsLocation: ObserverLocation?
    /// Created once when the garden starts (not on every view update).
    @State private var motion: MotionService?
    @State private var gyroLive = false
    @State private var gyroMessage: String?
    @State private var offset = (azimuth: 0.0, altitude: 0.0)
    @State private var dragStart: (azimuth: Double, altitude: Double)?
    @State private var zoomStart: Double?
    @State private var selected: GardenCollectionItem?
    @State private var failed = false
    /// Debug replay: the demo object stays in the sky until its sheet closes (never saved).
    @State private var demo: WormholeDemo?
    /// Decorative background star field (not tappable, no labels).
    @State private var background: [NightSeaObject] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let fallbackLocation = ObserverLocation(latitude:-6.2,longitude:106.85,isManual:true)   // Jakarta
    private var location: ObserverLocation { gpsLocation ?? model.location ?? Self.fallbackLocation }

    var body: some View {
        Group {
            if usesCamera {
                GardenCameraLayer(placed:placed,selectedID:selected?.id,isActive:isActive) { selected = $0 }
                    .transition(.opacity)
            } else {
                virtualGarden.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration:0.35),value:usesCamera)
        .overlay(alignment:.bottom) {
            if let gyroMessage, isActive, !usesCamera {
                Text(gyroMessage).font(.system(size:12,weight:.medium)).foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal,14).padding(.vertical,8)
                    .glassEffect(.regular,in:Capsule())
                    .padding(.horizontal,32).padding(.bottom,110)
                    .allowsHitTesting(false)
            }
        }
        // Real positions: recomputed every second from GPS + clock (the sky turns ~0.25° a minute).
        .task(id:isActive) {
            guard isActive else { return }
            while !Task.isCancelled {
                place()
                try? await Task.sleep(for:.seconds(1))
            }
        }
        .onChange(of:model.collectionItems.count) { old, new in
            place()
            // Something new: without gyro, turn to face it.
            if new > old, camera.orientation == nil, let latest = placed.first(where:{ $0.id == model.collectionItems.first?.id }) {
                camera.azimuth = atan2(latest.object.direction.x,latest.object.direction.y)
            }
        }
        // The camera mode orients itself with ARKit; the gyro only drives the virtual garden.
        .onChange(of:isActive && !usesCamera,initial:true) { _, active in active ? startGyro() : stopGyro() }
        .onChange(of:resetRequest) { _, _ in
            offset = (0,0)
            if camera.orientation == nil { camera.azimuth = 0; camera.altitude = 18 * .pi/180 }
            camera.fieldOfView = 72
            camera.zoom = 1
        }
        .onDisappear(perform:stopGyro)
        .onChange(of:handover?.phase) { _, phase in
            if phase == .landed, let next = handover?.demo { demo = next; place() }
            if phase == .releasing { prepareRelease() }
        }
        .onChange(of:sheetRequest) { _, request in
            guard let request, let item = model.collectionItems.first(where:{ $0.id == request.itemID }) ?? request.demoItem else { return }
            selected = item   // Sendi's native card (springs in with the system sheet)
        }
        .sheet(item:$selected,onDismiss:{ endDemo(); handover?.beginRelease() }) { item in
            CollectedObjectSheet(item:item,direction:placed.first(where:{ $0.id == item.id })?.object.direction) {
                model.deleteCollected(id:item.id)
                selected = nil
            }
        }
        .accessibilityElement(children:.contain)
        .accessibilityLabel("Your garden sky")
    }

    /// The camera actually rendered: the handover's while it lands and reframes, then the garden's own.
    private func viewCamera(_ now: Date) -> NightSeaCamera {
        guard let handover, handover.phase >= .landed, handover.phase < .done else { return camera }
        handover.target = handover.phase >= .releasing ? camera : nil
        return handover.camera(handover.tt())
    }

    private var virtualGarden: some View {
        TimelineView(.animation(paused:handover == nil || handover?.phase == .done)) { context in
            virtualGarden(shown:viewCamera(context.date))
        }
    }

    private func virtualGarden(shown: NightSeaCamera) -> some View {
        GeometryReader { geometry in
            ZStack {
                if failed {
                    Image("celyx-home-sky").resizable().scaledToFill()
                        .frame(width:geometry.size.width,height:geometry.size.height,alignment:.trailing)
                        .clipped()
                } else {
                    NightSeaView(camera:shown,objects:background+placed.map(\.object),selectedID:selected?.id,moon:moon,
                                 equatorial:equatorial,isActive:isActive) { _ in failed = true }
                }
                labels(in:geometry.size,camera:shown)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance:2)
                .onChanged { value in drag(value.translation,in:geometry.size) }
                .onEnded { _ in dragStart = nil })
            .simultaneousGesture(MagnifyGesture()
                .onChanged { value in
                    if camera.orientation != nil {
                        if zoomStart == nil { zoomStart = camera.zoom }
                        camera.zoom = min(4,max(0.5,(zoomStart ?? 1)*value.magnification))
                    } else {
                        if zoomStart == nil { zoomStart = camera.fieldOfView }
                        camera.fieldOfView = min(110,max(24,(zoomStart ?? 72)/value.magnification))
                    }
                }
                .onEnded { _ in zoomStart = nil })
            .simultaneousGesture(SpatialTapGesture().onEnded { value in tap(at:value.location,in:geometry.size) })
        }
    }

    // MARK: Labels

    @ViewBuilder private func labels(in size: CGSize,camera: NightSeaCamera) -> some View {
        ForEach(placed.filter(\.object.isAboveHorizon)) { entry in
            if let point = camera.project(entry.object.direction,in:size),
               point.x > -40, point.x < size.width+40, point.y > -40, point.y < size.height+40 {
                Button { selected = entry.item } label: {
                    Text(entry.item.star.title)
                        .font(.system(size:12,weight:.medium)).foregroundStyle(.white.opacity(0.85))
                        .shadow(color:.black.opacity(0.7),radius:3)
                        .padding(.horizontal,8).padding(.vertical,6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(x:point.x,y:point.y+entry.object.radius*0.45+14)
                .accessibilityLabel("\(entry.item.star.title), collected \(entry.item.collectedDate)")
                .accessibilityHint("Shows details")
            }
        }
    }

    // MARK: Placement

    private func place() {
        let scene = Self.placement(items:model.collectionItems,location:location,catalogue:model.stars,
                                   excluding:demo.map { [$0.item.id] } ?? [])
        background = scene.background
        placed = scene.placed
        if let demo, !placed.contains(where:{ $0.id == demo.item.id }) {
            placed.append(Placed(item:demo.item,object:demo.object))
        }
        moon = scene.moon
        equatorial = scene.equatorial
    }

    /// Every collected object at its real (refracted) position for this place and time.
    static func placement(items: [GardenCollectionItem],location: ObserverLocation,date: Date = Date(),
                          catalogue: [CatalogStar] = [],excluding extra: Set<Int> = [])
        -> (placed: [Placed], moon: (direction: SIMD3<Double>, illumination: Double)?, equatorial: simd_double3x3,
            background: [NightSeaObject]) {
        let sky = AstronomyService.snapshot(date:date,location:location)
        var result: [Placed] = []
        var moonState: (direction: SIMD3<Double>, illumination: Double)?
        for item in items {
            let star = item.star
            let geometric: SIMD3<Double>
            let kind: NightSeaObject.Kind
            let radius: Double
            let color: SIMD3<Double>
            if star.isSun {
                geometric = sky.sunDirection; kind = .sun; radius = 46; color = SIMD3(1,0.82,0.52)
            } else if star.isMoon {
                geometric = sky.moonDirection; kind = .moon; radius = 38; color = SIMD3(0.88,0.91,1)
                moonState = (Refraction.apparent(geometric),sky.moonIllumination)
            } else if star.isPlanet {
                guard let planet = sky.planets.first(where:{ $0.star.id == star.id }) else { continue }
                geometric = planet.direction; kind = .planet
                radius = min(5.2,max(2,3.4-0.5*planet.star.mag))*6; color = star.rgb
            } else {
                geometric = sky.direction(ra:star.ra_deg,dec:star.dec_deg); kind = .star
                radius = NightSeaObject.starRadius(magnitude:star.mag)*1.3; color = star.rgb
            }
            result.append(Placed(item:item,object:NightSeaObject(id:star.id,direction:Refraction.apparent(geometric),
                                                                 radius:radius,color:color,kind:kind)))
        }
        // Decorative star field (the kit's HYG layer to mag 6.2), toned down in the shader so it never reads as a
        // collected star: smaller, dimmer, no spikes, glow only for the very brightest, faint dust beyond mag 5.
        let collected = Set(items.map(\.star.id)).union(extra)
        let background = catalogue.lazy.filter { $0.mag <= Self.backgroundLimit && !collected.contains($0.id) && !$0.isSolarSystemBody }
            .compactMap { star -> NightSeaObject? in
                let direction = Refraction.apparent(sky.direction(ra:star.ra_deg,dec:star.dec_deg))
                guard direction.z > -0.01 else { return nil }
                return NightSeaObject(id:-star.id-1,direction:direction,radius:star.mag,color:star.rgb,kind:.background)
            }
        return (result,moonState,sky.basis,Array(background))
    }
    static let backgroundLimit = 6.2

    /// The Night Sea as the wormhole should show it.
    static func wormholeScene(model: HomeViewModel,newID: Int?,demo: WormholeDemo? = nil) -> WormholeScene {
        let scene = placement(items:model.collectionItems,location:model.location ?? fallbackLocation,catalogue:model.stars,
                              excluding:demo.map { [$0.object.id] } ?? [])
        var objects = scene.background+scene.placed.map(\.object)
        if let demo { objects.removeAll { $0.id == demo.object.id }; objects.append(demo.object) }
        return WormholeScene(objects:objects,newID:newID,moon:scene.moon,equatorial:scene.equatorial)
    }

    // MARK: Handover

    /// The card closed: line the garden's own camera up with the star view (no gyro offset, no zoom), so the
    /// 600 ms blend back to gyro/drag has no jump.
    private func prepareRelease() {
        guard let handover else { return }
        if camera.orientation != nil {
            offset = (0,0)
            camera.zoom = 1
        } else {
            let resting = handover.restingCamera
            let forward = resting.forward
            camera.azimuth = atan2(forward.x,forward.y)
            camera.altitude = min(88 * .pi/180,max(-35 * .pi/180,asin(min(1,max(-1,forward.z)))))
            camera.fieldOfView = WormholeTimeline.landingFieldOfView
        }
    }

    private func endDemo() {
        guard demo != nil else { return }
        demo = nil
        place()
        onDemoEnded()
    }

    // MARK: Gyro

    private func startGyro() {
        let service = motion ?? MotionService()
        motion = service
        camera.cameraFieldOfView = Self.backCameraFieldOfView
        service.onLocation = { fix in gpsLocation = fix; place() }
        service.onCalibration = { ready,_,message,stage in
            gyroLive = ready
            gyroMessage = ready || stage == .blocked ? nil : message
            if !ready { camera.orientation = nil }
        }
        service.start { _,_,_ in }
        service.onAttitude = { attitude in follow(attitude) }
    }
    private func stopGyro() {
        motion?.stop()
        gyroLive = false
        gyroMessage = nil
        camera.orientation = nil
    }
    /// Phone attitude -> camera orientation, plus the user's drag offset (turn left/right, tilt up/down).
    private func follow(_ attitude: simd_double3x3) {
        var sensor = simd_quatd(attitude)
        // Calibrated compass error (see SkyCalibration): turn the sensor's north to true north.
        let correction = SkyCalibration.motionHeadingOffset
        if correction != 0 { sensor = simd_quatd(angle:-correction,axis:SIMD3(0,0,1))*sensor }
        // A few degrees of extra upward tilt by default, so the horizon rests lower and the sky dominates.
        let tilt = offset.altitude+Self.restingTilt
        if offset.azimuth != 0 || tilt != 0 {
            let yaw = simd_quatd(angle:-offset.azimuth,axis:SIMD3(0,0,1))      // around the world's vertical
            let pitch = simd_quatd(angle:tilt,axis:SIMD3(1,0,0))               // around the phone's own right axis
            sensor = yaw*sensor*pitch
        }
        guard let current = camera.orientation, !reduceMotion else { camera.orientation = sensor; return }
        // Light smoothing against sensor jitter; still follows the phone within a few frames.
        camera.orientation = simd_slerp(current,sensor,0.45)
    }
    /// Default upward tilt of the gyro view (radians).
    private static let restingTilt = 4 * Double.pi/180
    /// Horizontal (long-side) field of view of the back wide camera, used for the 1:1 window.
    private static let backCameraFieldOfView: Double = {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,for:.video,position:.back) else { return 69 }
        let fov = Double(device.activeFormat.videoFieldOfView)
        return fov > 20 && fov < 130 ? fov : 69
    }()

    // MARK: Gestures

    private func drag(_ translation: CGSize,in size: CGSize) {
        if dragStart == nil {
            dragStart = camera.orientation != nil ? offset : (camera.azimuth,camera.altitude)
        }
        guard let start = dragStart else { return }
        // Degrees per point of the current view, so the sky follows the finger.
        let k = camera.orientation != nil ? 1/camera.focalLength(in:size) : camera.fieldOfView/Double(min(size.width,size.height))*1.15 * .pi/180
        let azimuth = start.azimuth-translation.width*k
        if camera.orientation != nil {
            offset = (atan2(sin(azimuth),cos(azimuth)),min(60 * .pi/180,max(-60 * .pi/180,start.altitude+translation.height*k)))
        } else {
            camera.azimuth = azimuth
            camera.altitude = min(88 * .pi/180,max(-35 * .pi/180,start.altitude+translation.height*k))
        }
    }
    private func tap(at point: CGPoint,in size: CGSize) {
        let hits = placed.compactMap { entry -> (Placed,CGFloat)? in
            guard entry.object.isAboveHorizon, let p = camera.project(entry.object.direction,in:size) else { return nil }
            let distance = hypot(p.x-point.x,p.y-point.y)
            return distance <= max(36,entry.object.radius*0.6) ? (entry,distance) : nil
        }
        if let hit = hits.min(by:{ $0.1 < $1.1 }) { selected = hit.0.item }
    }
}

/// One request to spring in the collected object's sheet (a new value every time).
struct GardenSheetRequest: Equatable {
    let id = UUID()
    let itemID: Int
    /// Debug replay: an in-memory object that isn't in the collection.
    var demoItem: GardenCollectionItem? = nil
    static func == (a: Self,b: Self) -> Bool { a.id == b.id }
}

#Preview("Garden sky") {
    GardenSkyView(model:AppPreviewData.collectedModel,camera:.constant(NightSeaCamera()))
        .preferredColorScheme(.dark)
}
