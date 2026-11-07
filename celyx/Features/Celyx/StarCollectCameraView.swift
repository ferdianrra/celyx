import SwiftUI
import ARKit

/// Real star collecting, styled like Figma "Camera Stand by" / "Camera Scanned" / "Camera Captured".
///
/// `SkyFinderService` does the work: GPS + true-north camera orientation (ARKit) project the HYG catalogue
/// onto the live camera image, and `CameraStarDetector` looks for an actual point of light at that spot.
/// The crosshair never moves: only what sits inside the centre circle is scanned. A target must be
/// really visible from this place right now (no stars in daylight, only the Sun). Pressing Collect starts
/// a short check: the crosshair spins green while we confirm the camera really sees that light in the
/// circle, and only then is it saved to the garden.
struct StarCollectCameraView: View {
    /// What sits inside the centre circle right now.
    struct CenterTarget {
        let star: CatalogStar
        /// The actual point of light the camera sees there. Required to collect.
        let detection: CameraStarAnnotation?
        var id: Int { star.id }
    }

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
    /// When set, a successful collect hands over to the garden instead of staying here.
    var onCollect: ((CollectResult) -> Void)? = nil
    @State private var service: SkyFinderService
    @State private var viewSize: CGSize = .zero
    @State private var settledID: Int?
    /// Last settled target, kept briefly so a single missed frame doesn't close the sheet.
    @State private var lastShown: CenterTarget?
    @State private var errorMessage: String?
    @State private var zoomStart: Double?
    @State private var verification: Verification = .idle
    @State private var showsCalibration = false
    @State private var showsFilteredStars = false
    /// True while something sits in the circle and we're locking on to it.
    @State private var isLocking = false
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Verification: Equatable { case idle, checking(Int), failed(Int) }
    /// Crosshair radius plus a little slack for hand shake.
    private let captureRadius: CGFloat = 28
    private var isChecking: Bool { if case .checking = verification { true } else { false } }

    init(model: HomeViewModel,handover: WormholeHandover? = nil,onCollect: ((CollectResult) -> Void)? = nil,onClose: @escaping () -> Void) {
        self.model = model
        self.handover = handover
        self.onCollect = onCollect
        self.onClose = onClose
        _service = State(initialValue:SkyFinderService(location:model.location,catalogue:model.stars,alignment:model.cameraAlignment))
    }

    private var center: CGPoint { CGPoint(x:viewSize.width/2,y:viewSize.height/2) }
    private func distance(_ point: CGPoint) -> CGFloat { hypot(point.x-center.x,point.y-center.y) }

    /// Only objects that are really visible from this GPS position at this moment can be targeted:
    /// `viewableObjects` already accounts for the Sun's altitude (no stars by day), the Moon,
    /// light pollution and clouds. A light the camera actually sees at the centre wins over a mapped position.
    private var centerTarget: CenterTarget? {
        guard service.status == .tracking, !service.isAdjustingCamera, viewSize != .zero else { return nil }
        let visible = Set(service.viewableObjects.map(\.id))
        if let seen = service.annotations
            .filter({ visible.contains($0.id) && distance($0.point) <= captureRadius })
            .min(by:{ distance($0.point) < distance($1.point) }) {
            return CenterTarget(star:seen.star,detection:seen)
        }
        // Sun, Moon and planets: judged by angle, tolerant to the phone compass error.
        // The Collect check then demands the real bright light inside the circle.
        let tolerance = min(25,max(10,(service.cameraHeadingAccuracy ?? 15)+5))
        if let body = service.brightBodiesNearAim()
            .filter({ visible.contains($0.star.id) && $0.separation <= tolerance })
            .min(by:{ $0.separation < $1.separation }) {
            return CenterTarget(star:body.star,detection:nil)
        }
        return service.mappedObjects
            .filter { $0.likelyVisible && distance($0.point) <= captureRadius }
            .min(by:{ distance($0.point) < distance($1.point) })
            .map { CenterTarget(star:$0.star,detection:nil) }
    }
    /// A catalogue object in the circle that can't actually be seen now (daylight, too faint…).
    private var hiddenAtCenter: CatalogStar? {
        guard service.status == .tracking, viewSize != .zero else { return nil }
        return service.mappedObjects
            .filter { !$0.likelyVisible && distance($0.point) <= captureRadius }
            .min(by:{ distance($0.point) < distance($1.point) })?.star
    }
    private var shownTarget: CenterTarget? {
        if let target = centerTarget, settledID == target.id { return target }
        return settledID == nil ? nil : lastShown
    }

