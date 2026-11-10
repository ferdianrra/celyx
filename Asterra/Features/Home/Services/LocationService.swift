//
//  LocationService.swift
//  celyx
//
//  Created by Ferdiansyah Annora on 02/11/26.
//
import CoreLocation
import Foundation

@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var wantsUpdates = false
    var onLocation: ((ObserverLocation) -> Void)?
    var onStatus: ((String) -> Void)?
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 500
    }
    func start() {
        wantsUpdates = true
        guard CLLocationManager.locationServicesEnabled() else { onStatus?("Location Services are off. You can enter coordinates instead."); return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse,.authorizedAlways: manager.startUpdatingLocation()
        case .denied,.restricted: onStatus?("Allow location access in Settings, or enter coordinates yourself.")
        @unknown default: onStatus?("We can’t find your location yet.")
        }
    }
    func stop() { wantsUpdates = false; manager.stopUpdatingLocation() }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if wantsUpdates && manager.authorizationStatus != .notDetermined { start() }
    }
    func locationManager(_ manager: CLLocationManager,didUpdateLocations locations: [CLLocation]) {
        guard wantsUpdates, let p = locations.last, p.horizontalAccuracy >= 0, abs(p.timestamp.timeIntervalSinceNow) < 120 else { return }
        onLocation?(ObserverLocation(latitude:p.coordinate.latitude,longitude:p.coordinate.longitude,
                                     elevation:p.altitude,accuracy:p.horizontalAccuracy))
    }
    func locationManager(_ manager: CLLocationManager,didFailWithError error: Error) {
        onStatus?("We can’t find your location yet. Try again or enter coordinates.")
    }
}
