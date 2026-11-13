import AVFoundation
import SwiftUI

/// Figma "Home Screen" (830:5105) + "Collection About" (886:6050).
struct HomeView: View {
    let model: HomeViewModel
    @State private var events = SkyEventStore()
    @State private var path: [HomeRoute] = []
    @State private var showsCollection = false
    @State private var pendingCollectionCategory: CollectionCategory?
    @State private var camera: CollectCameraView.Mode?
    @State private var gardenCamera = NightSeaCamera()
    @State private var gardenReset = 0
    @State private var showsCalibration = false
    /// The star collect camera, shown in place (not a cover) so the wormhole can hand over to the garden.
    @State private var showsStarCamera = false
    @State private var handoverTask: Task<Void, Never>?
    @State private var handover: WormholeHandover?
    @State private var sheetRequest: GardenSheetRequest?
    /// Debug demo star is in the sky / its card is open: keep the empty-state text out of the way.
    @State private var demoShowing = false
    @State private var screenSize = CGSize(width: 402, height: 874)
    @State private var screenWidth: CGFloat = 402
    @AppStorage("gardenUsesCamera") private var gardenUsesCamera = false
    @State private var gardenUsesGyro = true
    /// First-run run-through over the Night Sea (replayable from the direction menu).
    @AppStorage("hasCompletedTour") private var hasCompletedOnboarding = false
    @State private var onboarding: OnboardingFlow?
    /// The tour's view into the live camera mode.
    @State private var cameraLink = LiveCameraLink()
    /// The tour's capture cue (frozen frame + when the shutter fired), before its wormhole opens.
    @State private var tourShutter: (start: Date, image: CGImage?)?
    @State private var tourCameraTimeout: Task<Void, Never>?
    @State private var didAutoStartTour = false
    /// Where the tour's highlighted controls really are (measured, so it fits every device).
    @State private var tourTargets: [OnboardingFlow.Pointer: CGRect] = [:]
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack(path:$path) {
            ZStack(alignment:.bottom) {
                GardenSkyView(model:model,camera:$gardenCamera,
                              isActive:phase == .active && path.isEmpty && camera == nil && !showsCollection && !showsCalibration
                                && (!showsStarCamera || (handover?.phase ?? .wormhole) >= .landed),
                              resetRequest:gardenReset,usesCamera:gardenUsesCamera,usesGyro:gardenUsesGyro,
                              onModeChange:{ gardenUsesGyro = $0 },
                              handover:handover,sheetRequest:sheetRequest,onDemoEnded:{ demoShowing = false },
                              cameraLink:tourCameraLink)
                    .ignoresSafeArea()

                if let onboarding { tourLayer(onboarding) }

                if showsChrome && tourShowsBottomBar {
                    bottomBar
                        .frame(maxHeight:.infinity,alignment:.bottom)
                        .ignoresSafeArea(edges:.bottom)
                        .transition(.move(edge:.bottom).combined(with:.opacity))
                }

                if model.collectionItems.isEmpty && !showsCollection && handover == nil && !demoShowing && onboarding == nil {
                    VStack(spacing:6) {
                        Text("Your sky is still empty").font(.system(size:15,weight:.semibold))
                        Text("Collect your first star and it will shine here.").font(.system(size:13)).opacity(0.7)
                    }
                    .foregroundStyle(.white).multilineTextAlignment(.center)
                    .frame(maxWidth:.infinity,maxHeight:.infinity).allowsHitTesting(false)
                }
            }
            .background(CelyxColor.night)
            .modifier(TourSignals(home:self))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { screenSize = $0 }
            .onGeometryChange(for:CGFloat.self) { $0.size.width } action:{ screenWidth = $0 }
            .onChange(of:handover?.phase) { _, phase in
                guard let phase else { return }
                switch phase {
                case .reframe:
                    // The Night Sea now matches the wormhole pixel for pixel: drop the camera without a transition.
                    var transaction = Transaction(); transaction.disablesAnimations = true
                    withTransaction(transaction) { showsStarCamera = false }
                case .done:
                    self.handover = nil
                default: break
                }
            }
            .onChange(of:handover?.showsSheet == true) { _, shows in
                if shows, let handover, let id = handover.itemID {
                    // Demo albums use the same composited frame that was saved with the observation.
                    let photo = handover.demo != nil ? handover.freeze.image.map { UIImage(cgImage:$0) } : nil
                    if !reduceMotion { WormholeFeedback.shared.playSheet() }
                    sheetRequest = GardenSheetRequest(itemID:id,demoItem:handover.demo?.item,photo:photo,
                                                      isTour:onboarding != nil)
                }
            }
            // Figma "Home Screen" (998:2689): native top toolbar (compass, then a button group with the
            // collection and the calendar) and a native bottom toolbar (Start Collecting, real-sky camera).
            .toolbar { homeToolbar }
            .toolbarVisibility(showsChrome ? .visible : .hidden,for:.navigationBar)
            .navigationDestination(for:HomeRoute.self) { route in
                switch route {
                case .calendar:
                    SkyCalendarView(store:events) { path.append(.event($0)) }
                case .event(let event):
                    SkyEventDetailView(event:event,store:events) { camera = .event(event) }
                case .collection(let category):
                    CollectionListView(category:category,model:model,events:events) { path.append(.event($0)) }
                }
            }
        }
        .overlay(alignment:.bottom) { pushedTourGuide }
        // Above the toolbars, in window coordinates: the measured control the tour asks for glows and ripples.
        .overlay { tourHighlight }
        .animation(.spring(duration:0.45,bounce:0.1),value:showsChrome && tourShowsBottomBar)
        .preferredColorScheme(.dark)
        .sheet(isPresented:$showsCollection,onDismiss:openSelectedCollection) {
            CollectionSheet(counts:counts,onSelect:{ category in
                pendingCollectionCategory = category
                showsCollection = false
            },onClose:{ showsCollection = false })
            .safeAreaInset(edge:.bottom,spacing:0) { collectionTourGuide }
            .presentationDetents([.height(onboarding?.step == .collection ? 380 : 300),.large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented:$showsCalibration) {
            SkyCalibrationView(catalogue:model.stars,alignment:model.cameraAlignment) { showsCalibration = false }
        }
        .fullScreenCover(isPresented:$showsStarCamera) {
            StarCollectCameraView(model:model,handover:handover,onCollect:collected) { showsStarCamera = false }
        }
        .fullScreenCover(item:$camera) { mode in
            CollectCameraView(mode:mode,model:model,events:events) { finished in
                camera = nil
                if finished { path.removeAll() }
            }
        }
    }

    @ToolbarContentBuilder private var homeToolbar: some ToolbarContent {
        ToolbarItem(placement:.topBarLeading) {
            Menu {
                Picker("Sky controls",selection:$gardenUsesGyro) {
                    Label("Gyro",systemImage:"gyroscope").tag(true)
                    Label("Touch",systemImage:"hand.draw").tag(false)
                }
                Button("Calibrate direction",systemImage:"scope") { showsCalibration = true }
                Button("Reset view",systemImage:"arrow.counterclockwise") { gardenReset += 1 }
                Button("Replay intro",systemImage:"sparkles") { startOnboarding() }
            } label: {
                Group {
                    if gardenUsesGyro {
                        CompassBadge().rotationEffect(.radians(-gardenCamera.heading))
                    } else {
                        Image(systemName:"hand.draw").font(.system(size:20)).foregroundStyle(.white)
                    }
                }
                .frame(width:44,height:44).contentShape(Circle())
            }
            // HIG: a fixed 44×44 round Liquid Glass button of its own, not the toolbar's shared capsule.
            .frame(width:44,height:44)
            .glassEffect(.regular.interactive(),in:Circle())
            .accessibilityLabel("Direction options")
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItemGroup(placement:.topBarTrailing) {
            Button("Your Collection",systemImage:"text.book.closed") { showsCollection = true }
            Button("Sky Calendar",systemImage:"calendar") { path.append(.calendar) }
        }
    }

    /// The bottom row laid out like the native floating tab bar with a `role: .search` slot (measured on
    /// iOS 27: 62pt tall, 28pt side margins, 21pt above the screen's bottom edge): Start Collecting fills the
    /// bar, the real-sky camera sits in the trailing search circle.
    private var bottomBar: some View {
        HStack(spacing:TabBarMetrics.searchGap) {
            StartCollectingButton(height:TabBarMetrics.height,action:openStarCamera)
                .background(WindowFrameReader { tourTargets[.startCollecting] = $0 })
            // Switches the garden between the virtual Night Sea and the live camera (gyro + real sky).
            Button { gardenUsesCamera.toggle() } label: {
                Image(systemName:gardenUsesCamera ? "moon.stars.fill" : "arkit")
                    .font(.system(size:22,weight:.medium))
                    .foregroundStyle(CelyxColor.primaryLabel)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width:TabBarMetrics.height,height:TabBarMetrics.height)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(),in:Circle())
            .background(WindowFrameReader { tourTargets[.cameraButton] = $0 })
            .accessibilityLabel(gardenUsesCamera ? "Show virtual sky" : "Show real sky through the camera")
        }
        .padding(.horizontal,TabBarMetrics.sideMargin)
        .padding(.bottom,TabBarMetrics.bottomMargin)
        .environment(\.colorScheme,.dark)
    }

    /// Keep controls out of the presentation until the reveal and live-camera return finish.
    private var showsChrome: Bool {
        if onboarding != nil { return tourShowsChrome }
        guard let handover else { return true }
        return handover.phase >= .presenting
    }

    // MARK: Onboarding

    private var shouldStartOnboarding: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-onboarding") { return true }
        #endif
        return !hasCompletedOnboarding
    }

