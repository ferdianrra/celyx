import Foundation
import simd

struct CameraCandidateMatch {
    let star: CatalogStar
    let separation: Double
    let score: Double
}

enum CameraIdentificationIssue: Equatable {
    case stabilizing, compass, noCandidate, ambiguous, alignment
    var title: String {
        switch self {
        case .stabilizing: "Finding its name…"
        case .compass: "Direction needs alignment"
        case .noCandidate: "No nearby catalog match"
        case .ambiguous: "More than one possible match"
        case .alignment: "Position needs alignment"
        }
    }
    var message: String {
        switch self {
        case .stabilizing: "The light is visible. Hold steady a little longer while we check its direction."
        case .compass: "The light is visible, but the compass isn’t giving us a reliable direction. Align with an object you can identify."
        case .noCandidate: "We see the light, but haven’t found a clear catalog match near its direction. Check alignment; it could also be a light outside the catalog."
        case .ambiguous: "Several objects fit this direction too closely to choose a name. A known reference can help align the camera."
        case .alignment: "There’s a possible match outside the saved alignment’s close range. Hold steady, or check alignment with a known object."
        }
    }
}

struct CameraCandidateAssessment {
    let match: CameraCandidateMatch?
    let issue: CameraIdentificationIssue
}

enum CameraCandidateMatcher {
    // This is a brightness prior, not a measurement of magnitude from camera pixels.
    static func preferredMagnitudeLimit(zoom: Double) -> Double {
        3.5 + min(1.5,0.5*log2(max(1,zoom)))
    }
    static func assess(direction: SIMD3<Float>,isDisc: Bool,zoom: Double,headingAccuracy: Double?,
                     candidates: [(CatalogStar,SIMD3<Float>)],maximumSeparation: Double? = nil,minimumScoreGap: Double = 0.75) -> CameraCandidateAssessment {
        if let headingAccuracy, !headingAccuracy.isFinite || headingAccuracy < 0 || headingAccuracy > 25 { return .init(match:nil,issue:.compass) }
        let radius = min(maximumSeparation ?? 12,min(12,max(6,(headingAccuracy ?? 10)*0.75)))
        let preferredLimit = preferredMagnitudeLimit(zoom:zoom)
        let minimumDot = cos(radius * .pi/180)
        let ranked = candidates.compactMap { star,expected -> CameraCandidateMatch? in
            let dot = Double(simd_dot(direction,expected))
            guard dot >= minimumDot, star.mag <= 5.5 else { return nil }
            let separation = acos(min(1,max(-1,dot)))*180 / .pi
            guard separation <= radius else { return nil }
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
        guard let first = ranked.first else { return .init(match:nil,issue:.noCandidate) }
        // Keep a single suggestion, but don't arbitrarily break a near tie.
        if ranked.count > 1 && ranked[1].score-first.score < minimumScoreGap { return .init(match:nil,issue:.ambiguous) }
        return .init(match:first,issue:.stabilizing)
    }
}
