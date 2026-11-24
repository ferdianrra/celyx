import CoreGraphics
import Foundation

/// Keep a captured frame through hand shake, without locking the next scan to that target.
nonisolated enum CameraTargetSelection {
    /// Presentation starts near the visible reticle; optical discovery remains wider.
    static let reticleEntryRadius: CGFloat = 28
    static let lockReleaseRadius: CGFloat = 80

    @MainActor static func lockRadius(for star: CatalogStar) -> CGFloat {
        star.isSolarSystemBody ? CameraTrackingPolicy.holdRadius : lockReleaseRadius
    }
    static func canAcquireInReticle(at point: CGPoint, center: CGPoint) -> Bool {
        let distance = hypot(point.x - center.x, point.y - center.y)
        return distance.isFinite && distance <= reticleEntryRadius
    }

    /// A centered neighbor can take over while the old target is still visible.
    /// A relative margin keeps ties stable without imposing a minimum separation.
    static func shouldSwitchLock(to point: CGPoint, from heldPoint: CGPoint?, center: CGPoint) -> Bool {
        guard canAcquireInReticle(at: point, center: center) else { return false }
        guard let heldPoint else { return true }
        let heldDistance = hypot(heldPoint.x - center.x, heldPoint.y - center.y)
        return hypot(point.x - center.x, point.y - center.y) < heldDistance * 0.75
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
    static func keepsRetainedTarget(
        at point: CGPoint?, center: CGPoint, radius: CGFloat = lockReleaseRadius
    ) -> Bool {
        guard let point else { return false }
        return hypot(point.x - center.x, point.y - center.y) <= radius
    }
    static func beginsNewSource(
        previousPoint: CGPoint?, newPoint: CGPoint, center: CGPoint, observations: Int
    ) -> Bool {
        guard observations >= 3, hypot(newPoint.x - center.x, newPoint.y - center.y) <= CameraTrackingPolicy.sourceSwitchRadius else {
            return false
        }
        guard let previousPoint else { return true }
        if shouldSwitchLock(to: newPoint, from: previousPoint, center: center) { return true }
        let previousDistance = hypot(previousPoint.x - center.x, previousPoint.y - center.y)
        let newDistance = hypot(newPoint.x - center.x, newPoint.y - center.y)
        // A dim central source wins over a brighter off-center source. Retention
        // must not require moving the old source entirely out of the screen.
        return previousDistance - newDistance >= CameraTrackingPolicy.sourceSwitchAdvantage
    }
}
