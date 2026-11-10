import CoreGraphics
import Foundation
import simd

/// Acquisition is generous; once selected, the measured source is tracked independently
/// of the reticle. Remembering a scan is separate from fresh evidence for a photo.
nonisolated enum CameraTrackingPolicy {
    static let acquisitionRadius: CGFloat = 96
    static let holdRadius: CGFloat = 160
    static let sourceSwitchRadius: CGFloat = 48
    static let sourceSwitchAdvantage: CGFloat = 12
    static let maximumScanTurnDegrees: Float = 20
    static let trackGap: TimeInterval = 1.5
    static let scanMemory: TimeInterval = 5
    static let referenceFreshness: TimeInterval = 2
    static let maximumAnalysisAge: TimeInterval = 2

    static func acceptsAnalysis(capturedAt: TimeInterval, now: TimeInterval) -> Bool {
        capturedAt.isFinite && now.isFinite && now >= capturedAt && now - capturedAt <= maximumAnalysisAge
    }

    @MainActor static func select(fresh: [CameraOpticalTrack], pinned: CameraLightPin?, now: TimeInterval,
                                  center: CGPoint, currentAim: SIMD3<Float>? = nil,
                                  project: (SIMD3<Float>) -> CGPoint?) -> CameraOpticalTrack? {
        let nearest = fresh.compactMap { track -> (CameraOpticalTrack, CGFloat)? in
            guard let point = project(track.direction), isNearAim(point, center: center) else { return nil }
            return (track, hypot(point.x - center.x, point.y - center.y))
        }.min { $0.1 < $1.1 }?.0
        guard let pinned, keepsTarget(lastSeen: pinned.lastSeen, now: now,
            referenceAim: pinned.aimDirection, currentAim: currentAim) else { return nearest }
        let held = fresh.first { $0.id == pinned.opticalID || pinned.isSameSource($0.direction) }
        if let nearest, nearest.id != pinned.opticalID,
            let point = project(nearest.direction),
            CameraTargetSelection.beginsNewSource(previousPoint: project(pinned.direction), newPoint: point,
                center: center, observations: nearest.hits) { return nearest }
        // A competing light near the crosshair cannot steal a target through hand tremor.
        return held
    }

    @MainActor static func continuesPinnedSource(_ selected: CameraOpticalTrack, pinned: CameraLightPin?,
                                                 fresh: [CameraOpticalTrack]) -> Bool {
        guard let pinned else { return false }
        if selected.id == pinned.opticalID { return true }
        // Two simultaneously measured points are different targets, including at
        // high digital zoom where their world rays may be less than a degree apart.
        if fresh.contains(where: { $0.id == pinned.opticalID }) { return false }
        return pinned.canReacquire(selected.direction, identifiedAs: nil, opticalID: selected.id)
    }

    static func keepsTarget(lastSeen: TimeInterval, now: TimeInterval,
                            referenceAim: SIMD3<Float>?, currentAim: SIMD3<Float>?) -> Bool {
        guard now >= lastSeen else { return false }
        guard let referenceAim, let currentAim else { return keepsScan(lastSeen: lastSeen, now: now) }
        let a = simd_length(referenceAim), b = simd_length(currentAim)
        guard a.isFinite, b.isFinite, a > 0.001, b > 0.001 else { return false }
        return simd_dot(referenceAim / a, currentAim / b) >= cos(maximumScanTurnDegrees * .pi / 180)
    }

    static func isNearAim(_ point: CGPoint, center: CGPoint, holding: Bool = false) -> Bool {
        hypot(point.x - center.x, point.y - center.y) <= (holding ? holdRadius : acquisitionRadius)
    }
    static func keepsScan(lastSeen: TimeInterval, now: TimeInterval) -> Bool {
        now >= lastSeen && now - lastSeen <= scanMemory
    }
}
