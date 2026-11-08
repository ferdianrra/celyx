import Foundation
import simd

nonisolated struct CalibrationCatalogFilter: Equatable, Sendable {
    var maximumMagnitude: Double = 5.5
    var minimumAltitude: Double = 8
    func allows(magnitude: Double,altitude: Double) -> Bool {
        magnitude.isFinite && altitude.isFinite && magnitude <= maximumMagnitude
            && altitude >= minimumAltitude && altitude < 83
    }
}

struct CalibrationCandidate: Identifiable {
    let star: CatalogStar
    let direction: SIMD3<Float> // True direction in east/up/south, before calibration correction.
    var id: Int { star.id }
    var altitude: Double { asin(min(1,max(-1,Double(direction.y))))*180 / .pi }
    var azimuth: Double { (SkyPatternMatcher.azimuth(direction)*180 / .pi+360).truncatingRemainder(dividingBy:360) }
}

struct CalibrationSuggestion: Identifiable {
    let candidate: CalibrationCandidate
    let separation: Double
    var id: Int { candidate.id }
}

/// One known identity is enough for a manual yaw correction; it is not an automatic identification.
nonisolated enum CalibrationReference {
    static func localRotation(expected: SIMD3<Float>,observed: SIMD3<Float>,existingOffset: Double) -> simd_quatf? {
        guard let offset = correction(expected:expected,observed:observed) else { return nil }
        return simd_quatf(angle:Float(offset-existingOffset),axis:SIMD3(0,1,0))
    }
    static func correction(expected: SIMD3<Float>,observed: SIMD3<Float>) -> Double? {
        guard expected.x.isFinite, expected.y.isFinite, expected.z.isFinite,
              observed.x.isFinite, observed.y.isFinite, observed.z.isFinite,
              abs(simd_length(expected)-1) < 0.001, abs(simd_length(observed)-1) < 0.001,
              abs(observed.y) < 0.999,
              abs(asin(Double(expected.y))-asin(Double(observed.y))) <= 3 * .pi/180 else { return nil }
        return SkyPatternMatcher.wrap(SkyPatternMatcher.azimuth(expected)-SkyPatternMatcher.azimuth(observed))
    }
}
