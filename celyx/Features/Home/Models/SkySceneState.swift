//
//  SkySceneState.swift
//  celyx
//
//  Created by Ferdiansyah Annora on 02/11/26.
//

import Foundation

struct SkySceneState {
    static let minimumFieldOfView: Double = 6
    static let maximumFieldOfView: Double = 100
    // A visual exploration transition; observing time and celestial positions stay unchanged.
    var spaceBlend: Double {
        let t = min(1,max(0,(35-fieldOfView)/(35-8)))
        return t*t*(3-2*t)
    }
    var renderedExtinction: Double { extinction*(1-spaceBlend) }
    var renderedCloudCover: Double { cloudCover*(1-spaceBlend) }
    var azimuth: Double = 0
    var altitude: Double = 18 * .pi / 180
    var fieldOfView: Double = 72
    var showsMilkyWay = true
    var showsStars = true
    var showsGrid = false
    var showsConstellations = false
    var showsConstellationFigures = true
    var reduceMotion = false
    var equatorialX = SIMD3<Double>(1,0,0)
    var equatorialY = SIMD3<Double>(0,1,0)
    var equatorialZ = SIMD3<Double>(0,0,1)
    var sunDirection = SIMD3<Double>(0,0,-1)
    var moonDirection = SIMD3<Double>(0,0,-1)
    var moonIllumination: Double = 0
    var limitingMagnitude: Double = 3
    // Keep a small bright-star layer visible in the virtual sky, independent of forecasts.
    var starExtinction: Double { min(0.12,renderedExtinction) }
    // Reveal fainter catalogue stars progressively between the default view and full zoom.
    var starLimitingMagnitude: Double {
        let progress = min(1,max(0,(72-fieldOfView)/(72-35)))
        let eased = progress*progress*(3-2*progress)
        let base = min(4.2,max(3.8,limitingMagnitude))
        return base + (6.5-base)*eased
    }
    var extinction: Double = 0.3
    var cloudCover: Double = 0
    var hasLocation = false
}

enum LookMode: String, CaseIterable, Identifiable {
    case touch = "Touch", motion = "Gyro"
    var id: String { rawValue }
}

struct CatalogStar: Decodable, Identifiable {
    let id: Int
    let ra_deg: Double
    let dec_deg: Double
    let mag: Double
    let bv: Double?
    let name: String?
    let designation: String?
    let distance_ly: Double?
    let con: String?
    let collectible_candidate: Bool?
    static let sun = CatalogStar(id:-1,ra_deg:0,dec_deg:0,mag:-26.74,bv:0.65,name:"Sun",designation:"Sun",distance_ly:nil,con:nil,collectible_candidate:true)
    static let moon = CatalogStar(id:-2,ra_deg:0,dec_deg:0,mag:-12.7,bv:nil,name:"Moon",designation:"Moon",distance_ly:nil,con:nil,collectible_candidate:true)
    var isMoon: Bool { id == Self.moon.id }
    static let planets: [CatalogStar] = [
        planet(id:-3,name:"Mercury",magnitude:0),planet(id:-4,name:"Venus",magnitude:-4),
        planet(id:-5,name:"Mars",magnitude:1),planet(id:-6,name:"Jupiter",magnitude:-2),
        planet(id:-7,name:"Saturn",magnitude:1)
    ]
    static func planet(id: Int,name: String,magnitude: Double) -> CatalogStar {
        CatalogStar(id:id,ra_deg:0,dec_deg:0,mag:magnitude,bv:nil,name:name,designation:name,
            distance_ly:nil,con:nil,collectible_candidate:true)
    }
    var isPlanet: Bool { (-7 ... -3).contains(id) }
    var isSolarDisc: Bool { isSun || isMoon }
    var isSolarSystemBody: Bool { isSun || isMoon || isPlanet }
    var kind: String { isSun ? "Sun" : isMoon ? "Moon" : isPlanet ? "Planet" : "Star" }
    var isSun: Bool { id == Self.sun.id }
    var hasCommonName: Bool { !(name?.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ?? true) }
    var temperature: Double? {
        guard let bv else { return nil }
        return 4600*(1/(0.92*bv+1.7)+1/(0.92*bv+0.62))
    }
    var rgb: SIMD3<Double> {
        if isPlanet {
            switch id {
            case -3: return SIMD3(0.70,0.67,0.63)
            case -4: return SIMD3(0.97,0.88,0.69)
            case -5: return SIMD3(0.90,0.41,0.23)
            case -6: return SIMD3(0.90,0.75,0.60)
            default: return SIMD3(0.88,0.80,0.57)
            }
        }
        let t = min(1,max(0,((temperature ?? 7000)-3000)/12000))
        return SIMD3(1-0.35*t,0.58+0.32*min(t*2,1),0.35+0.65*min(t*2,1))
    }
    var title: String {
        for value in [name,designation] {
            if let title = value?.trimmingCharacters(in:.whitespacesAndNewlines), !title.isEmpty { return title }
        }
        // This is our bundled catalog’s ID, not an inferred official star name.
        return "Star \(id)"
    }
}

struct Constellation: Decodable {
    let name: String?
    let english: String?
    let segments: [[Int]]
}

// Resources are resolved in one place, including Xcode's flattened resource bundles.
enum SkyAssets {
    static func url(_ name: String, extension ext: String) throws -> URL {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url }
        let root = Bundle.main.resourceURL!
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            if url.lastPathComponent == "\(name).\(ext)" { return url }
        }
        throw CocoaError(.fileNoSuchFile)
    }
    static func stars() throws -> [CatalogStar] {
        try JSONDecoder().decode([CatalogStar].self, from: Data(contentsOf: url("stars", extension: "json")))
    }
}
