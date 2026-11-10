import Foundation

/// Compass corrections measured by aiming at a known sky object (Calibrate screen).
///
/// Phone compasses are often off by 5–30° because of local magnetic interference. The two sensor paths
/// are corrected separately because they fuse the compass differently:
/// - `arHeadingOffset`: ARKit (`gravityAndHeading`), used by the collecting camera.
/// - `motionHeadingOffset`: CoreMotion (`xTrueNorthZVertical`), used by the garden.
/// Each is "true azimuth − what the sensor reported", in radians, east of north positive.
nonisolated enum SkyCalibration {
    private static let arKey = "calibration.arHeadingOffset"
    private static let motionKey = "calibration.motionHeadingOffset"
    private static let dateKey = "calibration.date"
    private static let targetKey = "calibration.target"

    // Cached: worldDirection() reads this for every catalogue star on every camera frame.
    nonisolated(unsafe) private(set) static var arHeadingOffset: Double = UserDefaults.standard
        .double(forKey: arKey)
    nonisolated(unsafe) private(set) static var arCos: Double = cos(arHeadingOffset)
    nonisolated(unsafe) private(set) static var arSin: Double = sin(arHeadingOffset)
    nonisolated(unsafe) private(set) static var motionHeadingOffset: Double = UserDefaults.standard
        .double(forKey: motionKey)

    static var date: Date? { UserDefaults.standard.object(forKey: dateKey) as? Date }
    static var target: String? { UserDefaults.standard.string(forKey: targetKey) }
    static var isCalibrated: Bool { date != nil }

    static func save(arOffset: Double, motionOffset: Double?, target: String) {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
        setAR(arOffset)
        if let motionOffset {
            motionHeadingOffset = motionOffset
            UserDefaults.standard.set(motionOffset, forKey: motionKey)
        }
        UserDefaults.standard.set(arOffset, forKey: arKey)
        UserDefaults.standard.set(Date(), forKey: dateKey)
        UserDefaults.standard.set(target, forKey: targetKey)
    }
    static func reset() {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
        setAR(0)
        motionHeadingOffset = 0
        for key in [arKey, motionKey, dateKey, targetKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    private static func setAR(_ value: Double) {
        arHeadingOffset = value
        arCos = cos(value)
        arSin = sin(value)
    }
    /// Wraps an angle to (−π, π].
    static func wrap(_ angle: Double) -> Double { atan2(sin(angle), cos(angle)) }
}
