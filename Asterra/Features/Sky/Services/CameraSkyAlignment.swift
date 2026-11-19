import UIKit
import AVFoundation
import Combine
import CoreLocation
import Observation
import simd

/// Corrections belong to one live sensor world frame, never to a later app session.
@MainActor @Observable
final class CameraSkyAlignment {
    let session: SkyCaptureSession
    private(set) var reference: String?
    private(set) var date: Date?
    private(set) var location: ObserverLocation?
    private(set) var calibrationReason: String?
    var requiresCalibration: Bool { reference == nil || calibrationReason != nil }
    private(set) var generation = 0
    private(set) var rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var lifecycleObserver: AnyCancellable?

    init(defaults: UserDefaults = .standard, notifications: NotificationCenter = .default,
         session: SkyCaptureSession? = nil) {
        self.session = session ?? SkyCaptureSession()
        self.defaults = defaults
        // Every launch starts without a verified sensor world, including the first launch.
        calibrationReason = "Point the camera at several stars to map the sky automatically."
        defaults.removeObject(forKey: "cameraSkyAlignment.v1")
        // Observe the whole app: the camera screen may be covered by an album or picker.
        lifecycleObserver = notifications.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.pause(reason: "Sky mapping will restart when the camera resumes.")
                }
            }
    }
    func run() {
        session.run()
    }
    func correct(_ direction: SIMD3<Float>) -> SIMD3<Float> { rotation.act(direction) }
    func save(rotation: simd_quatf, reference: String, date: Date, location: ObserverLocation? = nil) {
        self.rotation = simd_normalize(rotation)
        self.reference = reference
        self.date = date
        self.location = location
        calibrationReason = nil
        defaults.set(true, forKey: "cameraSkyAlignment.usedBefore")
    }
    func pause(reason: String) {
        invalidate(reason: reason)
        session.pause()
    }
    func enterBackground() {
        pause(
            reason:
                "Sky mapping will restart when the camera returns to the foreground.")
    }
    func invalidate(reason: String) {
        generation += 1
        rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        reference = nil
        date = nil
        location = nil
        calibrationReason = reason
        defaults.removeObject(forKey: "cameraSkyAlignment.v1")
    }
    @discardableResult func validateLocation(_ current: ObserverLocation) -> Bool {
        guard let location else { return false }
        let distance = CLLocation(latitude: location.latitude, longitude: location.longitude)
            .distance(from: CLLocation(latitude: current.latitude, longitude: current.longitude))
        // Account for uncertainty so an ordinary GPS update does not demand calibration.
        guard distance > max(150, location.accuracy + current.accuracy) else { return false }
        invalidate(reason: "Your location changed. Align the sky again from this spot.")
        return true
    }
    func clear() {
        invalidate(reason: "Sky alignment was reset and will be rebuilt automatically.")
    }
}
