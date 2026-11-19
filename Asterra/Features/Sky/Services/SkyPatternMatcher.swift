import Foundation
import simd

nonisolated struct CalibrationCatalogPoint: Sendable {
    let id: Int
    let direction: SIMD3<Float>  // Uncorrected true ENU converted to AR's east/up/south axes.
    let magnitude: Double
}

nonisolated struct CalibrationObservation: Sendable {
    let id: Int
    let direction: SIMD3<Float>
}

nonisolated struct SkyPatternSolution: Equatable, Sendable {
    struct Match: Equatable, Sendable {
        let observationID: Int
        let starID: Int
        let residualDegrees: Double
    }
    let headingOffset: Double  // True azimuth minus the raw camera-world azimuth.
    let residualDegrees: Double
    let anchorStarID: Int
    let matches: [Match]
    var starIDs: [Int] { matches.map(\.starID).sorted() }
}

/// A gravity-assisted local pattern solver, not a brightness-based identity guess.
/// Only yaw is fitted: AR gravity already supplies altitude. Four unique rays must agree
/// with one rotation, including the ray in the reticle, and no rival rotation may fit as well.
nonisolated enum SkyPatternMatcher {
    static let minimumAutomaticPatternStars = 4
    private static let tolerance = 0.4 * Double.pi / 180

    static func solve(
        observations input: [CalibrationObservation],
        catalogue: [CalibrationCatalogPoint], anchorID: Int,
        priorOffset: Double = 0
    ) -> SkyPatternSolution? {
        let observations = Array(
            input.filter {
                valid($0.direction) && $0.direction.y > sin(8 * Float.pi / 180)
                    && $0.direction.y < sin(83 * Float.pi / 180)
            }.prefix(12))
        guard observations.count >= minimumAutomaticPatternStars,
            observations.contains(where: { $0.id == anchorID }),
            Set(observations.map(\.id)).count == observations.count
        else { return nil }
        let stars = catalogue.filter { valid($0.direction) && $0.magnitude <= 5.5 }
        guard Set(stars.map(\.id)).count == stars.count else { return nil }
        let pools = observations.map { observed in
            stars.filter { star in
                abs(asin(Double(star.direction.y)) - asin(Double(observed.direction.y))) < 0.6 * .pi / 180
                    && abs(wrap(azimuth(star.direction) - azimuth(observed.direction) - priorOffset)) <= 40
                        * .pi / 180
            }
        }
        var hypotheses: [Double] = []
        var bins: Set<Int> = []
        for (index, observation) in observations.enumerated() {
            for star in pools[index] {
                let offset = wrap(azimuth(star.direction) - azimuth(observation.direction))
                if bins.insert(Int((offset * 180 / .pi * 10).rounded())).inserted {
                    hypotheses.append(offset)
                }
            }
        }
        struct Edge {
            let index: Int
            let star: CalibrationCatalogPoint
            let error: Double
        }
        func assignments(_ offset: Double) -> [Edge] {
            let c = Float(cos(offset))
            let s = Float(sin(offset))
            var edges: [Edge] = []
            for (index, observed) in observations.enumerated() {
                for star in pools[index] {
                    let d = star.direction
                    let predicted = SIMD3(c * d.x + s * d.z, d.y, -s * d.x + c * d.z)
                    let dot = Double(simd_dot(observed.direction, predicted))
                    if dot >= cos(tolerance) {
                        edges.append(Edge(index: index, star: star, error: acos(min(1, max(-1, dot)))))
                    }
                }
            }
            edges.sort { $0.error < $1.error }
            var usedObservations: Set<Int> = []
            var usedStars: Set<Int> = []
            return edges.filter { edge in
                !edges.contains {
                    $0.index == edge.index && $0.star.id != edge.star.id
                        && abs($0.error - edge.error) < 0.12 * .pi / 180
                }
            }.filter {
                guard !usedObservations.contains($0.index), !usedStars.contains($0.star.id) else {
                    return false
                }
                usedObservations.insert($0.index)
                usedStars.insert($0.star.id)
                return true
            }
        }
        var solutions: [SkyPatternSolution] = []
        for hypothesis in hypotheses {
            let initial = assignments(hypothesis)
            guard initial.count >= minimumAutomaticPatternStars else { continue }
            let offsets = initial.map {
                azimuth($0.star.direction) - azimuth(observations[$0.index].direction)
            }
            let refined = atan2(offsets.reduce(0) { $0 + sin($1) }, offsets.reduce(0) { $0 + cos($1) })
            let fit = assignments(refined)
            guard fit.count >= minimumAutomaticPatternStars,
                let anchor = fit.first(where: { observations[$0.index].id == anchorID })
            else { continue }
            var span = 0.0
            var separated = true
            for i in fit.indices {
                for j in fit.indices where j > i {
                    let angle = acos(
                        min(
                            1,
                            max(
                                -1,
                                Double(
                                    simd_dot(
                                        observations[fit[i].index].direction,
                                        observations[fit[j].index].direction)))))
                    span = max(span, angle)
                    if angle < 0.75 * .pi / 180 { separated = false }
                }
            }
            let rms = sqrt(fit.reduce(0) { $0 + $1.error * $1.error } / Double(fit.count)) * 180 / .pi
            guard separated, span >= 8 * .pi / 180, rms <= 0.25 else { continue }
            let solution = SkyPatternSolution(
                headingOffset: refined, residualDegrees: rms, anchorStarID: anchor.star.id,
                matches: fit.map {
                    .init(
                        observationID: observations[$0.index].id, starID: $0.star.id,
                        residualDegrees: $0.error * 180 / .pi)
                })
            if let index = solutions.firstIndex(where: {
                abs(wrap($0.headingOffset - refined)) < .pi / 180
            }) {
                if better(solution, than: solutions[index]) { solutions[index] = solution }
            } else {
                solutions.append(solution)
            }
        }
        solutions.sort { better($0, than: $1) }
        guard let best = solutions.first else { return nil }
        // Reject competing sky patches even if one happens to have a slightly smaller residual.
        if solutions.dropFirst().contains(where: { $0.matches.count >= best.matches.count - 1 }) {
            return nil
        }
        return best
    }

    private static func better(_ lhs: SkyPatternSolution, than rhs: SkyPatternSolution) -> Bool {
        lhs.matches.count == rhs.matches.count
            ? lhs.residualDegrees < rhs.residualDegrees : lhs.matches.count > rhs.matches.count
    }
    static func wrap(_ angle: Double) -> Double { atan2(sin(angle), cos(angle)) }
    static func azimuth(_ ray: SIMD3<Float>) -> Double { atan2(Double(ray.x), Double(-ray.z)) }
    private static func valid(_ ray: SIMD3<Float>) -> Bool {
        ray.x.isFinite && ray.y.isFinite && ray.z.isFinite && abs(simd_length(ray) - 1) < 0.001
    }
}

/// Independent frames must support the same identities and correction; cached frames never count.
nonisolated struct SkyPatternConsensus {
    private var firstTime: TimeInterval?
    private var lastTime: TimeInterval?
    private var previous: SkyPatternSolution?
    private var count = 0
    mutating func reset() { self = Self() }
    mutating func add(_ solution: SkyPatternSolution?, at time: TimeInterval) -> Double {
        guard time.isFinite else {
            reset()
            return 0
        }
        guard let solution else {
            if let lastTime, time - lastTime > 0.8 { reset() }
            return 0
        }
        if let lastTime, time <= lastTime { return 0 }
        if let previous, let lastTime,
            previous.starIDs == solution.starIDs, previous.anchorStarID == solution.anchorStarID,
            abs(SkyPatternMatcher.wrap(previous.headingOffset - solution.headingOffset)) < 0.3 * .pi
                / 180,
            time - lastTime <= 0.8
        {
            count += 1
        } else {
            firstTime = time
            count = 1
        }
        previous = solution
        lastTime = time
        let elapsed = time - (firstTime ?? time)
        return min(1, min(elapsed / 1.2, Double(count) / 5))
    }
}