    /// The tour's signals from Home's state (kept apart so `body` type-checks quickly).
    private struct TourSignals: ViewModifier {
        let home: HomeView
        func body(content: Content) -> some View {
            content
                // Once per launch: returning from a pushed screen re-runs `task`, which must not restart the tour.
                .task { if home.shouldStartOnboarding && !home.didAutoStartTour { home.didAutoStartTour = true; home.startOnboarding() } }
                .onChange(of:home.gardenUsesCamera) { _, on in home.tourCameraModeChanged(on) }
                .onChange(of:home.gardenCamera,initial:true) { _, camera in home.onboarding?.cameraChanged(camera) }
                .onChange(of:home.cameraLink.pose != nil) { _, ready in
                    guard ready, home.gardenUsesCamera, let pose = home.cameraLink.pose else { return }
                    home.tourCameraTimeout?.cancel()
                    home.onboarding?.liveCameraReady(pose)
                }
                .onChange(of:home.handover == nil) { _, ended in if ended { home.onboarding?.wormholeEnded() } }
                .onChange(of:home.featureOpen) { _, open in if !open { home.onboarding?.returnedFromFeature() } }
        }
    }

    @ViewBuilder private var tourHighlight: some View {
        if let onboarding, let pointer = onboarding.pointer, path.isEmpty, !showsCollection, handover == nil,
           let target = tourTarget(pointer) {
            OnboardingHighlight(size:target.size)
                .position(x:target.midX,y:target.midY)
                .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
                .ignoresSafeArea()
                .id(pointer)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    /// The control's frame in window coordinates. Start Collecting is measured; the system toolbar buttons
    /// (bar items SwiftUI can't measure) sit at the native toolbar's fixed metrics from the window edges.
    private func tourTarget(_ pointer: OnboardingFlow.Pointer) -> CGRect? {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first
        else { return nil }
        let size = window.bounds.size, insets = window.safeAreaInsets
        func round(_ x: CGFloat,_ y: CGFloat) -> CGRect { CGRect(x:x-23,y:y-23,width:46,height:46) }
        let topRow = insets.top+22
        switch pointer {
        case .startCollecting:
            if let frame = tourTargets[.startCollecting] { return frame }
            let m = TabBarMetrics.self
            let width = size.width-2*m.sideMargin-m.searchGap-m.height
            return CGRect(x:m.sideMargin,y:size.height-m.bottomMargin-m.height,width:width,height:m.height)
        case .cameraButton:
            if let frame = tourTargets[.cameraButton] { return frame }
            return round(size.width-TabBarMetrics.sideMargin-TabBarMetrics.height/2,size.height-TabBarMetrics.bottomMargin-TabBarMetrics.height/2)
        case .collectionButton: return round(size.width-98.5,topRow)
        case .calendarButton: return round(size.width-43,topRow)
        }
    }

    /// The guide on screens pushed during the tour (collection list, Sky Calendar).
    @ViewBuilder private var pushedTourGuide: some View {
        if let onboarding, !path.isEmpty, onboarding.step == .collection || onboarding.step == .calendar {
            OnboardingGuidePill(text:onboarding.step == .calendar
                ? "Upcoming sky events live here. Tap ‹ at the top when you're done looking."
                : "Everything you collect will be listed here. Tap ‹ at the top to come back.")
                .padding(.horizontal,16).padding(.bottom,24)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var collectionTourGuide: some View {
        if onboarding?.step == .collection {
            OnboardingGuidePill(text:"Tap a category to look inside, or swipe down to close.")
                .frame(maxWidth:.infinity,alignment:.leading)
                .padding(.horizontal,16).padding(.top,8).padding(.bottom,4)
        }
    }

    private var windowSafeTop: CGFloat {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.safeAreaInsets.top ?? 0
    }

    private var tourCameraLink: LiveCameraLink? { onboarding == nil ? nil : cameraLink }

    /// The toolbars come back once the tour points at them.
    /// During the tour the bottom bar shows only for steps about its buttons; the card takes its place otherwise.
    private var tourShowsBottomBar: Bool {
        // Only while the card asks for one of its buttons; a card with its own button (Continue) never
        // shares the screen with the toolbar's, so there is always exactly one thing to press.
        guard let onboarding else { return true }
        switch onboarding.pointer {
        case .cameraButton, .startCollecting: return true
        default: return false
        }
    }

    private var tourShowsChrome: Bool {
        guard let onboarding else { return true }
        // Toolbars appear only while the tour points at one of their controls.
        return handover == nil && onboarding.pointer != nil
    }

    /// The tour's layers over the garden: its capture cue, wormhole, captions and coach overlay.
    @ViewBuilder private func tourLayer(_ onboarding: OnboardingFlow) -> some View {
            // The tour's practice capture: the same cekrek and wormhole the camera uses.
            if let tourShutter {
                TimelineView(.animation) { timeline in
                    CaptureFlashView(image:tourShutter.image,t:timeline.date.timeIntervalSince(tourShutter.start)*1000)
                }
                .ignoresSafeArea().allowsHitTesting(false)
            }
            if let handover, handover.phase < .reframe, !reduceMotion {
                WormholeHandoverView(handover:handover)
            }
            if let handover, onboarding.step == .wormhole, let caption = tourCaption(handover.phase) {
                // Below the Dynamic Island / notch on every device.
                OnboardingGuidePill(text:caption)
                    .padding(.top,windowSafeTop + 10)
                    .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top)
                    .padding(.horizontal,24)
                    .ignoresSafeArea()
                    .animation(.smooth(duration:0.5),value:caption)
                    .allowsHitTesting(false)
            }
            if handover == nil || onboarding.step != .wormhole {
                OnboardingOverlay(flow:onboarding,
                                  camera:gardenUsesCamera ? (cameraLink.pose ?? gardenCamera) : gardenCamera,
                                  chromeVisible:tourShowsChrome && tourShowsBottomBar,
                                  topBarVisible:tourShowsChrome)
                    .transition(.opacity)
            }
    }

    /// What the guide says while the wormhole carries the practice star into the Night Sea.
    private func tourCaption(_ phase: WormholeHandover.Phase) -> String? {
        switch phase {
        // One line for the whole flight: changing captions go by too fast to read.
        case .wormhole, .landed, .reframe, .focusing, .revealing, .releasing:
            return "Collected! Watch it fly into your Night Sea."
        case .presenting, .done: return nil
        }
    }

    /// The collection sheet, a collection list or the calendar is open.
    private var featureOpen: Bool { showsCollection || !path.isEmpty || pendingCollectionCategory != nil }

    private func startOnboarding() {
        let flow = OnboardingFlow()
        flow.reduceMotion = reduceMotion
        flow.actions = .init(
            setCamera:{ on in setTourCamera(on,flow:flow) },
            openCollection:{ showsCollection = true },
            openCalendar:{ path.append(.calendar) },
            collect:{ star, point in collectPractice(star,at:point) },
            finish:{
                hasCompletedOnboarding = true
                tourCameraTimeout?.cancel()
                withAnimation(.smooth(duration:0.6)) { onboarding = nil }
            })
        // The tour starts in the virtual sky with the gyro, facing wherever the phone points.
        gardenUsesGyro = true
        gardenUsesCamera = false
        path.removeAll()
        withAnimation(.smooth(duration:0.5)) { onboarding = flow }
        flow.cameraChanged(gardenCamera)
        #if DEBUG
        if let jump = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-onboarding-step=") }) {
            flow.jump(to:String(jump.dropFirst("-onboarding-step=".count)))
        }
        if ProcessInfo.processInfo.arguments.contains("-onboarding-autoplay") { Task { await flow.autoplay() } }
        #endif
    }

    /// Turns the garden's camera view on or off for the tour (the user normally uses the toolbar button).
    private func setTourCamera(_ on: Bool,flow: OnboardingFlow) {
        withAnimation(.smooth(duration:0.5)) { gardenUsesCamera = on }
    }

    /// The user switched the camera view with the toolbar button during the tour.
    private func tourCameraModeChanged(_ on: Bool) {
        guard let flow = onboarding else { return }
        flow.cameraModeChanged(on)
        tourCameraTimeout?.cancel()
        guard on, flow.step == .camera else { return }
        tourCameraTimeout = Task { @MainActor in
            // Ask for the camera in context; the wait for tracking starts after the user answers.
            if AVCaptureDevice.authorizationStatus(for:.video) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for:.video)
            }
            guard AVCaptureDevice.authorizationStatus(for:.video) == .authorized else {
                withAnimation(.smooth(duration:0.5)) { gardenUsesCamera = false }
                flow.cameraFailed(); return
            }
            // No tracked camera pose in time (no ARKit, covered lens): practise in the Night Sea instead.
            try? await Task.sleep(for:.seconds(8))
            guard !Task.isCancelled, cameraLink.pose == nil else { return }
            withAnimation(.smooth(duration:0.5)) { gardenUsesCamera = false }
            flow.cameraFailed()
        }
    }

