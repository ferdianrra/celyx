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
    @State private var showsFilteredStars = false
    @AppStorage("gardenUsesGyro") private var gardenUsesGyro = true
    @AppStorage("gardenUsesCamera") private var gardenUsesCamera = false
    @Environment(\.scenePhase) private var phase
    @AppStorage("galaxyOwnerName") private var ownerName = "Ferdiansyah"

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                GardenSkyView(
                    model: model, camera: $gardenCamera,
                    isActive: phase == .active && path.isEmpty && camera == nil && !showsCollection
                        && !showsCalibration && !showsFilteredStars,
                    resetRequest: gardenReset, usesCamera: gardenUsesCamera, usesGyro: gardenUsesGyro,
                    onUseTouch: { gardenUsesGyro = false }
                )
                .ignoresSafeArea()

                if model.collectionItems.isEmpty && !showsCollection {
                    VStack(spacing: 6) {
                        Text("Your sky is still empty").font(.system(size: 15, weight: .semibold))
                        Text("Collect your first star and it will shine here.").font(.system(size: 13))
                            .opacity(
                                0.7)
                    }
                    .foregroundStyle(.white).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).allowsHitTesting(false)
                }

                VStack(spacing: 0) {
                    topBar
                    HStack {
                        CelyxGlassButton(width: 156, action: { showsFilteredStars = true }) {
                            Label("Filtered Stars", systemImage: "list.star")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(
                                    CelyxColor.primaryLabel)
                        }
                        .accessibilityIdentifier("open-filtered-stars")
                        Spacer()
                        backgroundToggle
                    }
                    .padding(.horizontal, 20)
                    Spacer(minLength: 0)
                    bottomBar
                }
            }
            .background(CelyxColor.night)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .calendar:
                    SkyCalendarView(store: events) { path.append(.event($0)) }
                case .event(let event):
                    SkyEventDetailView(event: event, store: events) { camera = .event(event) }
                case .collection(let category):
                    CollectionListView(category: category, model: model, events: events) {
                        path.append(.event($0))
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsCollection, onDismiss: openSelectedCollection) {
            CollectionSheet(
                counts: counts,
                onSelect: { category in
                    pendingCollectionCategory = category
                    showsCollection = false
                }, onClose: { showsCollection = false }
            )
            .presentationDetents([.height(300), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground { CelyxBluePanel() }
        }
        .fullScreenCover(isPresented: $showsFilteredStars) {
            FilteredStarsView(model: model)
        }
        .fullScreenCover(isPresented: $showsCalibration) {
            SkyCalibrationView(catalogue: model.stars, alignment: model.cameraAlignment) {
                showsCalibration = false
            }
        }
        .fullScreenCover(item: $camera) { mode in
            CollectCameraView(mode: mode, model: model, events: events) { finished in
                camera = nil
                if finished { path.removeAll() }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Menu {
                Picker("Sky controls", selection: $gardenUsesGyro) {
                    Label("Gyro", systemImage: "gyroscope").tag(true)
                    Label("Touch", systemImage: "hand.draw").tag(false)
                }
                Button("Calibrate direction", systemImage: "scope") { showsCalibration = true }
                Button("Reset view", systemImage: "arrow.counterclockwise") { gardenReset += 1 }
            } label: {
                Group {
                    if gardenUsesGyro {
                        CompassBadge().rotationEffect(.radians(-gardenCamera.heading))
                    } else {
                        Image(systemName: "hand.draw").font(.system(size: 22)).foregroundStyle(.white)
                    }
                }
                .frame(width: 48, height: 48).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .accessibilityLabel("Direction options")
            TimelineView(.everyMinute) { context in
                VStack(spacing: 0) {
                    Text("\(ownerName) Galaxy").font(.system(size: 15)).tracking(-0.23).lineSpacing(0).frame(
                        height: 20)
                    Text(Self.dateText(context.date)).font(.system(size: 12)).opacity(0.5).frame(height: 16)
                }
                .foregroundStyle(.white).lineLimit(1)
                .frame(maxWidth: .infinity)
            }
            CelyxGlassButton(width: 56, action: { showsCollection = true }) {
                Image(systemName: "text.book.closed").font(.system(size: 17, weight: .medium))
                    .foregroundStyle(CelyxColor.primaryLabel)
            }
            .accessibilityLabel("Your Collection")
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    /// Switches the garden between the virtual Night Sea and the live camera.
    private var backgroundToggle: some View {
        CelyxGlassButton(width: 56, action: { gardenUsesCamera.toggle() }) {
            Image(systemName: gardenUsesCamera ? "moon.stars.fill" : "camera.fill")
                .font(.system(size: 18, weight: .medium)).foregroundStyle(CelyxColor.primaryLabel)
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel(gardenUsesCamera ? "Show virtual sky" : "Show real sky through the camera")
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                camera = .star
            } label: {
                HStack(spacing: 12) {
                    Image("celyx-icon-telescope").resizable().frame(width: 28, height: 28)
                    Text("Start Collecting").font(.system(size: 17, weight: .semibold)).tracking(-0.43)
                        .foregroundStyle(CelyxColor.primaryLabel)
                }
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(StartCollectingBackground())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("start-collecting")
            CelyxGlassButton(action: { path.append(.calendar) }) {
                Image(systemName: "calendar").font(.system(size: 24, weight: .medium)).foregroundStyle(
                    .white)
            }
            .accessibilityLabel("Sky Calendar")
        }
        .padding(.horizontal, 28).padding(.bottom, 4)
    }

    private var counts: CollectionSheet.Counts {
        let items = model.collectionItems
        return .init(
            stars: CollectionCategory.stars(items).count,
            planets: CollectionCategory.planets(items).count,
            events: events.collected.count,
            constellations: CollectionCategory.constellations(items).count)
    }
    private func openSelectedCollection() {
        // Wait for the system sheet to dismiss before navigating on the home stack.
        guard let category = pendingCollectionCategory else { return }
        pendingCollectionCategory = nil
        path.append(.collection(category))
    }
    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "d MMMM HH.mm a"
        return formatter.string(from: date)
    }
}

/// Compass glyph from the home top bar (Figma "Frame 2" 830:5348).
private struct CompassBadge: View {
    var body: some View {
        ZStack {
            Image("celyx-icon-compass").resizable().frame(width: 38, height: 38)
            Text("N").font(.system(size: 15, weight: .semibold, design: .default)).foregroundStyle(.white)
                .offset(y: 1)
            Rectangle().fill(.white).frame(width: 6, height: 1).offset(x: -16)
            Rectangle().fill(.white).frame(width: 6, height: 1).offset(x: 16)
            Rectangle().fill(.white).frame(width: 1, height: 6).offset(y: 16)
        }
        .frame(width: 38, height: 38)
    }
}

/// Blue Liquid Glass fill of the "Start Collecting" button (inner shadows #7459DF / #0066E2 / #062277).
private struct StartCollectingBackground: View {
    var body: some View {
        Capsule().fill(
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0xBCADF9), location: 0),
                    .init(color: Color(hex: 0x7B6CDE), location: 0.07),
                    .init(color: Color(hex: 0x766DDE), location: 0.24),
                    .init(color: Color(hex: 0x636ED9), location: 0.30),
                    .init(color: Color(hex: 0x4069CF), location: 0.36),
                    .init(color: Color(hex: 0x1661BF), location: 0.42),
                    .init(color: Color(hex: 0x0359AF), location: 0.48),
                    .init(color: Color(hex: 0x0351A1), location: 0.54),
                    .init(color: Color(hex: 0x074995), location: 0.60),
                    .init(color: Color(hex: 0x0A438C), location: 0.66),
                    .init(color: Color(hex: 0x103F85), location: 0.72),
                    .init(color: Color(hex: 0x133D80), location: 0.84),
                    .init(color: Color(hex: 0x184285), location: 0.90),
                    .init(color: Color(hex: 0x214D90), location: 1),
                ], startPoint: .top, endPoint: .bottom)
        )
        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 15, x: 0, y: 8)
    }
}

#Preview { HomeView(model: AppPreviewData.collectedModel) }

#Preview("Compass badge") {
    CompassBadge().padding().background(.black)
        .preferredColorScheme(.dark)
}

#Preview("Collecting background") {
    StartCollectingBackground().frame(height: 64).padding().background(.black)
        .preferredColorScheme(.dark)
}
