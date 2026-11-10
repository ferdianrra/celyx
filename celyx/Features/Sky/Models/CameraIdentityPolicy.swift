import Foundation
import simd

/// Optical persistence rejects brief flashes; verified calibration is separately
/// required by the service. Neither test proves an isolated light is celestial.
nonisolated enum CameraIdentityPolicy {
    static let maximumSeparationDegrees = 0.5
    static func permitsPointIdentification(sunAltitude: Double?) -> Bool {
        guard let sunAltitude, sunAltitude.isFinite else { return false }
        return sunAltitude < -6
    }
    @MainActor static func assess(direction: SIMD3<Float>, isDisc: Bool, zoom: Double,
                       hasReferenceAlignment: Bool, candidates: [(CatalogStar, SIMD3<Float>)],
                       hasOpticalEvidence: Bool) -> CameraCandidateAssessment {
        // An isolated lamp can coincide with a compass prediction. Require independent alignment.
        guard hasReferenceAlignment else { return .init(match: nil, issue: .alignment) }
        return CameraCandidateMatcher.assess(direction: direction, isDisc: isDisc, zoom: zoom,
            headingAccuracy: nil, candidates: candidates, maximumSeparation: maximumSeparationDegrees,
            isCalibrated: true, hasOpticalEvidence: hasOpticalEvidence)
    }
    /// A single measured point can offer a direction-based name, never a verified identity.
    @MainActor static func suggest(direction: SIMD3<Float>, isDisc: Bool, zoom: Double,
                                  headingAccuracy: Double?, candidates: [(CatalogStar, SIMD3<Float>)])
        -> CameraCandidateAssessment {
        guard let accuracy = headingAccuracy, accuracy.isFinite, accuracy >= 0, accuracy <= 15 else {
            return .init(match: nil, issue: .compass)
        }
        guard direction.y > sin(5 * Float.pi / 180) else { return .init(match: nil, issue: .noCandidate) }
        return CameraCandidateMatcher.assess(direction: direction, isDisc: isDisc, zoom: zoom,
            headingAccuracy: accuracy, candidates: candidates.filter { !$0.0.isSolarDisc },
            maximumSeparation: min(8, max(2, accuracy * 0.8)), minimumScoreGap: 0.35,
            hasOpticalEvidence: true)
    }

    static func hasPersistentEvidence(hits: Int, firstSeen: TimeInterval, lastSeen: TimeInterval) -> Bool {
        hits >= 4 && firstSeen.isFinite && lastSeen.isFinite && lastSeen - firstSeen >= 0.6
    }
}
