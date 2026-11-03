//
//  HomeView.swift
//  celyx
//
//  Created by Ferdiansyah Annora on 02/11/26.
//

import SwiftUI

struct HomeView: View {
    @State private var model: HomeViewModel
    @MainActor init() { _model = State(initialValue:HomeViewModel()) }
    init(model: HomeViewModel) { _model = State(initialValue:model) }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase

    var body: some View {
        skyNavigation
            .overlay {
                if model.showsGarden {
                    GardenView(model:model,onClose:model.closeGarden)
                        .opacity(reduceMotion ? model.gardenProgress : min(1,max(0,(model.gardenProgress-0.22)/0.12)))
                        .disabled(model.isGardenTransitioning)
                }
            }
            .onChange(of:model.showsGarden) { _, visible in
                if !visible && phase == .active { model.resume() }
            }
    }

    private var skyNavigation: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    PanoramaView(scene: model.scene, isActive: phase == .active && !model.showsStarCamera && model.finderTarget == nil && (!model.showsGarden || model.isGardenTransitioning)) { model.errorMessage = $0 }
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
                                    ConstellationFiguresView(model:model,size:canvas.size)
                                    StarLabelsView(model:model,size:canvas.size)
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
                            Picker("Mode melihat",selection:Binding(get:{model.mode},set:model.setMode)) {
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
                        HStack(alignment: .bottom) {
                            HUDButton(symbol:"camera.viewfinder", label:"Sky Camera") { model.openStarCamera() }
                            Spacer(minLength: 12)
                            Button { model.activeSheet = .observing } label: {
                                VStack(spacing: 15) {
                                    DotHandle().frame(width: 22,height: 20)
                                    VStack(spacing: 5) {
                                        Text(model.locationTitle).font(.system(size: 16, weight: .semibold))
                                        Text(model.currentTimeLabel).font(.system(size: 11, design: .monospaced)).tracking(1.2).foregroundStyle(.white.opacity(0.55))
                                    }
                                    .frame(maxWidth: .infinity).padding(.top,18).padding(.bottom,23)
                                    .background { HUDGlass().clipShape(DockShape()) }
                                    .overlay(DockShape().stroke(.white.opacity(0.13),lineWidth:1))
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: 210)
                            .accessibilityLabel("\(model.locationTitle), \(model.currentTimeLabel). Sky settings")
                            Spacer(minLength:12)
                            HUDButton(symbol:"sparkles", label:"Your Galaxy") { model.openGarden() }
                        }
                    }
                    .padding(.horizontal, 27).padding(.top, 12).padding(.bottom, -geometry.safeAreaInsets.bottom)
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
                    HomeSheetView(model:model, sheet:sheet).presentationDetents(sheet == .detail ? [.height(310),.large] : [.medium,.large]).presentationDragIndicator(.visible)
                }
                .fullScreenCover(item:$model.finderTarget,onDismiss:model.resume) { star in
                    if let location = model.location { SkyFinderView(star:star,location:location) }
                }
                .fullScreenCover(isPresented:$model.showsStarCamera,onDismiss:model.resume) { StarCameraView(model:model) }
                .onAppear { model.scene.reduceMotion = reduceMotion; model.resume() }
                .onDisappear { model.suspend() }
                .onChange(of:reduceMotion) { _, value in model.scene.reduceMotion = value }
                .onChange(of:phase) { _, value in if value == .active { model.resume() } else { model.suspend() } }
            }
            .navigationTitle("Sky")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for:.navigationBar)
            .toolbar { skyToolbar }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
    }

    @ToolbarContentBuilder
    private var skyToolbar: some ToolbarContent {
        ToolbarItem(placement:.topBarLeading) {
            Button("Reset view", systemImage:"location.north.fill", action:model.reset)
                .disabled(model.isCameraTransitioning)
                .accessibilityIdentifier("reset-sky")
                .accessibilityLabel("Compass. Reset view. \(String(format:"%.0f",model.heading)) degrees")
        }
        ToolbarItemGroup(placement:.topBarTrailing) {
            Button("What’s up tonight", systemImage:"list.bullet") { model.activeSheet = .nearby }.disabled(model.isCameraTransitioning)
            Button("Sky layers", systemImage:"square.3.layers.3d") { model.activeSheet = .layers }.disabled(model.isCameraTransitioning)
            Button("Find a star", systemImage:"magnifyingglass") { model.activeSheet = .search }.disabled(model.isCameraTransitioning)
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
