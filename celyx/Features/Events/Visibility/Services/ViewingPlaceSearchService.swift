import MapKit

struct ViewingPlace: Identifiable {
    let name: String
    let coordinate: ViewingCoordinate
    var id: String { name+coordinate.label }
}
@MainActor
struct ViewingPlaceSearchService {
    func search(_ query: String) async throws -> [ViewingPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .address
        let response = try await MKLocalSearch(request:request).start()
        try Task.checkCancellation()
        return response.mapItems.compactMap { item in
            let coordinate = item.location.coordinate
            let point = ViewingCoordinate(latitude:coordinate.latitude,longitude:coordinate.longitude)
            guard point.isValid, let name = item.name else { return nil }
            return ViewingPlace(name:name,coordinate:point)
        }
    }
}
