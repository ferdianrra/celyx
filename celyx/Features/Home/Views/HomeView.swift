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
    @State private var handover: WormholeHandover?
    @State private var sheetRequest: GardenSheetRequest?
    /// Debug demo star is in the sky / its card is open: keep the empty-state text out of the way.
    @State private var demoShowing = false
    @State private var screenWidth: CGFloat = 402
    @AppStorage("gardenUsesCamera") private var gardenUsesCamera = false
    @AppStorage("gardenUsesGyro") private var gardenUsesGyro = true
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack(path:$path) {
            ZStack(alignment:.bottom) {
                GardenSkyView(model:model,camera:$gardenCamera,
                              isActive:phase == .active && path.isEmpty && camera == nil && !showsCollection && !showsCalibration
                                && (!showsStarCamera || (handover?.phase ?? .wormhole) >= .landed),
                              resetRequest:gardenReset,usesCamera:gardenUsesCamera,usesGyro:gardenUsesGyro,
                              onUseTouch:{ gardenUsesGyro = false },
                              handover:handover,sheetRequest:sheetRequest,onDemoEnded:{ demoShowing = false })
                    .ignoresSafeArea()

                if model.collectionItems.isEmpty && !showsCollection && handover == nil && !demoShowing {
                    VStack(spacing:6) {
                        Text("Your sky is still empty").font(.system(size:15,weight:.semibold))
                        Text("Collect your first star and it will shine here.").font(.system(size:13)).opacity(0.7)
                    }
                    .foregroundStyle(.white).multilineTextAlignment(.center)
                    .frame(maxWidth:.infinity,maxHeight:.infinity).allowsHitTesting(false)
                }
            }
            .background(CelyxColor.night)
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
                    // The demo isn't saved, so its album shows the frozen frame (with the demo star painted in).
                    let photo = handover.demo != nil ? handover.freeze.image.map { UIImage(cgImage:$0) } : nil
                    sheetRequest = GardenSheetRequest(itemID:id,demoItem:handover.demo?.item,photo:photo)
                }
            }
            // Figma "Home Screen" (998:2689): native top toolbar (compass, then a button group with the
            // collection and the calendar) and a native bottom toolbar (Start Collecting, real-sky camera).
            .toolbar { homeToolbar }
            .toolbarVisibility(showsChrome ? .visible : .hidden,for:.navigationBar,.bottomBar)
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
        .preferredColorScheme(.dark)
        .sheet(isPresented:$showsCollection,onDismiss:openSelectedCollection) {
            CollectionSheet(counts:counts,onSelect:{ category in
                pendingCollectionCategory = category
                showsCollection = false
            },onClose:{ showsCollection = false })
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
            Button("Your Collection",systemImage:"book.fill") { showsCollection = true }
            Button("Sky Calendar",systemImage:"calendar") { path.append(.calendar) }
        }
        ToolbarItem(placement:.bottomBar) {
            // Figma: 284pt on a 402pt screen, i.e. the width minus 28pt margins, 12pt gap and the 50pt AR button.
            StartCollectingButton(action:openStarCamera)
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

    /// Hidden under the star camera and the wormhole; fades back in right after the landing.
    private var showsChrome: Bool {
        guard let handover else { return true }
        return handover.phase >= .landed
    }

    // MARK: Star camera + wormhole handover

    /// The star camera is presented like dev does (a full-screen cover), so Ferdi's toolbar renders.
    private func openStarCamera() { showsStarCamera = true }

    private func collected(_ result: StarCollectCameraView.CollectResult) {
        switch result {
        case .wormhole(let handover):
            self.handover = handover
            demoShowing = handover.demo != nil
            Task { await handover.run() }
        case .fade(let itemID):
            // Reduce Motion: 400 ms cross-fade to the garden, then the sheet.
            withAnimation(.easeInOut(duration:0.4)) { showsStarCamera = false }
            guard let itemID else { return }
            Task {
                try? await Task.sleep(for:.milliseconds(400))
                sheetRequest = GardenSheetRequest(itemID:itemID)
            }
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
    let action: () -> Void
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

