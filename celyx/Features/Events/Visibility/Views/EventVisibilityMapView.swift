import SwiftUI
import MapKit

struct EventVisibilityMapView: View {
    let event: AstronomyEvent
    let model: EventVisibilityViewModel
    @State private var query = ""
    @State private var focus: ViewingCoordinate?
    @Environment(\.dismiss) private var dismiss
    private var geometry: EventVisibilityGeometry? {
        if case .geometry(let value) = model.plan { return value }; return nil
    }
    private var greatest: ViewingCoordinate? {
        if case .greatestEclipse(_,let point) = model.plan { return point }; return nil
    }
    var body: some View {
        NavigationStack {
            VStack(spacing:0) {
                if geometry != nil {
                    HStack(spacing:12) {
                        TextField("Search a city or area",text:$query).submitLabel(.search)
                            .onSubmit { Task { await model.search(query) } }
                        if model.isSearching { ProgressView() }
                        else { Button("Search",systemImage:"magnifyingglass") { Task { await model.search(query) } }.labelStyle(.iconOnly) }
                    }.padding(14).background(.white.opacity(0.06))
                    if let message = model.searchMessage { Text(message).font(.caption).foregroundStyle(.secondary).padding(8) }
                    if !model.places.isEmpty {
                        ScrollView {
                            VStack(alignment:.leading,spacing:0) {
                                ForEach(model.places) { place in
                                    Button {
                                        focus = place.coordinate; model.choose(place)
                                    } label: { Label(place.name,systemImage:"mappin").frame(maxWidth:.infinity,alignment:.leading).padding(12) }
                                    Divider()
                                }
                            }
                        }.frame(maxHeight:145)
                    }
                }
                ZStack(alignment:.bottomTrailing) {
                    VisibilityMapCanvas(raster:model.raster,selected:model.selectedCoordinate,selectedName:model.selectedName,
                        greatest:greatest,focus:focus) { point in if geometry != nil { model.select(point) } }
                    if geometry != nil {
                        Button { model.useCurrentLocation() } label: { Image(systemName:"location.fill").padding(14).background(.regularMaterial,in:Circle()) }
                            .accessibilityLabel("Check my location").padding(14)
                    }
                    if model.isLoading { ProgressView().padding(12).background(.regularMaterial,in:Capsule()).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top) }
                }.frame(minHeight:230)
                ScrollView {
                    VStack(alignment:.leading,spacing:12) {
                        Text(event.cardTitle).font(.headline)
                        Text(event.time.formatted(.dateTime.month(.abbreviated).day().hour().minute())+" · "+(TimeZone.current.abbreviation(for:event.time) ?? TimeZone.current.identifier))
                            .font(.caption).foregroundStyle(.secondary)
                        if let geometry {
                            Label("Green: \(geometry.criteria)",systemImage:"square.fill").font(.caption).foregroundStyle(.green)
                            if let assessment = model.assessment {
                                Text(model.selectedName).font(.subheadline.weight(.semibold))
                                if let accuracy = model.locationAccuracy {
                                    Text(String(format:"Location accuracy ±%.0f m",accuracy)).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(assessment.meetsGeometry ? "Sky geometry fits at this time" : "Sky geometry doesn’t fit at this time")
                                    .font(.subheadline).foregroundStyle(assessment.meetsGeometry ? .green : .orange)
                                Text(String(format:"Target %.1f° · Sun %.1f°",assessment.targetAltitude,assessment.sunAltitude)).font(.caption.monospacedDigit())
                                if let note = geometry.equipmentNote { Text(note).font(.caption).foregroundStyle(.orange) }
                                Button("Open This Point in Apple Maps",systemImage:"arrow.up.right") {
                                    let item = MKMapItem(location:CLLocation(latitude:assessment.coordinate.latitude,longitude:assessment.coordinate.longitude),address:nil)
                                    item.name = model.selectedName; item.openInMaps()
                                }.font(.footnote)
                            } else { Text("Tap the map or search for a place to check its exact coordinates.").font(.subheadline) }
                            DisclosureGroup("How this area is calculated") {
                                VStack(alignment:.leading,spacing:8) {
                                    Text(geometry.source)
                                    Text("The shaded global overview is sampled on a 768-pixel Web Mercator grid. Readings at the selected point are recalculated directly, rather than read from a map pixel.")
                                    Text("The calculation includes Earth rotation, precession/nutation and topocentric parallax at sea level. It uses geometric altitude, without atmospheric refraction. All targets must meet the stated altitude and darkness thresholds at the event’s published time.")
                                    Text("This is a single-time observing geometry map, not an eclipse path, a weather forecast or a verified observing site. Local obstructions, light pollution, clouds and viewing equipment are not modeled.")
                                    Link("Astronomy Engine",destination:URL(string:"https://github.com/cosinekitty/astronomy")!)
                                    Link("SpaceCatalog event coordinate frame",destination:URL(string:"https://spacecatalog.org/api#events")!)
                                }.font(.caption).foregroundStyle(.secondary).padding(.top,8)
                            }.font(.footnote)
                        } else if let greatest {
                            Text("Point of greatest eclipse supplied by SpaceCatalog: \(greatest.label)").font(.subheadline)
                            Text("No footprint or visibility radius is drawn. Use a published eclipse map to plan an observing trip.").font(.caption).foregroundStyle(.secondary)
                            Link("NASA eclipse maps",destination:URL(string:"https://eclipse.gsfc.nasa.gov/solar.html")!)
                        }
                        if let message = model.locationMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(18)
                }.frame(maxHeight:300)
            }
            .background(Color(white:0.06))
            .navigationTitle("Viewing Map").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear { if let greatest { focus = greatest } }
        .onChange(of:model.selectedCoordinate) { _, point in if model.selectedName == "Your location" { focus = point } }
        .onDisappear { model.stopLocation() }
        .preferredColorScheme(.dark).tint(.white)
    }
}
