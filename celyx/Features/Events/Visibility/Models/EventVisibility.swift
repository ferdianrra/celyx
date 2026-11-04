import Foundation
import simd

struct ViewingCoordinate: Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    nonisolated var isValid: Bool { latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) }
    nonisolated var label: String { String(format:"%.4f°, %.4f°",latitude,longitude) }
}

struct EventVisibilityGeometry: Sendable {
    struct Target: Sendable {
        let name: String
        let equatorOfDate: SIMD3<Double>
        let distanceAU: Double? // nil = direction at effectively infinite distance (meteor radiant)
    }
    let time: Date
    let siderealRadians: Double
    let sun: Target
    let targets: [Target]
    let minimumAltitude: Double
    let maximumSunAltitude: Double
    let magnitude: Double?
    let source: String

    nonisolated var needsOpticalAid: Bool { (magnitude ?? -30) > 5.5 }
    nonisolated var equipmentNote: String? {
        guard let magnitude else { return nil }
        if magnitude > 6.5 { return "Too faint for normal naked-eye viewing. Suitable optical or imaging equipment is needed." }
        if magnitude > 5.5 { return "A dark sky or optical aid may be needed to pick this out." }
        return nil
    }
    nonisolated var criteria: String { String(format:"Target ≥ %.0f° · Sun ≤ %.0f°",minimumAltitude,maximumSunAltitude) }
    nonisolated func assessment(at coordinate: ViewingCoordinate) -> ViewingAssessment {
        let frame = localFrame(coordinate)
        let sunAltitude = asin(clamped(sineAltitude(sun,frame:frame)))*180 / .pi
        let targetAltitude = targets.map { asin(clamped(sineAltitude($0,frame:frame)))*180 / .pi }.min() ?? -90
        return ViewingAssessment(coordinate:coordinate,targetAltitude:targetAltitude,sunAltitude:sunAltitude,
            meetsGeometry:targetAltitude >= minimumAltitude && sunAltitude <= maximumSunAltitude,
            needsOpticalAid:needsOpticalAid)
    }
    nonisolated func matches(_ coordinate: ViewingCoordinate,minimumSine: Double,maximumSunSine: Double) -> Bool {
        let frame = localFrame(coordinate)
        guard sineAltitude(sun,frame:frame) <= maximumSunSine else { return false }
        for target in targets where sineAltitude(target,frame:frame) < minimumSine { return false }
        return true
    }
    nonisolated private func clamped(_ value: Double) -> Double { min(1,max(-1,value)) }
    nonisolated private func localFrame(_ coordinate: ViewingCoordinate) -> (up:SIMD3<Double>,observer:SIMD3<Double>) {
        let latitude = coordinate.latitude * .pi/180
        let angle = siderealRadians+coordinate.longitude * .pi/180
        let up = SIMD3(cos(latitude)*cos(angle),cos(latitude)*sin(angle),sin(latitude))
        // Astronomy Engine's sea-level Earth ellipsoid constants; parallax matters
        // for the Moon and nearby asteroids. This is not a flat-Earth radius zone.
        let flattening = 0.996647180302104
        let n = 6378.1366/sqrt(1-(1-flattening*flattening)*pow(sin(latitude),2))
        let observer = SIMD3(n*up.x,n*up.y,n*flattening*flattening*up.z)/149597870.69098932
        return (up,observer)
    }
    nonisolated private func sineAltitude(_ target: Target,frame:(up:SIMD3<Double>,observer:SIMD3<Double>)) -> Double {
        let direction = target.distanceAU.map { simd_normalize(target.equatorOfDate*$0-frame.observer) } ?? target.equatorOfDate
        return simd_dot(frame.up,direction)
    }

}

struct ViewingAssessment: Sendable {
    let coordinate: ViewingCoordinate
    let targetAltitude: Double
    let sunAltitude: Double
    let meetsGeometry: Bool
    let needsOpticalAid: Bool
}

enum EventViewingPlan: Sendable {
    case geometry(EventVisibilityGeometry)
    case greatestEclipse(time:Date,coordinate:ViewingCoordinate)
    case unavailable(String)
}

struct VisibilityRaster: Sendable {
    let width: Int
    let height: Int
    let rgba: Data
}
