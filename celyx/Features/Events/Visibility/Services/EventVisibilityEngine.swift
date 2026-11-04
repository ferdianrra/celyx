import Foundation
import simd

@MainActor
protocol EventVisibilityPreparing {
    func prepare(_ event: AstronomyEvent) -> EventViewingPlan
}

/// Astronomy Engine has shared C caches: all ephemeris calls stay on MainActor.
/// This boundary returns immutable, Sendable geometry for background map rendering.
@MainActor
struct EventVisibilityEngine: EventVisibilityPreparing {
    func prepare(_ event: AstronomyEvent) -> EventViewingPlan {
        if event.kind == "season" { return .unavailable("An equinox or solstice is a calendar milestone, not a sight with a viewing zone.") }
        if event.kind == "moon" && event.id.hasPrefix("moon-q0-") {
            return .unavailable("The New Moon’s lit side faces away from Earth. There isn’t a visible lunar disk to map for this event.")
        }
        if event.kind == "eclipse" && event.id.hasPrefix("eclipse-solar-") {
            if let point = event.circumstances?.greatest_at {
                let coordinate = ViewingCoordinate(latitude:point.lat_deg,longitude:point.lon_deg)
                if coordinate.isValid { return .greatestEclipse(time:event.time,coordinate:coordinate) }
            }
            return .unavailable("This feed doesn’t provide a solar-eclipse footprint. We need a published path before we can show a viewing area.")
        }
        if event.kind == "eclipse" && !event.id.hasPrefix("eclipse-lunar-") {
            return .unavailable("This eclipse doesn’t include enough information to identify its viewing geometry.")
        }
        var time = Astronomy_TimeFromDays((event.time.timeIntervalSince1970-946728000)/86400)
        let rotation = Astronomy_Rotation_EQJ_EQD(&time)
        guard rotation.status == ASTRO_SUCCESS else { return .unavailable("The sky position couldn’t be calculated for this date.") }
        func target(name:String,vector:astro_vector_t,infinite:Bool = false) -> EventVisibilityGeometry.Target? {
            guard vector.status == ASTRO_SUCCESS else { return nil }
            let rotated = Astronomy_RotateVector(rotation,vector)
            let xyz = SIMD3(rotated.x,rotated.y,rotated.z)
            let distance = simd_length(xyz)
            guard rotated.status == ASTRO_SUCCESS, distance.isFinite, distance > 0 else { return nil }
            return .init(name:name,equatorOfDate:xyz/distance,distanceAU:infinite ? nil : distance)
        }
        guard let sun = target(name:"Sun",vector:Astronomy_GeoVector(BODY_SUN,time,ABERRATION)) else {
            return .unavailable("The Sun’s position is unavailable for this event.")
        }
        let codes: [String:astro_body_t] = ["moon":BODY_MOON,"mercury":BODY_MERCURY,"venus":BODY_VENUS,"mars":BODY_MARS,
            "jupiter":BODY_JUPITER,"saturn":BODY_SATURN,"uranus":BODY_URANUS,"neptune":BODY_NEPTUNE]
        var targets: [EventVisibilityGeometry.Target] = []
        var magnitude = event.circumstances?.magnitude
        if event.kind == "shower" || event.kind == "flyby" {
            guard let p = event.position, p.ra_deg.isFinite, p.dec_deg.isFinite,
                  (0...360).contains(p.ra_deg), (-90...90).contains(p.dec_deg) else {
                return .unavailable("This event has no verified sky position in the feed. We can’t draw a viewing zone from its date alone.")
            }
            let a = p.ra_deg * .pi/180, d = p.dec_deg * .pi/180
            var vector = astro_vector_t(); vector.status = ASTRO_SUCCESS; vector.t = time
            let distance: Double
            if event.kind == "flyby" {
                guard let ld = event.circumstances?.distance_ld, ld.isFinite, ld > 0 else {
                    return .unavailable("This flyby is missing the distance needed to calculate local parallax. No viewing zone is shown.")
                }
                distance = ld*384400/149597870.69098932
            } else { distance = 1 }
            vector.x = cos(d)*cos(a)*distance; vector.y = cos(d)*sin(a)*distance; vector.z = sin(d)*distance
            if let value = target(name:event.kind == "shower" ? "Meteor radiant" : "Asteroid",vector:vector,infinite:event.kind == "shower") { targets = [value] }
        } else {
            let names = event.kind == "eclipse" ? ["moon"] : event.objects ?? []
            for name in names {
                guard let code = codes[name.lowercased()], let value = target(name:name.capitalized,vector:Astronomy_GeoVector(code,time,ABERRATION)) else {
                    return .unavailable("A required object has no supported ephemeris. We can’t reliably map this event yet.")
                }
                targets.append(value)
                let illumination = Astronomy_Illumination(code,time)
                if illumination.status == ASTRO_SUCCESS, illumination.mag.isFinite {
                    magnitude = max(magnitude ?? -.infinity,illumination.mag)
                }
            }
        }
        guard !targets.isEmpty else { return .unavailable("This event has no supported observing target. No viewing area has been inferred.") }
        let dark = event.kind == "shower" || event.kind == "flyby" || (magnitude ?? 0) > 5.5
        return .geometry(EventVisibilityGeometry(time:event.time,siderealRadians:Astronomy_SiderealTime(&time) * .pi/12,
            sun:sun,targets:targets,minimumAltitude:event.kind == "eclipse" ? 0 : 15,maximumSunAltitude:dark ? -18 : -6,
            magnitude:magnitude,source:event.kind == "shower" || event.kind == "flyby" ? "SpaceCatalog peak coordinates (ICRS/J2000), transformed with Astronomy Engine" : "Astronomy Engine ephemeris at the event’s UTC time"))
    }
}
