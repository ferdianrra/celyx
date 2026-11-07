//
//  HomeView.swift
//  celyx
//
//  Created by Ferdiansyah Annora on 02/11/26.
//

import SwiftUI

struct HomeView: View {
    @State private var model: HomeViewModel
    private var onReturnToGarden: (() -> Void)? = nil
    @MainActor init() { _model = State(initialValue:HomeViewModel()) }
    init(model: HomeViewModel,onReturnToGarden: (() -> Void)? = nil) {
        _model = State(initialValue:model)
        self.onReturnToGarden = onReturnToGarden
    }
    @State private var showsCollection = false
    @State private var showsCalendar = false
    @State private var savedItem: GardenCollectionItem?
    @State private var pendingCollectionID: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase

    var body: some View { skyNavigation }

    private var skyNavigation: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    PanoramaView(scene: model.scene, isActive: phase == .active && !showsCollection && !showsCalendar && savedItem == nil && !model.showsVisibleSkyAR && !model.showsStarCamera && model.finderTarget == nil && (!model.showsGarden || model.isGardenTransitioning)) { model.errorMessage = $0 }
                        .accessibilityIdentifier("sky-panorama")
                        .accessibilityLabel("360-degree sky panorama")
                        .accessibilityHint(model.mode == .touch ? "Swipe to look around. Pinch to zoom." : "Move your phone to look around. Pinch to zoom.")
                        .accessibilityValue(String(format:"Zoom %.1f×",72/model.scene.fieldOfView))
                        .accessibilityAdjustableAction { direction in
                            guard model.mode == .touch else { return }
                            model.scene.azimuth += direction == .increment ? .pi / 12 : -.pi / 12
                        }
                        .overlay {
                            GeometryReader { canvas in
                                ZStack {
                                    StarLabelsView(model:model,size:canvas.size,onSelect:model.showDetail)
                                }
                                .opacity(1-min(1,model.gardenProgress*4))
                                .allowsHitTesting(!model.showsGarden)
                                .accessibilityHidden(model.showsGarden)
                            }
                        }
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .gesture(DragGesture().onChanged { model.drag($0.translation, width: geometry.size.width) }.onEnded { _ in model.endDrag() })
                        .simultaneousGesture(MagnifyGesture().onChanged { model.zoom($0.magnification) }.onEnded { _ in model.endZoom() })
                    LinearGradient(colors: [.black.opacity(0.12), .clear, .clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea().allowsHitTesting(false)
                    VStack {
                        HStack {
                            Picker("Viewing mode",selection:Binding(get:{model.mode},set:model.setMode)) {
                                Text("Touch").tag(LookMode.touch)
                                Text("Gyro").tag(LookMode.motion).disabled(!model.motionAvailable)
                            }.pickerStyle(.segmented).frame(width:180)
                            Spacer()
                        }
                        if model.mode == .motion && !model.isMotionCalibrating {
                            HStack(spacing:8) {
                                Text(model.motionStatus).font(.caption).lineLimit(2)
                                Button("Recalibrate",systemImage:"arrow.clockwise") { model.recalibrateMotion() }
                                    .labelStyle(.iconOnly)
                            }
                            .padding(10).background(.regularMaterial,in:Capsule())
                            .frame(maxWidth:.infinity,alignment:.leading)
                        }
                        Spacer()
                        if model.location == nil {
                            Button { model.activeSheet = .observing } label: {
                                Label("Turn on location to see your sky",systemImage:"location.fill")
                                    .font(.footnote).padding().background(.black.opacity(0.6),in:RoundedRectangle(cornerRadius:14))
                            }
                        }
                        if let error = model.errorMessage {
                            Text(error).accessibilityIdentifier("panorama-error").font(.footnote).padding().background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
                        }
                        if model.collected.isEmpty {
                            VStack(spacing:5) {
                                Text("Your sky starts here").font(.headline)
                                Text("Collect your first star and watch this sky grow.")
                                    .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                            }.multilineTextAlignment(.center).padding(.bottom,16)
                        }
                        Button { model.activeSheet = .nearby } label: {
                            HStack(spacing:8) {
                                Label("Visible Now",systemImage:"list.star")
                                if model.location != nil { Text("\(model.predictedVisibleObjects.count)").monospacedDigit().foregroundStyle(.white.opacity(0.65)) }
                            }.font(.subheadline.weight(.medium)).frame(minHeight:44)
                        }.buttonStyle(.plain).accessibilityHint("Stars and planets predicted to be visible from your location")
                        Button { model.openStarCamera() } label: {
                            Label("Start Collecting",systemImage:"camera.viewfinder")
                                .font(.headline).frame(maxWidth:.infinity).padding(.vertical,16)
                        }.buttonStyle(.plain).foregroundStyle(.black).background(.white,in:Capsule())
                        Button { model.activeSheet = .observing } label: {
                            Text(model.currentTimeLabel).font(.caption.monospaced()).foregroundStyle(.white.opacity(0.65))
                                .padding(.vertical,12)
                        }.buttonStyle(.plain)

                    }
                    .padding(.horizontal, 27).padding(.top, 12).padding(.bottom, 8)
                    .opacity(1-min(1,model.gardenProgress*5))
                    .allowsHitTesting(!model.isCameraTransitioning && !model.showsGarden)
                }
                .overlay {
                    if model.mode == .motion && model.isMotionCalibrating {
                        MotionCalibrationView(model:model)
                    }
                }
                .foregroundStyle(.white)
                .preferredColorScheme(.dark)
                .sheet(item:$model.activeSheet,onDismiss:model.handleSheetDismissal) { sheet in
                    HomeSheetView(model:model, sheet:sheet).presentationDetents([.medium,.large]).presentationDragIndicator(.visible)
                }
                .fullScreenCover(item:$model.finderTarget,onDismiss:model.resume) { star in
                    if let location = model.location { SkyFinderView(star:star,location:location,alignment:model.cameraAlignment,catalogue:model.stars) }
                }
                .fullScreenCover(isPresented:$model.showsVisibleSkyAR,onDismiss:model.resume) { VisibleSkyARView(model:model) }
                .fullScreenCover(isPresented:$model.showsStarCamera,onDismiss:model.resume) { StarCameraView(model:model) }
                .sheet(isPresented:$showsCalendar) {
                    NavigationStack {
                        GardenCalendarView().toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { showsCalendar = false } } }
                    }.preferredColorScheme(.dark)
                }
                .sheet(isPresented:$showsCollection,onDismiss:{
                    if let id = pendingCollectionID, let item = model.collectionItems.first(where:{ $0.id == id }) {
                        pendingCollectionID = nil; savedItem = item
                    }
                }) {
                    NavigationStack {
                        GardenCollectionView(model:model) { id in pendingCollectionID = id; showsCollection = false }
                            .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { showsCollection = false } } }
                    }.preferredColorScheme(.dark)
                }
                .sheet(item:$savedItem) { item in SavedStarNoteView(item:item) }
                .onAppear { model.scene.reduceMotion = reduceMotion; model.resume() }
                .onDisappear { model.suspend() }
                .onChange(of:reduceMotion) { _, value in model.scene.reduceMotion = value }
                .onChange(of:phase) { _, value in
                    if value == .active { model.resume() } else { model.suspend() }
                    if value == .background { model.cameraAlignment.enterBackground() }
                }
            }
            .navigationTitle("Your Sky")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for:.navigationBar)
            .toolbar { skyToolbar }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
    }

    @ToolbarContentBuilder
    private var skyToolbar: some ToolbarContent {
        ToolbarItemGroup(placement:.topBarLeading) {
            Button("Reset view", systemImage:"location.north.fill", action:model.reset)
                .disabled(model.isCameraTransitioning)
                .accessibilityIdentifier("reset-sky")
                .accessibilityLabel("Compass. Reset view. \(String(format:"%.0f",model.heading)) degrees")
        }
        ToolbarItemGroup(placement:.topBarTrailing) {
            Button("Collection",systemImage:"books.vertical") { showsCollection = true }
            Button("Upcoming Events",systemImage:"calendar") { showsCalendar = true }
            Button("Sky settings",systemImage:"slider.horizontal.3") { model.activeSheet = .observing }
        }
    }
}

