import CoreGraphics
import Foundation

/// Keep a captured frame through hand shake, without locking the next scan to that target.
nonisolated enum CameraTargetSelection {
    /// Presentation starts near the visible reticle; optical discovery remains wider.
    static let reticleEntryRadius: CGFloat = 28
    static func canAcquireInReticle(at point: CGPoint, center: CGPoint) -> Bool {
        let distance = hypot(point.x - center.x, point.y - center.y)
        return distance.isFinite && distance <= reticleEntryRadius
    }

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
        guard gap >= 0, gap <= CameraTrackingPolicy.trackGap, let previousPoint else { return false }
        return hypot(point.x - previousPoint.x, point.y - previousPoint.y) <= 32
    }
    static func keepsRetainedTarget(at point: CGPoint?, center: CGPoint) -> Bool {
        guard let point else { return false }
        return hypot(point.x - center.x, point.y - center.y) <= CameraTrackingPolicy.holdRadius
    }
    static func beginsNewSource(
        previousPoint: CGPoint?, newPoint: CGPoint, center: CGPoint, observations: Int
    ) -> Bool {
        guard observations >= 3, hypot(newPoint.x - center.x, newPoint.y - center.y) <= CameraTrackingPolicy.sourceSwitchRadius else {
            return false
        }
        guard let previousPoint else { return true }
        let previousDistance = hypot(previousPoint.x - center.x, previousPoint.y - center.y)
        let newDistance = hypot(newPoint.x - center.x, newPoint.y - center.y)
        // A dim central source wins over a brighter off-center source. Retention
        // must not require moving the old source entirely out of the screen.
        return previousDistance - newDistance >= CameraTrackingPolicy.sourceSwitchAdvantage
    }
}
