//
//  HomeSheetView.swift
//  celyx
//
//  Created by Ferdiansyah Annora on 02/11/26.
//
import SwiftUI

struct HomeSheetView: View {
    @Bindable var model: HomeViewModel
    let sheet: HomeSheet
    var body: some View {
        if sheet == .detail { StarDetailView(model:model) }
        else {
            NavigationStack {
                Group {
                    switch sheet {
                    case .search:
                        List(model.results) { star in
                            Button { model.showDetail(star) } label: { starRow(star,observation:star.isSun ? model.sunObservation : star.isMoon ? model.moonObservation : star.isPlanet ? model.planetObservations.first { $0.id == star.id } : model.observations.first { $0.id == star.id }) }.tint(.primary)
                        }
                        .searchable(text:$model.query,prompt:"Stars, Sun or Moon")
                        .overlay { if model.results.isEmpty { ContentUnavailableView.search(text:model.query) } }
                    case .nearby:
                        List {
                            Section {
                                Text("\(model.phaseTitle) · \(model.location?.coordinateLabel ?? "No location yet")\n\(model.currentTimeLabel)")
                                    .font(.footnote).foregroundStyle(.secondary)
                                Text("Stars and planets that may be visible from your location right now, with the brightest first. You don’t need to have collected them.")
                                    .font(.subheadline)
                                Button { model.openVisibleSkyAR() } label: {
                                    Label("View in AR",systemImage:"camera.viewfinder").frame(maxWidth:.infinity).padding(.vertical,6)
                                }.buttonStyle(.borderedProminent)
                                    .tint(.cyan)
                                    .foregroundStyle(model.location != nil && !model.predictedVisibleObjects.isEmpty ? Color.black : Color.white.opacity(0.65))
                                    .disabled(model.location == nil || model.predictedVisibleObjects.isEmpty)
                                Text("See the filtered objects over your camera. Markers show expected positions, not camera detections.")
                                    .font(.caption).foregroundStyle(.secondary)
                                Picker("Nearby light",selection:$model.quality) {
                                    ForEach(SkyQuality.allCases) { Text($0.rawValue).tag($0) }
                                }
                                Toggle("Use live weather",isOn:$model.onlineConditions).tint(.green)
                                if model.isLoadingAtmosphere { ProgressView("Checking the weather…") }
                                if let date = model.atmosphere.weatherDate, model.onlineConditions {
                                    Text("Cloud forecast: \(date.formatted(date:.abbreviated,time:.shortened))")
                                        .font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text("No cloud forecast loaded. This estimate uses a standard atmosphere.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                if let error = model.atmosphere.weatherError, model.onlineConditions {
                                    Text(error).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            VisibilityFilterSection(model:model)
                            Section("Stars & planets · \(model.predictedVisibleObjects.count)") {
                                if model.predictedVisibleObjects.isEmpty {
                                    ContentUnavailableView("No objects predicted right now",systemImage:"moon.stars",
                                        description:Text(model.visibleObjectsEmptyMessage))
                                }
                                ForEach(model.predictedVisibleObjects) { observation in
                                    Button { model.showDetail(observation.star) } label: {
                                        starRow(observation.star,observation:observation)
                                    }.tint(.primary)
                                }
                            }
                            Section {
                                Text("This uses the time, your location, brightness, moonlight and your selected surroundings. Buildings, trees and nearby lights can still hide a star. Tap one for details and camera directions.")
                                    .font(.caption).foregroundStyle(.secondary)
                                if model.location == nil { Button("Use my location") { model.requestLocation() } }
                            }
                        }
                    case .layers:
                        Form {
                            Section("Sky") {
                                Toggle("Milky Way",isOn:$model.scene.showsMilkyWay)
                                Toggle("Stars",isOn:$model.scene.showsStars)
                                Toggle("Coordinate grid",isOn:$model.scene.showsGrid)
                                Toggle("Constellation lines",isOn:$model.scene.showsConstellations)
                                Toggle("Constellation art",isOn:$model.scene.showsConstellationFigures)
                                Text("Constellation art appears as you look toward it and fades as you look away.").font(.caption).foregroundStyle(.secondary)
                            }
                            Section("Credits") {
                                Text("Star catalog: HYG v3.8 · CC BY-SA 4.0\nSun, Moon & sky positions: Astronomy Engine / Don Cross · MIT\nConstellation lines: d3-celestial © 2015 Olaf Frohn · BSD 3-Clause\nConstellation art: Stellarium / Johan Meuris · Free Art License 1.3\nConstellation metadata: Stellarium · CC BY-SA 4.0").font(.caption)
                                Text("Weather & air quality: Open-Meteo, Copernicus CAMS · CC BY 4.0. Forecast data, not phone sensors. Star artwork supplied with the project.").font(.caption)
                                Text("Environment & Milky Way: project assets. Boat panorama: project-supplied Gemini image. Source licenses are included with the app.").font(.caption)
                            }.foregroundStyle(.secondary)
                        }
                    case .observing:
                        Form {
                            Section("Here & now") {
                                Text(model.locationStatus).font(.footnote)
                                if let location = model.location {
                                    LabeledContent("Coordinates",value:location.coordinateLabel)
                                    LabeledContent("Source",value:location.isManual ? "Manual" : "GPS")
                                }
                                LabeledContent("Time",value:model.currentTimeLabel)
                                LabeledContent("Sky phase",value:model.phaseTitle)
                                Button("Use my location") { model.requestLocation() }
                                DisclosureGroup("Enter coordinates") {
                                    TextField("Latitude (-90…90)",text:$model.manualLatitude).keyboardType(.numbersAndPunctuation)
                                    TextField("Longitude (-180…180)",text:$model.manualLongitude).keyboardType(.numbersAndPunctuation)
                                    Button("Use coordinates") { model.useManualLocation() }
                                }.disabled(model.mode == .motion)
                            }
                            Section("Seeing conditions") {
                                Button { model.openVisibleSkyAR() } label: {
                                    Label("View in AR",systemImage:"camera.viewfinder").frame(maxWidth:.infinity).padding(.vertical,6)
                                }.buttonStyle(.borderedProminent)
                                    .tint(.cyan)
                                    .foregroundStyle(model.location != nil && !model.predictedVisibleObjects.isEmpty ? Color.black : Color.white.opacity(0.65))
                                    .disabled(model.location == nil || model.predictedVisibleObjects.isEmpty)
                                Text("See the filtered objects over your camera. Markers show expected positions, not camera detections.")
                                    .font(.caption).foregroundStyle(.secondary)
                                Picker("Nearby light",selection:$model.quality) { ForEach(SkyQuality.allCases) { Text($0.rawValue).tag($0) } }
                                Toggle("Use live weather",isOn:$model.onlineConditions).tint(.green)
                                Text("When this is on, we send your coordinates to Open-Meteo for cloud and air-quality forecasts. PM2.5 is shown for context; it doesn’t measure light pollution.").font(.caption).foregroundStyle(.secondary)
                                if model.isLoadingAtmosphere { ProgressView("Checking the weather…") }
                                LabeledContent("Cloud cover",value:model.atmosphere.cloudCover.map { String(format:"%.0f%%",$0) } ?? "Unknown")
                                LabeledContent("AOD 550 nm",value:model.atmosphere.aerosolOpticalDepth.map { String(format:"%.2f",$0) } ?? "Unknown")
                                LabeledContent("PM2.5",value:model.atmosphere.pm25.map { String(format:"%.1f µg/m³",$0) } ?? "Unknown")
                                if let date = model.atmosphere.weatherDate { LabeledContent("Cloud forecast",value:date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute().locale(Locale(identifier:"en")))) }
                                if let date = model.atmosphere.airDate { LabeledContent("Aerosol forecast",value:date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute().locale(Locale(identifier:"en")))) }
                                if let error = model.atmosphere.weatherError { Text(error).font(.caption).foregroundStyle(.orange) }
                                if let error = model.atmosphere.airError { Text(error).font(.caption).foregroundStyle(.orange) }
                                Button("Refresh weather") { model.refreshAtmosphere(force:true) }.disabled(!model.onlineConditions || model.isLoadingAtmosphere)
                                Text("These estimates can’t see buildings, trees, nearby lights, or clouds right in front of a star. If you can see it in the camera, you can still save it.").font(.caption).foregroundStyle(.secondary)
                            }
                            VisibilityFilterSection(model:model)
                            Section("Look around") {
                                Picker("Mode",selection:Binding(get:{model.mode},set:{model.setMode($0)})) {
                                    ForEach(LookMode.allCases) { mode in Text(mode.rawValue).tag(mode).disabled(mode == .motion && !model.motionAvailable) }
                                }.pickerStyle(.segmented)
                                Text(model.motionStatus).font(.footnote).foregroundStyle(.secondary)
                                if model.isMotionCalibrating { ProgressView(value:model.motionCalibrationProgress) }
                                Text("Your compass can be a little off. Recalibrate if the sky doesn’t line up with where you’re pointing.").font(.caption).foregroundStyle(.secondary)
                                Button("Reset view") { model.reset() }
                            }
                            Section("Your collection") {
                                Text("\(model.collected.count) memories saved on this device. Your collection isn’t synced to an account yet.")
                            }
                        }
                    case .detail: EmptyView()
                    }
                }
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { model.activeSheet = nil } } }
            }.preferredColorScheme(.dark).tint(.cyan)
        }
    }
    private var title: String { switch sheet { case .search: "Find a star"; case .nearby: "Visible Now"; case .layers: "Sky layers"; case .observing: "Sky settings"; case .detail: "A closer look" } }
    private func starRow(_ star: CatalogStar,observation: StarObservation?) -> some View {
        HStack(spacing:12) {
            StarPortraitView(star:star,solarAltitude:model.sunObservation?.altitude ?? 60).frame(width:36,height:36)
            VStack(alignment:.leading,spacing:4) {
                Text(star.title).font(.body.weight(.medium))
                if let observation { Text(String(format:"%@ · %.0f° · %@",observation.bearing,observation.altitude,observation.reason)).font(.caption).foregroundStyle(.secondary) }
                else { Text("Turn on location to find its position").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            VStack { Text(String(format:"%.1f mag",star.mag)).font(.caption).foregroundStyle(.secondary)
                if model.collected[star.id] != nil { Image(systemName:"checkmark.circle.fill").foregroundStyle(.green) }
            }
        }
    }
}

#Preview("Search") { HomeSheetView(model:HomeViewModel.preview(),sheet:.search) }
#Preview("Nearby stars") { HomeSheetView(model:HomeViewModel.preview(),sheet:.nearby) }
#Preview("Layers") { HomeSheetView(model:HomeViewModel.preview(),sheet:.layers) }
#Preview("Observing") { HomeSheetView(model:HomeViewModel.preview(),sheet:.observing) }

/// Shared by the nearby list, observing settings and camera sheet.
struct VisibilityFilterSection: View {
    @Bindable var model: HomeViewModel

    var body: some View {
        Section {
            LabeledContent("Stars",value:"\(model.predictedVisibleObjects.filter { !$0.star.isSolarSystemBody }.count)")
            LabeledContent("Planets",value:"\(model.predictedVisibleObjects.filter { $0.star.isPlanet }.count)")
            VisibilityFilterToggle("Daylight",isOn:$model.visibilityFilters.daylight)
            VisibilityFilterToggle("Horizon",isOn:$model.visibilityFilters.horizon)
            VisibilityFilterToggle("Brightness limit",isOn:$model.visibilityFilters.brightness)
            VisibilityFilterToggle("Light pollution",isOn:$model.visibilityFilters.lightPollution)
            VisibilityFilterToggle("Moonlight",isOn:$model.visibilityFilters.moonlight)
            VisibilityFilterToggle("Cloud cover",isOn:$model.visibilityFilters.clouds)
            VisibilityFilterToggle("Atmospheric dimming",isOn:$model.visibilityFilters.atmosphericExtinction)
            if model.visibilityFilters.isModified {
                Button("Reset filters") { model.visibilityFilters = VisibilityFilters() }
            }
        } header: {
            Text("Visibility filters")
        } footer: {
            Text(model.visibilityFilters.isModified
                 ? "Custom filters active. Results simulate the selected conditions. Turn off Daylight to test during the day; positions still use your actual time and location."
                 : "Turn off a parameter to ignore its effect on the nearby list and AR predictions. Turn off Daylight to test during the day.")
        }
    }
}

/// Explicit switch tint stays legible even inside camera views that use white accents.
private struct VisibilityFilterToggle: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String,isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn:$isOn) {
            HStack(spacing:12) {
                Text(title).foregroundStyle(.primary)
                    .fixedSize(horizontal:false,vertical:true)
                Spacer(minLength:0)
                Text(isOn ? "On" : "Off")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
        }
        .tint(.green)
        .accessibilityLabel(title)
    }
}
