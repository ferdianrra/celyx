//
//  AstronomyService.swift
//  celyx
//
//  Created by Ferdiansyah Annora on 02/11/26.
//
import Foundation
import simd

// All calls stay on MainActor: Astronomy Engine maintains internal caches.
// Rotations include precession/nutation. Catalogue proper motion is not in this asset pack.
enum AstronomyService {
    static func snapshot(date: Date, location: ObserverLocation) -> SkySnapshot {
        var time = Astronomy_TimeFromDays((date.timeIntervalSince1970-946728000)/86400) // menggeser waktu di swift ke waktu astronomy enine (berpatokan ke epoch J2000)
        let observer = Astronomy_MakeObserver(location.latitude,location.longitude,max(0,location.elevation))
        let rotation = Astronomy_Rotation_EQJ_HOR(&time,observer)
        func rotate(_ x: Double, _ y: Double, _ z: Double) -> SIMD3<Double> {
            var v = astro_vector_t()
            v.status = ASTRO_SUCCESS; v.x = x; v.y = y; v.z = z; v.t = time
            let h = Astronomy_RotateVector(rotation,v)
            // Engine HOR=(north,west,up); our scene=(east,north,up).
            return SIMD3(-h.y,h.x,h.z)
        }
        func body(_ value: astro_body_t) -> SIMD3<Double> {
            let eq = Astronomy_Equator(value,&time,observer,EQUATOR_OF_DATE,ABERRATION)
            let h = Astronomy_Horizon(&time,observer,eq.ra,eq.dec,REFRACTION_NONE)
            let a = h.azimuth * .pi/180, alt = h.altitude * .pi/180
            return SIMD3(sin(a)*cos(alt),cos(a)*cos(alt),sin(alt))
        }
        let bodies: [astro_body_t] = [BODY_MERCURY,BODY_VENUS,BODY_MARS,BODY_JUPITER,BODY_SATURN]
        let planets = zip(CatalogStar.planets,bodies).compactMap { entry,value -> (star:CatalogStar,direction:SIMD3<Double>)? in
            let illumination = Astronomy_Illumination(value,time)
            guard illumination.status == ASTRO_SUCCESS, illumination.mag.isFinite else { return nil }
            let direction = body(value)
            guard direction.x.isFinite, direction.y.isFinite, direction.z.isFinite else { return nil }
            return (CatalogStar.planet(id:entry.id,name:entry.title,magnitude:illumination.mag),direction)
        }
        return SkySnapshot(date: date,basis: simd_double3x3(columns: (rotate(1,0,0),rotate(0,1,0),rotate(0,0,1))),
                           sunDirection: body(BODY_SUN),moonDirection: body(BODY_MOON),
                           moonIllumination: Astronomy_Illumination(BODY_MOON,time).phase_fraction,planets:planets)
    }
}
