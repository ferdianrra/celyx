import CoreGraphics
import Foundation

nonisolated enum CameraExposureGesture {
    /// One upward swipe brightens the capture; one downward swipe darkens it.
    static func isVerticalDrag(_ translation: CGPoint) -> Bool {
        abs(translation.y) >= 6 && abs(translation.y) > abs(translation.x)
    }
    static func value(
        start: Double, translation: Double, viewportHeight: Double,
        minimum: Double, maximum: Double
    ) -> Double {
        guard start.isFinite, translation.isFinite, viewportHeight.isFinite,
            minimum.isFinite, maximum.isFinite, maximum > minimum
        else { return start }
        let travel = max(160, viewportHeight * 0.35)
        return min(maximum, max(minimum, start - translation / travel * (maximum - minimum)))
    }
    static func value(at position: Double, height: Double, minimum: Double, maximum: Double) -> Double {
        guard position.isFinite, height.isFinite, height > 0, maximum > minimum else { return minimum }
        let fraction = min(1, max(0, 1 - position / height))
        return minimum + fraction * (maximum - minimum)
    }
}

/// Visibility follows interaction, independently of camera/session timestamps.
nonisolated struct CameraExposurePresentation: Sendable {
    private(set) var isEditing = false
    private var deadline: TimeInterval = 0
    mutating func begin() { isEditing = true }
    mutating func end(at uptime: TimeInterval) {
        isEditing = false
        deadline = uptime + 1.3
    }
    mutating func reset() { self = Self() }
    func isVisible(at uptime: TimeInterval) -> Bool { isEditing || uptime < deadline }
}