private struct HUDGlass: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(colors:[.white.opacity(0.09),.black.opacity(0.18),.white.opacity(0.04)],startPoint:.topLeading,endPoint:.bottomTrailing)
        }
    }
}
private struct HUDButton: View {
    let symbol: String
    let label: String
    var selected = false
    let action: () -> Void
    var body: some View {
        Button(action:action) { Image(systemName:symbol).font(.system(size:24,weight:.light)).frame(width:46,height:46)
            .background { HUDGlass().clipShape(Circle()) }.overlay(Circle().strokeBorder(.white.opacity(selected ? 0.65:0.18))) }
            .buttonStyle(.plain).accessibilityLabel(label).padding(.bottom,23)
    }
}
private struct DotHandle: View {
    var body: some View {
        Canvas { context,_ in
            for row in 0..<4 { for col in 0...row {
                let rect = CGRect(x:10+Double(col)*5-Double(row)*2.5,y:Double(row)*5,width:2.5,height:2.5)
                context.fill(Path(ellipseIn:rect),with:.color(.white.opacity(0.45)))
            } }
        }
    }
}
private struct DockShape: Shape {
    func path(in rect:CGRect) -> Path {
        var p=Path()
        p.move(to:CGPoint(x:0,y:rect.maxY)); p.addLine(to:CGPoint(x:20,y:18))
        p.addQuadCurve(to:CGPoint(x:43,y:0),control:CGPoint(x:25,y:0))
        p.addLine(to:CGPoint(x:rect.maxX-43,y:0))
        p.addQuadCurve(to:CGPoint(x:rect.maxX-20,y:18),control:CGPoint(x:rect.maxX-25,y:0))
        p.addLine(to:CGPoint(x:rect.maxX,y:rect.maxY)); p.closeSubpath(); return p
    }
}


#Preview("Home") {
    HomeView(model:HomeViewModel.preview())
}

#Preview("HUD Glass", traits: .sizeThatFitsLayout) {
    HUDGlass()
        .clipShape(Capsule())
        .frame(width: 110, height: 46)
        .padding()
        .background(Color.indigo.opacity(0.4))
        .preferredColorScheme(.dark)
}

#Preview("HUD Button", traits: .sizeThatFitsLayout) {
    HStack(spacing: 24) {
        HUDButton(symbol: "camera.aperture", label: "Mode melihat") {}
        HUDButton(symbol: "sparkles", label: "Garis rasi", selected: true) {}
    }
    .foregroundStyle(.white)
    .padding()
    .background(Color.black)
    .preferredColorScheme(.dark)
}

#Preview("Dot Handle", traits: .sizeThatFitsLayout) {
    DotHandle()
        .frame(width: 22, height: 20)
        .padding()
        .background(Color.black)
}

#Preview("Dock Shape", traits: .sizeThatFitsLayout) {
    DockShape()
        .fill(.gray.gradient)
        .frame(width: 210, height: 84)
        .padding()
        .background(Color.black)
}
