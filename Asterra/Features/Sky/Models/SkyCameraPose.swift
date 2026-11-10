import Foundation

struct SkyCameraPose: Equatable {
    var azimuth: Double
    var altitude: Double
    var fieldOfView: Double

    init(scene: SkySceneState) {
        azimuth = scene.azimuth
        altitude = scene.altitude
        fieldOfView = scene.fieldOfView
    }
    init(azimuth: Double, altitude: Double, fieldOfView: Double) {
        self.azimuth = azimuth
        self.altitude = altitude
        self.fieldOfView = fieldOfView
    }
    static func interpolate(from: Self, to: Self, progress: Double) -> Self {
        let t = min(1, max(0, progress))
        if t == 0 { return from }
        // Quintic easing has zero velocity and acceleration at both ends.
        let eased = t * t * t * (t * (t * 6 - 15) + 10)
        let turn = atan2(sin(to.azimuth - from.azimuth), cos(to.azimuth - from.azimuth))
        return Self(
            azimuth: from.azimuth + turn * eased,
            altitude: from.altitude + (to.altitude - from.altitude) * eased,
            fieldOfView: exp(
                log(from.fieldOfView) + (log(to.fieldOfView) - log(from.fieldOfView)) * eased))
    }
}
