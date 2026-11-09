import Foundation
import simd

/// Optical persistence rejects brief flashes; verified calibration is separately
/// required by the service. Neither test proves an isolated light is celestial.
nonisolated enum CameraIdentityPolicy {
    static let maximumSeparationDegrees = 0.5
    @MainActor static func assess(direction: SIMD3<Float>, isDisc: Bool, zoom: Double,
                       hasReferenceAlignment: Bool, candidates: [(CatalogStar, SIMD3<Float>)],
                       hasOpticalEvidence: Bool) -> CameraCandidateAssessment {
        // An isolated lamp can coincide with a compass prediction. Require independent alignment.
        guard hasReferenceAlignment else { return .init(match: nil, issue: .alignment) }
        return CameraCandidateMatcher.assess(direction: direction, isDisc: isDisc, zoom: zoom,
            headingAccuracy: nil, candidates: candidates, maximumSeparation: maximumSeparationDegrees,
            isCalibrated: true, hasOpticalEvidence: hasOpticalEvidence)
    }
    static func hasPersistentEvidence(hits: Int, firstSeen: TimeInterval, lastSeen: TimeInterval) -> Bool {
        hits >= 4 && firstSeen.isFinite && lastSeen.isFinite && lastSeen - firstSeen >= 0.6
    }
}
