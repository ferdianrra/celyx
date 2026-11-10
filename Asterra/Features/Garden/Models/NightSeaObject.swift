import Foundation
import simd

/// One collected object placed in the sky.
struct NightSeaObject: Identifiable, Equatable {
    enum Kind: Float { case star = 0, planet = 1, moon = 2, sun = 3, background = 4 }
    let id: Int
    let direction: SIMD3<Double>
    /// Stars: core radius in points (the kit's starR, x1.3 for collected). Background stars: their magnitude.
    /// Planets, Moon, Sun: sprite radius in points (glow included).
    let radius: Double
    let color: SIMD3<Double>
    let kind: Kind
    var isAboveHorizon: Bool { direction.z > 0.002 }
    var gpuKind: Float { kind.rawValue }
    /// The kit's star radius (points) for a magnitude; collected stars use it x1.3.
    static func starRadius(magnitude: Double) -> Double { min(5,max(0.8,3.0-0.55*magnitude)) }
}