    var body: some View {
        TimelineView(.animation(paused:handover == nil)) { _ in
            let frame = handover.map { $0.frame($0.tt()) }
            content(cameraUI:frame?.cameraUI ?? 1,crosshair:frame?.crossAlpha ?? 1)
        }
    }

    private func content(cameraUI: Double,crosshair: Double) -> some View {
        ZStack(alignment:.bottom) {
            GeometryReader { geometry in
                ZStack {
                    if service.isCameraRunning {
                        SkyCameraPreview(session:service.session,onViewport:service.updateViewport,zoom:service.cameraZoom)
                            .simultaneousGesture(MagnifyGesture()
                                .onChanged { value in
                                    if zoomStart == nil { zoomStart = service.cameraZoom }
                                    service.setZoom((zoomStart ?? 1)*value.magnification)
                                }
                                .onEnded { _ in zoomStart = nil })
                    } else {
                        CelyxColor.night
                    }
                    if let handover { WormholeHandoverView(handover:handover) }
                    // CrosshairView's reticle sits 10pt above its own centre (see crosshair README).
                    reticle.position(x:geometry.size.width/2,y:geometry.size.height/2+10)
                        .opacity(crosshair)
                }
                .onAppear { viewSize = geometry.size }
                .onChange(of:geometry.size) { _, size in viewSize = size }
            }
            .ignoresSafeArea()

            VStack {
                HStack {
                    CelyxBackButton { service.stop(); onClose() }
                    Spacer()
                    CelyxGlassButton(width:148,action:{ service.stop(); showsFilteredStars = true }) {
                        Label("Filtered Stars",systemImage:"list.star")
                            .font(.system(size:14,weight:.semibold)).foregroundStyle(CelyxColor.primaryLabel)
                    }
                    CelyxGlassButton(action:{ service.stop(); showsCalibration = true }) {
                        Image(systemName:"scope").font(.system(size:20)).foregroundStyle(.white)
                    }
                    .accessibilityLabel("Calibrate direction")
                }
                .padding(.horizontal,20)
                Spacer()
            }
            .opacity(cameraUI)

            if let target = shownTarget {
                sheet(for:target)
                    .padding(.horizontal,6).padding(.bottom,6)
                    .ignoresSafeArea(edges:.bottom)
                    .transition(.move(edge:.bottom).combined(with:.opacity))
                    .opacity(cameraUI)
            } else {
                CelyxHintPill(text:hintText).padding(.bottom,59).transition(.opacity)
                    .opacity(cameraUI)
            }
        }
        .allowsHitTesting(handover == nil)
        .background(CelyxColor.night)
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .spring(duration:0.35),value:shownTarget?.id)
        .task {
            if onCollect != nil { WormholeFeedback.shared.prepare() }
            service.updateVisibility(quality:model.quality,atmosphere:model.atmosphere)
            await service.start()
        }
        .onDisappear { service.stop() }
        .onChange(of:phase) { _, value in
            if value == .active, !showsCalibration, !showsFilteredStars { Task { await service.start() } } else { service.stop() }
        }
        .onChange(of:centerTarget?.detection != nil) { _, _ in
            if let target = centerTarget, target.id == settledID { lastShown = target }
        }
        // Settle briefly so the sheet doesn't flicker while sweeping across the sky.
        .task(id:centerTarget?.id) {
            guard let target = centerTarget else {
                try? await Task.sleep(for:.milliseconds(800))
                guard !Task.isCancelled else { return }
                settledID = nil; lastShown = nil
                return
            }
            if settledID == target.id { return }
            // Lock on: the crosshair's loader runs while the object stays in the circle.
            isLocking = true
            try? await Task.sleep(for:.seconds(Self.lockDuration))
            guard !Task.isCancelled else { isLocking = false; return }
            isLocking = false
            settledID = target.id
            lastShown = target
        }
        .fullScreenCover(isPresented:$showsCalibration,onDismiss:{ Task { await service.start() } }) {
            SkyCalibrationView(catalogue:model.stars,alignment:model.cameraAlignment) { showsCalibration = false }
        }
        .fullScreenCover(isPresented:$showsFilteredStars,onDismiss:{ Task { await service.start() } }) {
            FilteredStarsView(model:model)
        }
        .alert("Couldn’t collect that",isPresented:Binding(get:{ errorMessage != nil },set:{ if !$0 { errorMessage = nil } })) {
            Button("Try Again",role:.cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Crosshair (always fixed at the centre of the screen)

    private static let lockDuration = 0.9
    private static let verifyDuration = 1.6

    /// Figma "Crosshair" component (node 922:1567) with its own motion, sound and haptics.
    private var reticle: some View {
        CrosshairView(state:crosshairState,label:(shownTarget ?? (isLocking ? centerTarget : nil))?.star.title ?? "")
        #if DEBUG
            // Debug: long-press the crosshair to replay the wormhole indoors (fake success at the centre).
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration:0.6) { replayHandover() }
        #endif
    }
    private var crosshairState: CrosshairState {
        if isChecking { return .validating }
        if shownTarget != nil { return .enable }
        if isLocking { return .locking }
        return .default
    }

    private var hintText: String {
        switch service.status {
        case .tracking: break
        case .preparing: return "Finding your place under the sky…"
        case .requestingPermission: return "Allow camera and location to find stars"
        case .limited(let message), .unavailable(let message), .denied(let message): return message
        }
        let sun = service.sunAltitude ?? -90
        if let hidden = hiddenAtCenter {
            if sun >= -0.833 { return "It’s daytime, so \(hidden.title) can’t be seen now" }
            if sun >= -6 { return "The sky is still too bright to see \(hidden.title)" }
            return "\(hidden.title) is too faint to see from here now"
        }
        if sun >= -0.833 { return "It’s daytime. Only the Sun can be collected now" }
        if sun >= -6 { return "The sky is still too bright for stars" }
        return "Point your circle at a star"
    }

    // MARK: Sheet

    private func sheet(for target: CenterTarget) -> some View {
        let star = target.star
        let isCollected = model.collected[star.id] != nil
        let checking = verification == .checking(star.id)
        let failed = verification == .failed(star.id)
        return ZStack(alignment:.top) {
            CelyxBluePanel(cornerRadius:34)
            CelyxGrabber()
            VStack(spacing:0) {
                HStack(spacing:0) {
                    StarPortraitView(star:star)
                        .frame(width:64,height:64)
                        .shadow(color:Color(red:star.rgb.x,green:star.rgb.y,blue:star.rgb.z).opacity(0.8),radius:10)
                        .accessibilityHidden(true)
                    VStack(alignment:.leading,spacing:0) {
                        Text(star.title).font(.system(size:28,weight:.bold)).tracking(0.38).foregroundStyle(CelyxColor.primaryLabel)
                            .lineLimit(1).minimumScaleFactor(0.6).frame(height:34)
                        Text(subtitle(for:star)).font(.system(size:15,weight:.medium)).tracking(-0.23).foregroundStyle(CelyxColor.subtitle).frame(height:20)
                    }
                    .padding(.horizontal,16)
                    Spacer(minLength:0)
                    CelyxCloseButton { verification = .idle; settledID = nil; lastShown = nil }
                }
                .padding(.horizontal,16).frame(height:64).padding(.top,24).padding(.bottom,8)
                HStack(spacing:6) {
                    let color = failed ? Color.orange : CelyxColor.ready
                    Circle().fill(color).frame(width:6,height:6).shadow(color:color,radius:3)
                    Text("\(Text(statusText(for:star,checking:checking,failed:failed,collected:isCollected)).foregroundStyle(CelyxColor.primaryLabel))\(Text(directionText(for:star)).foregroundStyle(CelyxColor.secondaryLabel))")
                        .font(.system(size:12)).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength:0)
                }
                .frame(height:16).padding(16)
                Group {
                    if isCollected {
                        CelyxPillButton(title:"Collected",systemImage:"checkmark",style:.collected) {}
                            .allowsHitTesting(false)
                    } else {
                        CelyxPillButton(title:checking ? "Checking the sky…" : star.isSun ? "Collect the Sun" : "Collect this star",
                                        style:checking ? .disabled : .primary) { collect(target) }
                    }
                }
                .padding(.horizontal,16)
            }
        }
        .frame(height:228)
    }

