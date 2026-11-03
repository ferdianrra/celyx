import CoreMotion
import CoreLocation
import Foundation

enum MotionCalibrationStage {
    case location, compass, settling, ready, blocked
}

@MainActor
final class MotionService: NSObject, CLLocationManagerDelegate {
    private let manager = CMMotionManager()
    private let compass = CLLocationManager()
    private var running = false
    private var heading: CLHeading?
    private var hasLocation = false
    private var goodSince: TimeInterval?
    private var poorSince: TimeInterval?
    private var lastStage: MotionCalibrationStage?
    private var ready = false
    private var lastProgress = -1
    private var blockedMessage: String?
    var onCalibration: ((Bool,Double,String,MotionCalibrationStage) -> Void)?
    var onLocation: ((ObserverLocation) -> Void)?
    private(set) var referenceDescription = "Gyro isn’t ready yet"
    var isAvailable: Bool { manager.isDeviceMotionAvailable && CLLocationManager.headingAvailable() }

    override init() { super.init(); compass.delegate = self }

    func start(onChange: @escaping (Double,Double,Bool) -> Void) {
        stop()
        running = true
        report(false,0,"Finding your location…",stage:.location)
        guard isAvailable, CMMotionManager.availableAttitudeReferenceFrames().contains(.xTrueNorthZVertical) else {
            report(false,0,"This device can’t find true north.",stage:.blocked)
            return
        }
        authorize()
        manager.showsDeviceMovementDisplay = true
        manager.deviceMotionUpdateInterval = 1/60
        manager.startDeviceMotionUpdates(using:.xTrueNorthZVertical,to:.main) { [weak self] motion,error in
            guard let self, self.running else { return }
            if let blockedMessage = self.blockedMessage { self.report(false,0,blockedMessage,stage:.blocked); return }
            guard let motion, error == nil else {
                self.ready = false; self.goodSince = nil
                self.report(false,0,"Motion sensors aren’t ready. Check Motion & Fitness access in Settings and try again.",stage:.blocked)
                return
            }
            guard self.hasLocation else {
                self.report(false,0,"Finding your location. Try near a window or outside, and check location access if it takes a while.",stage:.location)
                return
            }
            let time = motion.timestamp
            // A stationary compass need not deliver a new timestamp every few seconds.
            // Once north is acquired, retain it through brief sensor-quality fluctuations.
            let validHeading = self.heading.map { $0.trueHeading >= 0 && $0.headingAccuracy >= 0 } ?? false
            let accuracy = self.heading?.headingAccuracy ?? .infinity
            let recentlyAcquired = self.heading.map { abs($0.timestamp.timeIntervalSinceNow) < 60 } ?? false
            let canAcquire = validHeading && accuracy <= 25 && recentlyAcquired
            if !self.ready {
                guard canAcquire else {
                    self.goodSince = nil
                    let quality = validHeading ? String(format:"Compass accuracy is ±%.0f°. ",accuracy) : "We haven’t found north yet. "
                    self.report(false,0.25,quality+"Follow the phone’s movement below, away from magnets or metal.",stage:.compass)
                    return
                }
                let rotation = motion.rotationRate
                let turning = sqrt(rotation.x*rotation.x+rotation.y*rotation.y+rotation.z*rotation.z)
                if turning > 0.5 {
                    self.goodSince = nil
                    self.report(false,0.5,"Found north. Stop moving and hold your phone still for a moment.",stage:.settling)
                    return
                }
                if self.goodSince == nil { self.goodSince = time }
                let progress = min(1,(time-(self.goodSince ?? time))/1.2)
                guard progress >= 1 else {
                    self.report(false,0.5+progress*0.5,"Found north. Stop moving and hold your phone still for a moment.",stage:.settling)
                    return
                }
                self.ready = true
            }
            if !validHeading || accuracy > 45 {
                if self.poorSince == nil { self.poorSince = time }
                if time-(self.poorSince ?? time) > 5 {
                    self.ready = false; self.goodSince = nil
                    self.report(false,0.25,"Something’s throwing off your compass. Move away from magnets or metal and follow the movement below.",stage:.compass)
                    return
                }
                self.report(true,1,"Gyro on · compass interference, direction may be off",stage:.ready)
            } else {
                self.poorSince = nil
                self.report(true,1,String(format:accuracy <= 25 ? "Gyro on · compass ±%.0f°" : "Gyro on · lower accuracy ±%.0f°",accuracy),stage:.ready)
            }
            let r = motion.attitude.rotationMatrix
            // Reference axes are north, west, up; the back camera points along device -Z.
            let azimuth = atan2(r.m32,-r.m31)
            let altitude = asin(min(1,max(-1,-r.m33)))
            onChange(azimuth,altitude,true)
        }
    }
    private func report(_ ready: Bool,_ progress: Double,_ message: String,stage: MotionCalibrationStage) {
        let percent = Int(progress*100)
        guard percent != lastProgress || message != referenceDescription || stage != lastStage else { return }
        lastProgress = percent; referenceDescription = message; lastStage = stage
        onCalibration?(ready,progress,message,stage)
    }
    private func authorize() {
        guard running else { return }
        guard CLLocationManager.locationServicesEnabled() else {
            blockedMessage = "Turn on Location Services to find north."
            report(false,0,blockedMessage!,stage:.blocked); return
        }
        switch compass.authorizationStatus {
        case .authorizedAlways,.authorizedWhenInUse:
            blockedMessage = nil
            compass.desiredAccuracy = kCLLocationAccuracyBest
            compass.headingFilter = kCLHeadingFilterNone
            compass.startUpdatingLocation(); compass.startUpdatingHeading()
        case .notDetermined: compass.requestWhenInUseAuthorization()
        default:
            blockedMessage = "Allow location access in Settings to set up gyro."
            report(false,0,blockedMessage!,stage:.blocked)
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { authorize() }
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { true }
    func locationManager(_ manager: CLLocationManager,didUpdateHeading newHeading: CLHeading) { heading = newHeading }
    func locationManager(_ manager: CLLocationManager,didUpdateLocations locations: [CLLocation]) {
        guard running, let fix = locations.last, fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 5_000,
              abs(fix.timestamp.timeIntervalSinceNow) < 120 else { return }
        hasLocation = true; blockedMessage = nil
        onLocation?(ObserverLocation(latitude:fix.coordinate.latitude,longitude:fix.coordinate.longitude,elevation:fix.altitude,accuracy:fix.horizontalAccuracy))
    }
    func locationManager(_ manager: CLLocationManager,didFailWithError error: Error) {
        guard running else { return }
        // A heading failure is not a loss of GPS; let the compass recover in place.
        guard (error as? CLError)?.code == .denied else { return }
        hasLocation = false; ready = false
        blockedMessage = "Location access stopped. Allow it while using the app in Settings."
        report(false,0,blockedMessage!,stage:.blocked)
    }

    func stop() {
        running = false; manager.stopDeviceMotionUpdates()
        compass.stopUpdatingHeading(); compass.stopUpdatingLocation()
        heading = nil; hasLocation = false; goodSince = nil; poorSince = nil; lastStage = nil; ready = false; lastProgress = -1; blockedMessage = nil
    }
}
