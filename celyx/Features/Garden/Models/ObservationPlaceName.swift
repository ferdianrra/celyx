import MapKit

/// Resolve the coordinates saved with the photograph, never the phone's current
/// location. Persist successful lookups so old albums also work offline.
@MainActor final class ObservationPlaceName {
    static let shared = ObservationPlaceName()
    private let defaults: UserDefaults
    private var requests: [String:Task<String?,Never>] = [:]
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func key(latitude: Double,longitude: Double) -> String {
        String(format:"observationCity.v1.%.4f,%.4f",locale:Locale(identifier:"en_US_POSIX"),latitude,longitude)
    }
    func cached(latitude: Double,longitude: Double) -> String? {
        defaults.string(forKey:key(latitude:latitude,longitude:longitude))
    }
    func resolve(latitude: Double,longitude: Double) async -> String? {
        guard CLLocationCoordinate2DIsValid(.init(latitude:latitude,longitude:longitude)) else { return nil }
        let key = key(latitude:latitude,longitude:longitude)
        if let name = defaults.string(forKey:key) { return name }
        if let existing = requests[key] { return await existing.value }
        let task = Task { @MainActor () -> String? in
            guard let request = MKReverseGeocodingRequest(location:CLLocation(latitude:latitude,longitude:longitude)) else { return nil }
            return await withCheckedContinuation { continuation in
                var completed = false
                let timeout = Task { @MainActor in
                    try? await Task.sleep(for:.seconds(8))
                    guard !completed else { return }
                    completed = true; request.cancel(); continuation.resume(returning:nil)
                }
                request.getMapItems { items,_ in
                    guard !completed else { return }
                    completed = true; timeout.cancel()
                    let address = items?.first?.addressRepresentations
                    let name = Self.readableName(city:address?.cityWithContext(.short) ?? address?.cityName,
                                                 region:address?.regionName)
                    continuation.resume(returning:name)
                }
            }
        }
        requests[key] = task
        let name = await task.value
        requests[key] = nil
        if let name { defaults.set(name,forKey:key) }
        return name
    }
    static func readableName(city: String?,region: String?) -> String? {
        for candidate in [city,region] {
            if let name = candidate?.trimmingCharacters(in:.whitespacesAndNewlines), !name.isEmpty { return name }
        }
        return nil
    }
}
