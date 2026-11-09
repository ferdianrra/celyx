import Foundation
import simd

/// One collected object placed in the sky.
struct NightSeaObject: Identifiable, Equatable {
    enum Kind: Float {
        case star = 0
        case planet = 1
        case moon = 2
        case sun = 3
    }
    let id: Int
    let direction: SIMD3<Double>
    /// Sprite radius in points (glow included).
    let radius: Double
    let color: SIMD3<Double>
    let kind: Kind
    var isAboveHorizon: Bool { direction.z > 0.002 }
}
