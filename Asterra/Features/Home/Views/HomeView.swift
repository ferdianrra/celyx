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
            .toolbarVisibility(showsChrome && tourShowsBottomBar ? .visible : .hidden,for:.bottomBar)
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
        .preferredColorScheme(.dark)
        .sheet(isPresented:$showsCollection,onDismiss:openSelectedCollection) {
            CollectionSheet(counts:counts,onSelect:{ category in
                pendingCollectionCategory = category
                showsCollection = false
            },onClose:{ showsCollection = false })
            .overlay(alignment:.bottom) { collectionTourGuide }
            .presentationDetents([.height(300),.large])
            .presentationDragIndicator(.visible)
            .presentationBackground { CelyxBluePanel() }
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
        ToolbarItem(placement:.bottomBar) {
            // Figma: 284pt on a 402pt screen, i.e. the width minus 28pt margins, 12pt gap and the 50pt AR button.
            StartCollectingButton(invites:onboarding?.step == .ready,action:openStarCamera)
                .frame(width:max(160,screenWidth-118))
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarSpacer(.flexible,placement:.bottomBar)
        ToolbarItem(placement:.bottomBar) {
            // Switches the garden between the virtual Night Sea and the live camera (gyro + real sky).
            Button(gardenUsesCamera ? "Show virtual sky" : "Show real sky through the camera",
                   systemImage:gardenUsesCamera ? "moon.stars.fill" : "arkit") { gardenUsesCamera.toggle() }
                .contentTransition(.symbolEffect(.replace))
        }
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
                .padding(.horizontal,16).padding(.bottom,8)
        }
    }

    private var tourCameraLink: LiveCameraLink? { onboarding == nil ? nil : cameraLink }

    /// The toolbars come back once the tour points at them.
    /// During the tour the bottom bar shows only for steps about its buttons; the card takes its place otherwise.
    private var tourShowsBottomBar: Bool {
        guard let onboarding else { return true }
        switch onboarding.step {
        case .camera, .landed, .ready: return true
        default: return false
        }
    }

    private var tourShowsChrome: Bool {
        guard let onboarding else { return true }
        guard handover == nil else { return false }
        switch onboarding.step {
        case .camera, .landed, .collection, .calendar, .ready: return true
        default: return false
        }
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
                OnboardingGuidePill(text:caption)
                    .frame(maxHeight:.infinity,alignment:.top).padding(.top,8)
                    .padding(.horizontal,24)
                    .animation(.smooth(duration:0.5),value:caption)
                    .allowsHitTesting(false)
            }
            if handover == nil || onboarding.step != .wormhole {
                OnboardingOverlay(flow:onboarding,
                                  camera:gardenUsesCamera ? (cameraLink.pose ?? gardenCamera) : gardenCamera,
                                  chromeVisible:tourShowsChrome && tourShowsBottomBar)
                    .transition(.opacity)
            }
    }

    /// What the guide says while the wormhole carries the practice star into the Night Sea.
    private func tourCaption(_ phase: WormholeHandover.Phase) -> String? {
        switch phase {
        case .wormhole: return "Collected! Hold on, it's going through the wormhole…"
        case .landed, .reframe, .focusing, .revealing: return "Landing in your Night Sea"
        case .releasing: return "Here it is. Let's give it a note."
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
    private func openStarCamera() { showsStarCamera = true }

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
private struct StartCollectingButton: View {
    /// End of the run-through: a slow halo breathes around the button to invite the first real collect.
    var invites = false
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button(action:action) {
            HStack(spacing:12) {
                Image("celyx-icon-telescope").resizable().frame(width:28,height:28)
                Text("Start Collecting").font(.system(size:17,weight:.semibold)).tracking(-0.43)
                    .foregroundStyle(CelyxColor.primaryLabel)
            }
            .padding(.horizontal,20)
            .frame(maxWidth:.infinity).frame(height:50)
            .contentShape(Capsule())
        }
        .buttonStyle(CelyxTintedGlassButtonStyle())
        .background {
            if invites && !reduceMotion {
                Capsule().fill(CelyxColor.accent)
                    .blur(radius:14)
                    .phaseAnimator([0.25,0.7]) { glow, value in glow.opacity(value).scaleEffect(0.9+value*0.12) }
                        animation: { _ in .easeInOut(duration:1.3) }
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration:0.6),value:invites)
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

