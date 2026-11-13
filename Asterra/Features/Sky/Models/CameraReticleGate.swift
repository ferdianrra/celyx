import Foundation

/// A small exit margin keeps a selected target from flickering at the reticle edge.
nonisolated struct CameraReticleGate: Sendable {
    private(set) var centeredID: Int?
    mutating func update(id: Int?, distance: Double?, enabled: Bool) {
        guard enabled, let id, let distance, distance.isFinite else {
            centeredID = nil
            return
        }
        let radius = centeredID == id ? Double(CameraTrackingPolicy.holdRadius) : Double(CameraTrackingPolicy.acquisitionRadius)
        centeredID = distance <= radius ? id : nil
    }
    mutating func reset() { centeredID = nil }
}

struct CameraReferenceCapture: Identifiable {
    let id = UUID()
    let generation: Int
    let direction: SIMD3<Float>
    let date: Date
    let location: ObserverLocation
    let candidates: [CalibrationCandidate]
}