    /// The practice star's capture: cekrek on the frozen frame, then the real wormhole into the Night Sea
    /// and the note sheet. A WormholeDemo shows it there without saving anything to the collection.
    private func collectPractice(_ star: OnboardingFlow.PracticeStar,at point: CGPoint) {
        guard handover == nil else { return }
        let size = screenSize
        let liveFreeze = gardenUsesCamera ? cameraLink.freeze() : nil
        let view = gardenUsesCamera ? (cameraLink.pose ?? gardenCamera) : gardenCamera
        let freeze = liveFreeze ?? WormholeFreeze(image:nil,size:size,
            orientation:WormholeFreeze.orientation(forward:view.forward,right:view.right,up:view.up),
            focal:view.focalLength(in:size))
        let location = model.location
        let record = CollectedStar(id:star.id,date:Date(),latitude:location?.latitude ?? 0,longitude:location?.longitude ?? 0,
                                   identificationNote:"Practice star from the Asterra tour. Not saved to your collection.")
        let demo = WormholeDemo(item:GardenCollectionItem(star:star.catalogStar,record:record),
            object:NightSeaObject(id:star.id,direction:star.direction,
                                  radius:NightSeaObject.starRadius(magnitude:star.catalogStar.mag)*1.3,
                                  color:star.color,kind:.star))
        let transition = WormholeHandover(freeze:freeze,star:point,itemID:star.id,
            scene:GardenSkyView.wormholeScene(model:model,newID:star.id,demo:demo),demo:demo)
        demoShowing = true
        if reduceMotion {
            CrosshairFeedback.shared.play(CrosshairSound.collect)
            CrosshairFeedback.shared.play(CrosshairHaptic.collect)
            handover = transition
            handoverTask?.cancel()
            handoverTask = Task { await transition.run(reduceMotion:true) }
            return
        }
        WormholeFeedback.shared.prepare()
        WormholeFeedback.shared.playShutter()
        tourShutter = (Date(),freeze.image)
        Task { @MainActor in
            try? await Task.sleep(for:.milliseconds(Int(CaptureFlash.handoverDelay)))
            for sound in CrosshairSound.allCases { CrosshairFeedback.shared.suppress(sound,for:4) }
            WormholeFeedback.shared.play(landing:transition.landing)
            handover = transition
            handoverTask?.cancel()
            handoverTask = Task { await transition.run() }
            try? await Task.sleep(for:.milliseconds(Int(CaptureFlash.duration-CaptureFlash.handoverDelay)+20))
            tourShutter = nil
        }
    }

