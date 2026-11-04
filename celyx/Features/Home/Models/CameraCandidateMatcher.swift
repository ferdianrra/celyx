import Foundation
import simd

struct CameraCandidateMatch {
    let star: CatalogStar
    let separation: Double
    let score: Double
}

enum CameraCandidateMatcher {
    // This is a brightness prior, not a measurement of magnitude from camera pixels.
    static func preferredMagnitudeLimit(zoom: Double) -> Double {
        3.5 + min(1.5,0.5*log2(max(1,zoom)))
    }
    static func best(direction: SIMD3<Float>,isDisc: Bool,zoom: Double,headingAccuracy: Double?,
                     candidates: [(CatalogStar,SIMD3<Float>)]) -> CameraCandidateMatch? {
        if let headingAccuracy, !headingAccuracy.isFinite || headingAccuracy < 0 || headingAccuracy > 25 { return nil }
        let radius = min(12,max(6,(headingAccuracy ?? 10)*0.75))
        let preferredLimit = preferredMagnitudeLimit(zoom:zoom)
        let ranked = candidates.compactMap { star,expected -> CameraCandidateMatch? in
            let separation = Double(acos(min(1,max(-1,simd_dot(direction,expected)))))*180 / .pi
            guard separation <= radius, star.mag <= 5.5 else { return nil }
            // A point source several degrees away should not acquire the Sun/Moon's name.
            if (star.isSun || star.isMoon) && !isDisc && separation > 3 { return nil }
            let brightnessPenalty = max(0,star.mag-1)*0.9 + max(0,star.mag-3)*0.8
            let faintnessPenalty = max(0,star.mag-preferredLimit)*1.5
            let brightnessBonus = min(1.5,max(0,-star.mag)*0.3)
            let discPenalty = isDisc && !star.isSolarDisc ? 1.5 : 0
            return CameraCandidateMatch(star:star,separation:separation,
                score:separation+brightnessPenalty+faintnessPenalty-brightnessBonus+discPenalty)
        }.sorted {
            if abs($0.score-$1.score) > 0.0001 { return $0.score < $1.score }
            return $0.star.id < $1.star.id
        }
        guard let first = ranked.first else { return nil }
        // Keep a single suggestion, but don't arbitrarily break a near tie.
        if ranked.count > 1 && ranked[1].score-first.score < 0.75 { return nil }
        return first
    }
}
