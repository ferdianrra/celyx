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
    var planets: [(star:CatalogStar,direction:SIMD3<Double>)] = []
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
    var placeName: String? = nil
}

nonisolated struct VisibilityFilters: Equatable, Sendable {
    var daylight = true
    var horizon = true
    var brightness = true
    var lightPollution = true
    var moonlight = true
    var clouds = true
    var atmosphericExtinction = true
    var isModified: Bool { self != Self() }
}

enum VisibilityEstimator {
    static func visibleObjects(stars: [CatalogStar],sky: SkySnapshot,quality: SkyQuality,atmosphere: Atmosphere,filters: VisibilityFilters = .init()) -> [StarObservation] {
        let moonAltitude = asin(min(1,max(-1,sky.moonDirection.z)))*180 / .pi
        let limit = limitingMagnitude(sunAltitude:sky.sunAltitude,quality:quality,moonAltitude:moonAltitude,moonIllumination:sky.moonIllumination,filters:filters)
        let targets = stars.filter { !$0.isSolarSystemBody }.map { ($0,sky.direction(ra:$0.ra_deg,dec:$0.dec_deg)) }
            + sky.planets.map { ($0.star,$0.direction) }
        return targets.map { observation(star:$0.0,direction:$0.1,limit:limit,sunAltitude:sky.sunAltitude,atmosphere:atmosphere,filters:filters) }
            .filter(\.likelyVisible).sorted {
                if $0.dimmedMagnitude != $1.dimmedMagnitude { return $0.dimmedMagnitude < $1.dimmedMagnitude }
                return $0.id < $1.id
            }
    }
    static func limitingMagnitude(sunAltitude: Double, quality: SkyQuality, moonAltitude: Double, moonIllumination: Double, filters: VisibilityFilters = .init()) -> Double {
        let darkness = filters.daylight ? min(1,max(0,(-sunAltitude-6)/12)) : 1
        let moonPenalty = filters.moonlight && moonAltitude > 0 ? moonIllumination * 1.3 : 0
        let skyLimit = filters.lightPollution ? quality.limit : SkyQuality.dark.limit
        return -2 + darkness*(skyLimit+2) - moonPenalty
    }
    static func observation(star: CatalogStar, direction: SIMD3<Double>, limit: Double, sunAltitude: Double, atmosphere: Atmosphere, filters: VisibilityFilters = .init()) -> StarObservation {
        let alt = asin(min(1,max(-1,direction.z))) * 180 / .pi
        let airMass = alt > 0 ? 1 / (sin(alt * .pi/180) + 0.50572 * pow(alt+6.07995,-1.6364)) : 40
        let dimmed = star.mag + (filters.atmosphericExtinction ? atmosphere.extinction * max(0,airMass-1) : 0)
        let reason: String
        if filters.horizon && alt <= 0 { reason = "Below the horizon" }
        else if filters.daylight && sunAltitude >= -6 { reason = "The sky is still bright" }
        else if filters.horizon && alt <= 1 { reason = "Close to the horizon" }
        else if filters.clouds && (atmosphere.cloudCover ?? 0) >= 75 { reason = "Cloudy forecast" }
        else if filters.brightness && dimmed > limit { reason = "May be too faint to see" }
        else { reason = filters.isModified ? "Matches selected filters" : "May be visible" }
        let visible = (!filters.horizon || alt > 1)
            && (!filters.daylight || sunAltitude < -6)
            && (!filters.clouds || (atmosphere.cloudCover ?? 0) < 75)
            && (!filters.brightness || dimmed <= limit)
        return StarObservation(star: star,direction: direction,dimmedMagnitude: dimmed,likelyVisible: visible,reason: reason)
    }
}