    private func statusText(for star: CatalogStar,checking: Bool,failed: Bool,collected: Bool) -> String {
        if collected { return "In your garden · " }
        if checking { return "Hold steady, checking its light · " }
        if failed { return "Couldn’t see it in the circle. Try again · " }
        if star.isSun { return "Visible now · Never look straight at it · " }
        return "Visible now · "
    }
    private func subtitle(for star: CatalogStar) -> String {
        if star.isSolarSystemBody { return star.kind }
        if let code = star.con, let name = ConstellationNames.name(for:code) { return "Star in \(name)" }
        return "Star"
    }
    /// e.g. "High in the west", from the object's real altitude/azimuth at this place and time.
    private func directionText(for star: CatalogStar) -> String {
        guard let observation = service.viewableObjects.first(where:{ $0.id == star.id }) else { return "In your view" }
        let points = ["north","northeast","east","southeast","south","southwest","west","northwest"]
        let bearing = points[Int((observation.azimuth+22.5)/45) % 8]
        let height = observation.altitude >= 50 ? "High" : observation.altitude >= 20 ? "Up" : "Low"
        return "\(height) in the \(bearing)"
    }

    // MARK: Actions

    /// Starts the check. Collecting only succeeds if, over ~1–2.5s, the same object stays in the circle
    /// AND the camera actually sees its light there (a detected star, or a real bright source in the frame).
    private func collect(_ target: CenterTarget) {
        guard !isChecking else { return }
        let id = target.id
        verification = .checking(id)
        Task { @MainActor in
            let start = Date()
            var confirmations = 0
            while Date().timeIntervalSince(start) < 2.5 {
                guard verification == .checking(id) else { return }
                if let current = centerTarget, current.id == id,
                   current.detection != nil || lightIsInCircle(for:current.star) {
                    confirmations += 1
                    // Several consecutive confirmations, and let the spinner read as a real check.
                    if confirmations >= 4 && Date().timeIntervalSince(start) >= Self.verifyDuration {
                        save(current)
                        return
                    }
                } else {
                    confirmations = 0
                }
                try? await Task.sleep(for:.milliseconds(150))
            }
            if verification == .checking(id) { fail(id) }
        }
    }