    // MARK: Star camera + wormhole handover

    /// The star camera is presented like dev does (a full-screen cover), so Ferdi's toolbar renders.
    private func openStarCamera() {
        // The tour's last step points here: pressing it ends the tour and starts the real thing.
        if let onboarding, onboarding.startCollectingPressed() { return }
        showsStarCamera = true
    }

    private func collected(_ result: StarCollectCameraView.CollectResult) {
        switch result {
        case .wormhole(let handover):
            self.handover = handover
            demoShowing = handover.demo != nil
            handoverTask?.cancel()
            handoverTask = Task { await handover.run() }
        case .fade(let itemID):
            // Reduce Motion: cross-fade, reveal in place, then present the album.
            withAnimation(.easeInOut(duration:0.4)) { showsStarCamera = false }
            guard let itemID else { return }
            let transition = WormholeHandover(freeze: .placeholder(size: screenSize),
                star: CGPoint(x: screenSize.width / 2, y: screenSize.height / 2), itemID: itemID,
                scene: GardenSkyView.wormholeScene(model: model, newID: itemID))
            handoverTask?.cancel()
            handover = transition
            handoverTask = Task { await transition.run(reduceMotion: true) }
        }
    }

    private var counts: CollectionSheet.Counts {
        let items = model.collectionItems
        return .init(stars:CollectionCategory.stars(items).count,
                     planets:CollectionCategory.planets(items).count,
                     events:events.collected.count,
                     constellations:CollectionCategory.constellations(items).count)
    }
    private func openSelectedCollection() {
        // Wait for the system sheet to dismiss before navigating on the home stack.
        guard let category = pendingCollectionCategory else { return }
        pendingCollectionCategory = nil
        path.append(.collection(category))
    }
    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier:"en_US")
        formatter.dateFormat = "d MMMM HH.mm a"
        return formatter.string(from:date)
    }
}

