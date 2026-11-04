import Foundation
import Observation

@MainActor @Observable
final class EventVisibilityViewModel {
    private(set) var plan: EventViewingPlan?
    private(set) var raster: VisibilityRaster?
    private(set) var isLoading = false
    private(set) var selectedCoordinate: ViewingCoordinate?
    private(set) var selectedName = "Selected point"
    private(set) var assessment: ViewingAssessment?
    private(set) var locationAccuracy: Double?
    @ObservationIgnored private var searchID = UUID()
    private(set) var locationMessage: String?
    private(set) var places: [ViewingPlace] = []
    private(set) var isSearching = false
    private(set) var searchMessage: String?
    @ObservationIgnored private let placeSearch = ViewingPlaceSearchService()
    @ObservationIgnored private let engine: any EventVisibilityPreparing
    @ObservationIgnored private let location: LocationService
    @ObservationIgnored private var rasterTask: Task<VisibilityRaster,Error>?

    init(engine: (any EventVisibilityPreparing)? = nil,location: LocationService? = nil) {
        self.engine = engine ?? EventVisibilityEngine(); self.location = location ?? LocationService()
    }
    func load(event: AstronomyEvent) async {
        if plan == nil { plan = engine.prepare(event) }
        guard raster == nil, !isLoading, case .geometry(let geometry) = plan else { return }
        isLoading = true
        defer { isLoading = false }
        let task = Task.detached(priority:.userInitiated) { try VisibilityRasterizer.render(geometry) }
        rasterTask = task
        do {
            let value = try await withTaskCancellationHandler(operation:{ try await task.value },onCancel:{ task.cancel() })
            try Task.checkCancellation()
            raster = value
        } catch { if !Task.isCancelled { locationMessage = "The map overlay couldn’t be prepared. You can still check an exact point." } }
        rasterTask = nil
    }
    func select(_ coordinate: ViewingCoordinate,name: String = "Selected point") {
        guard coordinate.isValid else { return }
        selectedCoordinate = coordinate; selectedName = name; locationAccuracy = nil
        if case .geometry(let geometry) = plan { assessment = geometry.assessment(at:coordinate) }
    }
    func useCurrentLocation() {
        locationMessage = "Finding your location…"
        location.onStatus = { [weak self] in self?.locationMessage = $0 }
        location.onLocation = { [weak self] fix in
            guard let self else { return }
            self.location.stop(); self.locationMessage = nil
            self.select(.init(latitude:fix.latitude,longitude:fix.longitude),name:"Your location")
            self.locationAccuracy = fix.accuracy
        }
        location.start()
    }
    func search(_ query: String) async {
        guard !query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { places = []; return }
        let requestID = UUID(); searchID = requestID
        isSearching = true; searchMessage = nil
        defer { if searchID == requestID { isSearching = false } }
        do {
            let result = try await placeSearch.search(query)
            guard searchID == requestID else { return }
            places = result
            if places.isEmpty { searchMessage = "No places found. Try a city or a more specific name." }
        } catch { if !Task.isCancelled && searchID == requestID { searchMessage = "Place search isn’t available. You can still tap anywhere on the map." } }
    }
    func choose(_ place: ViewingPlace) { select(place.coordinate,name:place.name); places = [] }
    func stopLocation() { location.stop() }
}
