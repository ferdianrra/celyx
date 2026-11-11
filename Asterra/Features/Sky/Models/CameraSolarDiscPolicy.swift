import Foundation
import simd

/// A resolved optical disc is matched only to a solar disc above the horizon.
/// Compact lens flare and ordinary star points cannot acquire the Sun's identity.
@MainActor enum CameraSolarDiscPolicy {
    /// Call with ephemeris-matched tracks only. A small cloud highlight or flare
    /// closer to the reticle must not steal the resolved solar core.
    static func preferredCore(from tracks: [CameraOpticalTrack], center: CGPoint,
                              project: (SIMD3<Float>) -> CGPoint?) -> CameraOpticalTrack? {
        tracks.filter { track in
            guard track.isDisc, track.hits >= 2, let point = project(track.direction) else { return false }
            return CameraTrackingPolicy.isNearAim(point, center: center, holding: true)
        }.max { $0.size.width * $0.size.height < $1.size.width * $1.size.height }
    }

    static func assess(direction: SIMD3<Float>, isDisc: Bool, headingAccuracy: Double?,
                       hasReferenceAlignment: Bool, candidates: [(CatalogStar, SIMD3<Float>)]) -> CameraCandidateAssessment {
        guard isDisc, direction.y > 0 else { return .init(match: nil, issue: .noCandidate) }
        let accuracy = hasReferenceAlignment ? 3 : headingAccuracy
        guard let accuracy, accuracy.isFinite, accuracy >= 0, accuracy <= 25 else {
            return .init(match: nil, issue: .compass)
        }
        // An unaligned compass report is not a calibrated camera bearing.
        // Keep a bounded yaw margin for resolved discs; gravity still constrains altitude.
        let radius = hasReferenceAlignment ? 3 : min(12, max(8, accuracy * 0.8))
        let ranked = candidates.compactMap { star, expected -> CameraCandidateMatch? in
            guard star.isSolarDisc, expected.y > 0 else { return nil }
            let altitudeError = abs(asin(Double(direction.y)) - asin(Double(expected.y))) * 180 / .pi
            let separation = acos(Double(min(1, max(-1, simd_dot(direction, expected))))) * 180 / .pi
            guard altitudeError <= 4, separation <= radius else { return nil }
            return CameraCandidateMatch(star: star, separation: separation, score: separation)
        }.sorted { $0.separation < $1.separation }
        guard let first = ranked.first else { return .init(match: nil, issue: .noCandidate) }
        if ranked.count > 1, ranked[1].separation - first.separation < 0.5 {
            return .init(match: nil, issue: .ambiguous)
        }
        return .init(match: first, issue: .stabilizing)
    }
}
