import Foundation

/// Detection is quick; identification needs an unambiguous pattern, with a bounded loading state.
struct CameraAutomaticMappingProgress {
    private var startedAt: TimeInterval?
    private(set) var lightCount = 0
    private(set) var isSearching = true
    private var canTrySparseMatch = false
    private var immediateMatchRequested = false
    mutating func update(at time: TimeInterval, lightCount: Int) {
        if startedAt == nil { startedAt = time }
        self.lightCount = lightCount
        let elapsed = time - (startedAt ?? time)
        isSearching = elapsed < 8
        canTrySparseMatch = immediateMatchRequested || elapsed >= 2
    }
    mutating func requestImmediateMatch() {
        immediateMatchRequested = true
        canTrySparseMatch = true
    }
    func canEstimate(headingAccuracy: Double?) -> Bool {
        guard canTrySparseMatch, lightCount > 0, let headingAccuracy else { return false }
        return headingAccuracy.isFinite && headingAccuracy >= 0 && headingAccuracy <= 25
    }
    var message: String {
        if isSearching {
            return lightCount > 0
                ? "Light detected. Matching the surrounding stars…"
                : "Hold steady while the camera looks for starlight…"
        }
        if lightCount < SkyPatternMatcher.minimumAutomaticPatternStars {
            return "Checking the light’s direction. Hold steady."
        }
        return "No clear star pattern yet. Scanning continues automatically."
    }
}
