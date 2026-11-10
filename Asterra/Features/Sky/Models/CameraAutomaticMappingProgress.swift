import Foundation

/// Detection is quick; identification needs an unambiguous pattern, with a bounded loading state.
struct CameraAutomaticMappingProgress {
    private var startedAt: TimeInterval?
    private(set) var lightCount = 0
    private(set) var isSearching = true
    mutating func update(at time: TimeInterval, lightCount: Int) {
        if startedAt == nil { startedAt = time }
        self.lightCount = lightCount
        let elapsed = time - (startedAt ?? time)
        isSearching = elapsed < 8
    }
    var message: String {
        if isSearching {
            return lightCount > 0
                ? "Light detected. Matching the surrounding stars…"
                : "Hold steady while the camera looks for starlight…"
        }
        if lightCount < SkyPatternMatcher.minimumAutomaticPatternStars {
            return "One light is enough to check a name. Hold steady, or choose an object you recognize."
        }
        return "No clear star pattern yet. Scanning continues automatically."
    }
}
