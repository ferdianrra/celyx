import Foundation
import simd

@MainActor enum CameraReferenceCandidates {
    static func make(catalogue: [CatalogStar], sky: SkySnapshot, observed: SIMD3<Float>) -> [CalibrationCandidate] {
        let stars = catalogue.filter { !$0.isSolarSystemBody && $0.mag <= 5.5 }.map {
            ($0, Refraction.apparent(sky.direction(ra: $0.ra_deg, dec: $0.dec_deg)))
        }
        let planets = sky.planets.map { ($0.star, Refraction.apparent($0.direction)) }
        let altitude = asin(Double(observed.y)) * 180 / .pi
        return (stars + planets).compactMap { star, d -> CalibrationCandidate? in
            let candidate = CalibrationCandidate(star: star,
                direction: SIMD3(Float(d.x), Float(d.z), Float(-d.y)))
            return candidate.altitude > 5 && candidate.altitude < 83 && abs(candidate.altitude - altitude) <= 3
                ? candidate : nil
        }.sorted { simd_dot($0.direction, observed) > simd_dot($1.direction, observed) }
    }
}
