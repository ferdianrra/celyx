import SwiftUI

/// Visible Now filters are independent of the calibration candidate catalog.
struct FilteredStarsView: View {
    @Bindable var model: HomeViewModel
    @State private var query = ""
    @State private var selectedID: Int?
    @State private var showsAR = false
    @State private var showsCalibrationCatalog = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase

    private var results: [StarObservation] {
        model.predictedVisibleObjects.filter { query.isEmpty || $0.star.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                VStack(alignment:.leading,spacing:12) {
                    Text("Visible Now").font(.system(size:22,weight:.bold))
                    Text("Stars and planets predicted from your time, location and filters. This is separate from Calibration Stars and your collection.")
                        .font(.system(size:13)).foregroundStyle(CelyxColor.secondaryLabel)
                    Text("\(model.phaseTitle) · \(model.location?.coordinateLabel ?? "Waiting for location")\n\(model.currentTimeLabel)")
                        .font(.system(size:12)).foregroundStyle(CelyxColor.secondaryLabel)
                    CelyxPillButton(title:"View filtered stars in AR",systemImage:"camera.viewfinder",
                        style:model.location == nil || model.predictedVisibleObjects.isEmpty ? .disabled : .primary) {
                            selectedID = nil; showsAR = true
                        }
                    if model.location == nil {
                        Button("Use my location") { model.requestLocation() }
                    }
                    Button("Open Calibration Stars · separate catalog") { showsCalibrationCatalog = true }
                        .font(.system(size:13,weight:.semibold))
                }
                filters
                catalog
            }.padding(20)
        }
        .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge:.top,spacing:0) { header }
        .background(CelyxScreenWash()).foregroundStyle(CelyxColor.primaryLabel).preferredColorScheme(.dark)
        .fullScreenCover(isPresented:$showsAR) { FilteredSkyARView(model:model,selectedID:selectedID) }
        .fullScreenCover(isPresented:$showsCalibrationCatalog) {
            SkyCalibrationView(catalogue:model.stars,alignment:model.cameraAlignment,
                opensCatalog:true,initialLocation:model.location) { showsCalibrationCatalog = false }
        }
        .task {
            guard !AppPreviewData.isRunning else { return }
            model.resume()
        }
        .onDisappear { model.suspend() }
        .onChange(of:phase) { _, value in
            if value == .active, !showsAR, !showsCalibrationCatalog, !AppPreviewData.isRunning { model.resume() }
            else { model.suspend() }
        }
    }

    private var header: some View {
        HStack {
            CelyxBackButton { dismiss() }
            Spacer()
            Text("Filtered Stars").font(.system(size:20)).tracking(-0.45)
            Spacer()
            Color.clear.frame(width:48,height:48)
        }.padding(.horizontal,20).padding(.vertical,12)
    }

    private var filters: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Visibility filters").font(.system(size:15,weight:.semibold)).foregroundStyle(CelyxColor.secondaryLabel)
            VStack(spacing:16) {
                Picker("Nearby light",selection:$model.quality) {
                    ForEach(SkyQuality.allCases) { Text($0.rawValue).tag($0) }
                }.tint(CelyxColor.primaryLabel)
                filterToggle("Use live weather",isOn:$model.onlineConditions)
                Divider()
                filterToggle("Daylight",isOn:$model.visibilityFilters.daylight)
                filterToggle("Horizon",isOn:$model.visibilityFilters.horizon)
                filterToggle("Brightness limit",isOn:$model.visibilityFilters.brightness)
                filterToggle("Light pollution",isOn:$model.visibilityFilters.lightPollution)
                filterToggle("Moonlight",isOn:$model.visibilityFilters.moonlight)
                filterToggle("Cloud cover",isOn:$model.visibilityFilters.clouds)
                filterToggle("Atmospheric dimming",isOn:$model.visibilityFilters.atmosphericExtinction)
                if model.visibilityFilters.isModified {
                    Button("Reset filters") { model.visibilityFilters = VisibilityFilters() }
                        .font(.system(size:13,weight:.semibold))
                }
            }.padding(16).background(CelyxInfoBox())
            Text("Turn a filter off to ignore that parameter in this list and its AR map. Turn Daylight off to test during the day. Positions remain predictions, not camera detections.")
                .font(.system(size:12)).foregroundStyle(CelyxColor.secondaryLabel)
            if let message = model.atmosphere.weatherError, model.onlineConditions {
                Text(message).font(.system(size:12)).foregroundStyle(CelyxColor.secondaryLabel)
            }
        }
    }

    private func filterToggle(_ title: String,isOn: Binding<Bool>) -> some View {
        Toggle(isOn:isOn) {
            HStack(spacing:12) {
                Text(title).fixedSize(horizontal:false,vertical:true)
                Spacer(minLength:0)
                Text(isOn.wrappedValue ? "On" : "Off").foregroundStyle(CelyxColor.secondaryLabel)
            }.font(.system(size:15))
        }.tint(CelyxColor.ready).accessibilityLabel(title)
    }

    private var catalog: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Stars & planets · \(results.count)")
                .font(.system(size:15,weight:.semibold)).foregroundStyle(CelyxColor.secondaryLabel)
            HStack(spacing:10) {
                Image(systemName:"magnifyingglass").foregroundStyle(CelyxColor.secondaryLabel)
                TextField("Search filtered stars",text:$query).autocorrectionDisabled()
            }.font(.system(size:15)).padding(14).background(CelyxInfoBox())
            if results.isEmpty {
                Text(query.isEmpty ? model.visibleObjectsEmptyMessage : "No stars match your search.")
                    .font(.system(size:15)).foregroundStyle(CelyxColor.secondaryLabel)
                    .frame(maxWidth:.infinity).multilineTextAlignment(.center).padding(.vertical,24)
            } else {
                LazyVStack(spacing:12) {
                    ForEach(results) { item in
                        Button { selectedID = item.id; showsAR = true } label: {
                            HStack(spacing:14) {
                                StarPortraitView(star:item.star).frame(width:44,height:44)
                                VStack(alignment:.leading,spacing:4) {
                                    Text(item.star.title).font(.system(size:17,weight:.semibold))
                                    Text(String(format:"%.1f mag · %.0f° up · %@",item.star.mag,item.altitude,item.bearing))
                                        .font(.system(size:12)).foregroundStyle(CelyxColor.secondaryLabel)
                                }
                                Spacer(minLength:8)
                                Image(systemName:"camera.viewfinder").foregroundStyle(CelyxColor.secondaryLabel)
                            }.padding(14).background(CelyxInfoBox()).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityHint("Find this object in the filtered AR map")
                    }
                }
            }
        }
    }
}

#Preview("Filtered stars") {
    FilteredStarsView(model:AppPreviewData.model)
}

#Preview("Filtered stars · custom filters") {
    let model = AppPreviewData.model
    model.visibilityFilters.daylight = false
    return FilteredStarsView(model:model)
}