/// Compass glyph from the home top bar (Figma "Frame 2" 830:5348).
private struct CompassBadge: View {
    var body: some View {
        ZStack {
            Image("celyx-icon-compass").resizable().frame(width:38,height:38)
            Text("N").font(.system(size:15,weight:.semibold,design:.default)).foregroundStyle(.white).offset(y:1)
            Rectangle().fill(.white).frame(width:6,height:1).offset(x:-16)
            Rectangle().fill(.white).frame(width:6,height:1).offset(x:16)
            Rectangle().fill(.white).frame(width:1,height:6).offset(y:16)
        }
        .frame(width:38,height:38)
    }
}

/// "Start Collecting" (Figma 998:2695): native Liquid Glass tinted with the Figma inner-shadow stack.
/// Native floating tab bar metrics, measured on the iOS 27 simulator (iPhone 18 Pro).
enum TabBarMetrics {
    /// The large control size (50pt), centred where the native 62pt bar sits.
    static let height: CGFloat = 50
    static let sideMargin: CGFloat = 28
    /// From the screen's bottom edge (the bar sits inside the home-indicator area).
    static let bottomMargin: CGFloat = 27
    /// Between the bar and the separate search circle.
    static let searchGap: CGFloat = 12
}

private struct StartCollectingButton: View {
    var height: CGFloat = 50
    let action: () -> Void
    var body: some View {
        Button(action:action) {
            HStack(spacing:12) {
                Image("celyx-icon-telescope").resizable().frame(width:28,height:28)
                Text("Start Collecting").font(.system(size:17,weight:.semibold)).tracking(-0.43)
                    .foregroundStyle(CelyxColor.primaryLabel)
            }
            .padding(.horizontal,20)
            .frame(maxWidth:.infinity).frame(height:height)
            .contentShape(Capsule())
        }
        .buttonStyle(CelyxTintedGlassButtonStyle())
        .accessibilityIdentifier("start-collecting")
    }
}

#Preview { HomeView(model:AppPreviewData.collectedModel) }

#Preview("Compass badge") {
    CompassBadge().padding().background(.black)
        .preferredColorScheme(.dark)
}

#Preview("Start Collecting") {
    StartCollectingButton {}.padding(28).background(.black)
        .preferredColorScheme(.dark)
}