    /// Soft "not this time" cue (sound + two dull taps) instead of the harsh system error buzz,
    /// and mute the crosshair's automatic "back" sound so the two don't stack.
    private func fail(_ id: Int) {
        CrosshairFeedback.shared.suppress(.back,for:0.6)
        CrosshairFeedback.shared.play(CrosshairSound.fail)
        CrosshairFeedback.shared.play(CrosshairHaptic.fail)
        verification = .failed(id)
    }

    private func save(_ target: CenterTarget) {
        // The confirmed light: a detected source, or the bright source we just measured at the centre.
        let annotation = target.detection ?? CameraStarAnnotation(star:target.star,point:center,size:CGSize(width:28,height:28))
        let note = target.detection?.estimatedSeparation.map {
            String(format:"Our best match is %@, based on direction and brightness. Direction offset: %.1f°.",target.star.title,$0)
        } ?? "Confirmed by direction, time and place, with a bright light seen in the circle."
        guard let draft = service.captureObservation(annotation:annotation,identificationNote:note) else {
            fail(target.id)
            return
        }
        do {
            try model.saveCameraObservation(draft,note:"")
            verification = .idle
            if onCollect != nil && !reduceMotion {
                beginHandover(itemID:target.star.id,point:target.detection?.point ?? center)
                return
            }
            // Celebrate: our own chime + haptic, and mute the crosshair's automatic "back" on the way to Enable.
            CrosshairFeedback.shared.suppress(.back,for:0.6)
            CrosshairFeedback.shared.play(CrosshairSound.collect)
            CrosshairFeedback.shared.play(CrosshairHaptic.collect)
            onCollect?(.fade(itemID:target.star.id))
        } catch {
            verification = .idle
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Wormhole handover

    /// Freezes the camera frame and opens the wormhole at the collected star's screen point.
    private func beginHandover(itemID: Int?,point: CGPoint,demoStar: CatalogStar? = nil) {
        guard handover == nil, let onCollect, viewSize != .zero else { return }
        let freeze = service.wormholeFreeze() ?? .placeholder(size:viewSize)
        let demo = demoStar.map { WormholeDemo.make(star:$0,freeze:freeze,location:model.location) }
        let id = demo?.item.id ?? itemID
        let handover = WormholeHandover(freeze:freeze,star:point,itemID:id,
                                        scene:GardenSkyView.wormholeScene(model:model,newID:id,demo:demo),demo:demo)
        // The crosshair fades out; keep its own state-change sounds out of the score.
        CrosshairFeedback.shared.suppress(.back,for:1.2)
        CrosshairFeedback.shared.suppress(.release,for:1.2)
        WormholeFeedback.shared.play(landing:handover.landing)
        onCollect(.wormhole(handover))
    }

    #if DEBUG
    /// Fake success on a fixed point (the screen centre) with Rigel as an in-memory demo star (never saved),
    /// so it lights up at landing and its sheet springs in, even with an empty collection.
    private func replayHandover() {
        guard onCollect != nil, !isChecking else { return }
        if reduceMotion { onCollect?(.fade(itemID:model.collectionItems.first?.id)); return }
        let rigel = model.stars.first { $0.name == "Rigel" || $0.title == "Rigel" }
        beginHandover(itemID:model.collectionItems.first?.id,point:center,demoStar:rigel)
    }
    #endif

    /// Reads the live camera frame: is there really a light inside the circle?
    private func lightIsInCircle(for star: CatalogStar) -> Bool {
        guard let buffer = service.session.currentFrame?.capturedImage, viewSize != .zero,
              let sample = CenterLightProbe.measure(buffer,viewSize:viewSize,radius:captureRadius) else { return false }
        if star.isSun {
            // A saturated disc filling a good part of the circle.
            return sample.peak >= 245 && sample.saturatedFraction >= 0.10
        }
        // A point or disc clearly brighter than the sky right around it.
        return sample.peak >= 60 && sample.peak-sample.surroundingMedian >= 35
    }
}

/// Measures brightness in the centre of a camera frame (luma plane), mapped from the on-screen circle.
nonisolated enum CenterLightProbe {
    struct Sample { let peak: Double; let saturatedFraction: Double; let surroundingMedian: Double }

    static func measure(_ buffer: CVPixelBuffer,viewSize: CGSize,radius: CGFloat) -> Sample? {
        guard CVPixelBufferGetPlaneCount(buffer) >= 1 else { return nil }
        CVPixelBufferLockBaseAddress(buffer,.readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer,.readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer,0) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(buffer,0), height = CVPixelBufferGetHeightOfPlane(buffer,0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer,0)
        let pixels = base.assumingMemoryBound(to:UInt8.self)
        // The preview is aspect-filled and rotated; the frame centre is the screen centre.
        let long = Double(max(width,height)), short = Double(min(width,height))
        let scale = max(long/Double(max(viewSize.height,viewSize.width)),short/Double(min(viewSize.width,viewSize.height)))
        let r = max(4,Double(radius)*scale)
        let cx = width/2, cy = height/2
        let outer = Int(r*3)
        var peak = 0.0, core = 0, saturated = 0
        var ring: [UInt8] = []
        ring.reserveCapacity(4096)
        let step = max(1,Int(r/20))
        for dy in stride(from:-outer,through:outer,by:step) {
            let y = cy+dy
            guard y >= 0, y < height else { continue }
            let row = pixels+y*rowBytes
            for dx in stride(from:-outer,through:outer,by:step) {
                let x = cx+dx
                guard x >= 0, x < width else { continue }
                let distance = (Double(dx*dx+dy*dy)).squareRoot()
                let value = row[x]
                if distance <= r {
                    core += 1
                    peak = max(peak,Double(value))
                    if value >= 235 { saturated += 1 }
                } else if distance >= r*2 && distance <= r*3 {
                    ring.append(value)
                }
            }
        }
        guard core > 0, !ring.isEmpty else { return nil }
        ring.sort()
        return Sample(peak:peak,saturatedFraction:Double(saturated)/Double(core),surroundingMedian:Double(ring[ring.count/2]))
    }
}

/// Glass hint capsule used at the bottom of the camera screens.
struct CelyxHintPill: View {
    let text: String
    var body: some View {
        HStack(spacing:12) {
            Image(systemName:"scope")
            Text(text).lineLimit(2).multilineTextAlignment(.leading)
        }
        .font(.system(size:15,weight:.semibold)).tracking(-0.23).foregroundStyle(.white)
        .padding(12)
        .background(Capsule().fill(.white.opacity(0.2)))
        .glassEffect(.regular,in:Capsule())
        .padding(.horizontal,24)
    }
}

/// Latin constellation names from the bundled Stellarium metadata (e.g. "Ori" → "Orion").
enum ConstellationNames {
    private static let names: [String:String] = {
        guard let url = try? SkyAssets.url("constellations",extension:"json"),
              let data = try? Data(contentsOf:url),
              let entries = try? JSONDecoder().decode([String:Constellation].self,from:data) else { return [:] }
        return entries.compactMapValues { $0.name ?? $0.english }
    }()
    static func name(for code: String) -> String? { names[code] }
}

#Preview("Collect stars") {
    StarCollectCameraView(model:AppPreviewData.model,onClose:{})
        .preferredColorScheme(.dark)
}

#Preview("Camera hint") {
    CelyxHintPill(text:"Hold steady while we compare the stars").padding().background(.black)
        .preferredColorScheme(.dark)
}
