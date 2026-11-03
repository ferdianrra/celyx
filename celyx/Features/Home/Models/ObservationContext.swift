//
//  ObservationContext.swift
//  celyx
//
//  Created by Ferdiansyah Annora on 02/11/26.
//
import Foundation
import simd

struct ObserverLocation: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var elevation: Double = 0
    var accuracy: Double = 0
    var isManual = false
    var coordinateLabel: String { String(format: "%.3f°, %.3f°", latitude, longitude) }
}

struct SkySnapshot {
    let date: Date
    let basis: simd_double3x3
    let sunDirection: SIMD3<Double>
    let moonDirection: SIMD3<Double>
    let moonIllumination: Double
    var sunAltitude: Double { asin(sunDirection.z) * 180 / .pi }
    var phase: String {
        sunAltitude >= -0.833 ? "Daytime" : sunAltitude > -6 ? "Civil twilight" : sunAltitude > -12 ? "Nautical twilight" : sunAltitude > -18 ? "Astronomical twilight" : "Night"
    }
    func direction(ra: Double, dec: Double) -> SIMD3<Double> {
        let a = ra * .pi/180, d = dec * .pi/180
        return basis * SIMD3(cos(d)*cos(a),cos(d)*sin(a),sin(d))
    }
}

enum SkyQuality: String, CaseIterable, Identifiable {
    case city = "City center", suburban = "Suburbs", rural = "Countryside", dark = "Dark sky"
    var id: String { rawValue }
    var limit: Double { switch self { case .city: 3; case .suburban: 4; case .rural: 5; case .dark: 5.6 } }
}

struct Atmosphere: Equatable {
    var cloudCover: Double?
    var aerosolOpticalDepth: Double?
    var pm25: Double?
    var weatherDate: Date?
    var airDate: Date?
    var weatherError: String?
    var airError: String?
    var fetchedAt: Date?
    var extinction: Double { 0.15 + 1.086 * max(0, min(aerosolOpticalDepth ?? 0.14, 3)) }
}

struct StarObservation: Identifiable {
    let star: CatalogStar
    let direction: SIMD3<Double>
    let dimmedMagnitude: Double
    let likelyVisible: Bool
    let reason: String
    var id: Int { star.id }
    var altitude: Double { asin(min(1,max(-1,direction.z))) * 180 / .pi }
    var azimuth: Double { (atan2(direction.x,direction.y)*180 / .pi+360).truncatingRemainder(dividingBy: 360) }
    var bearing: String { ["N","NE","E","SE","S","SW","W","NW"][Int((azimuth+22.5)/45) % 8] }
    var canCollect: Bool { likelyVisible && altitude >= 15 }
}

struct CollectedStar: Codable, Identifiable {
    let id: Int
    let date: Date
    let latitude: Double
    let longitude: Double
    var photoFilename: String? = nil
    var note: String? = nil
    var identificationNote: String? = nil
}

enum VisibilityEstimator {
    static func limitingMagnitude(sunAltitude: Double, quality: SkyQuality, moonAltitude: Double, moonIllumination: Double) -> Double {
        let darkness = min(1,max(0,(-sunAltitude-6)/12))
        let moonPenalty = moonAltitude > 0 ? moonIllumination * 1.3 : 0
        return -2 + darkness*(quality.limit+2) - moonPenalty
    }
    static func observation(star: CatalogStar, direction: SIMD3<Double>, limit: Double, sunAltitude: Double, atmosphere: Atmosphere) -> StarObservation {
        let alt = asin(min(1,max(-1,direction.z))) * 180 / .pi
        let airMass = alt > 0 ? 1 / (sin(alt * .pi/180) + 0.50572 * pow(alt+6.07995,-1.6364)) : 40
        let dimmed = star.mag + atmosphere.extinction * max(0,airMass-1)
        let visible = alt > 1 && sunAltitude < -6 && dimmed <= limit && (atmosphere.cloudCover ?? 0) < 75
        let reason: String
        if alt <= 0 { reason = "Below the horizon" }
        else if sunAltitude >= -6 { reason = "The sky is still bright" }
        else if alt <= 1 { reason = "Close to the horizon" }
        else if (atmosphere.cloudCover ?? 0) >= 75 { reason = "Cloudy forecast" }
        else if dimmed > limit { reason = "May be too faint to see" }
        else { reason = "May be visible" }
        return StarObservation(star: star,direction: direction,dimmedMagnitude: dimmed,likelyVisible: visible,reason: reason)
    }
}
