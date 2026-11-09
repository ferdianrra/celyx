import CoreGraphics
import Foundation

/// Keep a captured frame through hand shake, without locking the next scan to that target.
nonisolated enum CameraTargetSelection {
    @MainActor static func captureEvidence(
        for starID: Int, live: CameraStarAnnotation?, retained: CameraStarAnnotation?
    ) -> CameraStarAnnotation? {
        if let live, live.id == starID { return live }
        if let retained, retained.id == starID { return retained }
        return nil
    }
    /// A continuously visible single point should not acquire a new optical ID just
    /// because its compass-derived world projection shifted between adjacent frames.
    static func continuesSingleSource(previousPoint: CGPoint?, point: CGPoint, gap: TimeInterval) -> Bool {
        guard gap >= 0, gap <= 0.25, let previousPoint else { return false }
        return hypot(point.x - previousPoint.x, point.y - previousPoint.y) <= 12
    }
    static func keepsRetainedTarget(at point: CGPoint?, center: CGPoint) -> Bool {
        guard let point else { return false }
        return hypot(point.x - center.x, point.y - center.y) <= 96
    }
    static func beginsNewSource(
        previousPoint: CGPoint?, newPoint: CGPoint, center: CGPoint, observations: Int
    ) -> Bool {
        guard observations >= 3, hypot(newPoint.x - center.x, newPoint.y - center.y) <= 28 else {
            return false
        }
        guard let previousPoint else { return true }
        return hypot(previousPoint.x - center.x, previousPoint.y - center.y) > 44
    }
}
