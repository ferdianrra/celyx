import SwiftUI

struct GardenView: View {
    let model: HomeViewModel
    let onClose: () -> Void
    @State private var selectedID: Int?
    @State private var showsCollection = false
    @State private var inspectedItem: GardenCollectionItem?
    @State private var baseRotation = 0.0
    @State private var rotationStartedAt = Date()
    @State private var elevation = atan(0.63)
    @GestureState private var orbitDrag = CGSize.zero
    @GestureState private var isOrbiting = false
    @State private var zoom = 1.0
    @State private var rotationPaused = false
    private let rotationSpeed = 0.06
    @GestureState private var pinch = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    private var rotates: Bool { !reduceMotion && phase == .active && !showsCollection && inspectedItem == nil && !rotationPaused && !isOrbiting }
    private var selectedItem: GardenCollectionItem? { model.collectionItems.first { $0.id == selectedID } }

    var body: some View {
        let items = model.collectionItems
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea()
                    TimelineView(.animation(minimumInterval:1/30,paused:!rotates)) { context in
                        let rotation = baseRotation+orbitDrag.width/180+(rotates ? context.date.timeIntervalSince(rotationStartedAt)*rotationSpeed : 0)
                        GardenSpaceView(items:items,selectedID:selectedID,rotation:rotation,
                            elevation:clampedElevation(elevation-orbitDrag.height/240),
                            zoom:min(3.2,max(0.75,zoom*pinch)),travel:reduceMotion ? 1 : model.gardenProgress,
                            isActive:phase == .active && !showsCollection && inspectedItem == nil && !reduceMotion && !rotationPaused && !isOrbiting) { id in
                            withAnimation(.easeInOut(duration:0.2)) { selectedID = selectedID == id ? nil : id }
                        }
                        .ignoresSafeArea()
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance:5)
                        .updating($orbitDrag) { value,state,_ in state = value.translation }
                        .updating($isOrbiting) { _,state,_ in state = true }
                        .onEnded { value in
                            baseRotation += value.translation.width/180
                            elevation = clampedElevation(elevation-value.translation.height/240)
                        })
                    .accessibilityLabel("Interactive galaxy")
                    .accessibilityHint("Drag left or right to rotate. Drag up or down to change the viewing angle. Pinch to zoom.")
                    .accessibilityAction(named:Text("View from above")) { elevation = 75 * .pi/180 }
                    .accessibilityAction(named:Text("View from below")) { elevation = -60 * .pi/180 }
                    .simultaneousGesture(MagnifyGesture().updating($pinch) { value,state,_ in state = value.magnification }
                        .onEnded { zoom = min(3.2,max(0.75,zoom*$0.magnification)) })
                    VStack {
                        Spacer()
                        if let item = selectedItem {
                            Button { inspectedItem = item } label: {
                                GardenCollectionCard(star:item.star,record:item.record,isSelected:true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("garden-selected-card")
                            .transition(.move(edge:.bottom).combined(with:.opacity))
                        } else {
                            VStack(spacing:8) {
                                Text(model.collectionItems.isEmpty ? "Your galaxy starts with one star" : "\(model.collectionItems.count) little lights, all yours")
                                    .font(.headline)
                                Text(model.collectionItems.isEmpty ? "Look up and find your first star." : "Tap a light to revisit a memory.")
                                    .font(.subheadline).foregroundStyle(.white.opacity(0.6))
                                Text("Drag to orbit · Pinch to zoom").font(.caption).foregroundStyle(.white.opacity(0.45))
                                if model.collectionItems.isEmpty {
                                    Button("Explore the Sky") { onClose() }.buttonStyle(.bordered).padding(.top,8)
                                }
                            }.multilineTextAlignment(.center).padding(18)
                        }
                    }.padding(.horizontal,24).padding(.bottom,18)
                }
            }
            .navigationTitle("Your Galaxy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden,for:.navigationBar)
            .toolbarColorScheme(.dark,for:.navigationBar)
            .toolbar {
                ToolbarItem(placement:.topBarLeading) {
                    Button("Back to Sky",systemImage:"chevron.left") { onClose() }
                        .accessibilityLabel("Back to Sky")
                }
                ToolbarItemGroup(placement:.topBarTrailing) {
                    Button("Reset View",systemImage:"arrow.counterclockwise") {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration:0.3)) {
                            elevation = atan(0.63); zoom = 1; baseRotation = 0
                            rotationStartedAt = Date()
                        }
                    }
                    Button(rotationPaused ? "Rotate galaxy" : "Pause rotation",systemImage:rotationPaused ? "play.fill" : "pause.fill") {
                        rotationPaused.toggle()
                    }
                    .accessibilityIdentifier("garden-rotation-toggle")
                    Button("View Collection",systemImage:"books.vertical") { showsCollection = true }
                        .accessibilityLabel("View Collection")
                }
            }
            .navigationDestination(isPresented:$showsCollection) {
                GardenCollectionView(model:model) { id in
                    withAnimation(reduceMotion ? nil : .easeInOut(duration:0.35)) {
                        selectedID = id
                        zoom = 1
                        baseRotation = -.pi/2+0.35-GardenOrbit.angle(id:id)
                        rotationStartedAt = Date()
                    }
                }
            }
            .sheet(item:$inspectedItem) { item in SavedStarNoteView(item:item) }
        }
        .foregroundStyle(.white).tint(.white).preferredColorScheme(.dark)
        .onChange(of:rotates) { old,new in
            if old { baseRotation += Date().timeIntervalSince(rotationStartedAt)*rotationSpeed }
            if new { rotationStartedAt = Date() }
        }
        .onAppear { rotationStartedAt = Date() }
    }
    private func clampedElevation(_ angle: Double) -> Double {
        min(85 * .pi/180,max(-80 * .pi/180,angle))
    }
}

