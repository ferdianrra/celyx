import CoreLocation
import Foundation
import Observation
import simd

/// Computes Sky Calendar events with Astronomy Engine (github.com/cosinekitty/astronomy) for the user's
/// own location. Event instants are global (full Moon, conjunction, meteor peak…); the viewing window
/// and direction are worked out for the observer, and every time is shown in the device's time zone.
/// Astronomy Engine keeps internal caches, so all calls stay on the main actor.
@MainActor @Observable
final class SkyEventCatalog {
    static let shared = SkyEventCatalog()

    /// The observer used for viewing windows and directions.
    private(set) var location: ObserverLocation?
    /// Bumped whenever cached events become stale, so observing views refresh.
    private(set) var revision = 0
    @ObservationIgnored private var cache: [Date: [SkyEvent]] = [:]
    @ObservationIgnored private var cachedTimeZone = TimeZone.current

    /// Feed the latest observer location. Small GPS jitter keeps the cached events.
    func update(location value: ObserverLocation?) {
        guard let value else { return }
        if let location, abs(location.latitude - value.latitude) < 0.1,
            abs(location.longitude - value.longitude) < 0.1
        {
            return
        }
        location = value
        invalidate()
    }

    /// Events whose viewing window overlaps `interval`.
    func events(in interval: DateInterval) -> [SkyEvent] {
        _ = revision
        if cachedTimeZone != TimeZone.current {
            cachedTimeZone = TimeZone.current
            cache.removeAll()
        }
        // Event instants are grouped by UTC month; pad so windows that spill across a month edge still show.
        var month = Self.utcMonthStart(interval.start.addingTimeInterval(-3 * 86400))
        let last = interval.end.addingTimeInterval(3 * 86400)
        var result: [SkyEvent] = []
        while month < last {
            let next = Self.utc.date(byAdding: .month, value: 1, to: month) ?? last
            if cache[month] == nil { cache[month] = compute(DateInterval(start: month, end: next)) }
            result += cache[month] ?? []
            month = next
        }
        return result.filter { $0.start < interval.end && $0.end >= interval.start }
            .sorted { $0.start < $1.start }
    }

    /// The last 6 and next 12 months, used where the app needs every event (e.g. collected events).
    var catalogue: [SkyEvent] {
        let now = Date()
        let start = Self.utc.date(byAdding: .month, value: -6, to: now) ?? now
        let end = Self.utc.date(byAdding: .month, value: 12, to: now) ?? now
        return events(in: DateInterval(start: start, end: end))
    }

    private func invalidate() {
        cache.removeAll()
        revision += 1
    }

    // MARK: Observer

    private var observer: ObserverLocation {
        if let location { return location }
        if let fix = CLLocationManager().location {
            return ObserverLocation(
                latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude,
                elevation: fix.altitude)
        }
        // No fix yet: approximate the longitude from the device time zone until GPS arrives.
        let hours = Double(TimeZone.current.secondsFromGMT()) / 3600
        return ObserverLocation(latitude: 0, longitude: max(-180, min(180, hours * 15)), isManual: true)
    }

    // MARK: Computation

    private func compute(_ month: DateInterval) -> [SkyEvent] {
        let place = observer
        let sky = SkySampler(location: place)
        var events: [SkyEvent] = []
        events += fullMoons(month, sky)
        events += lunarEclipses(month, sky)
        events += solarEclipses(month, sky)
        events += oppositions(month, sky)
        events += elongations(month, sky)
        events += venusPeak(month, sky)
        events += conjunctions(month, sky)
        events += meteorShowers(month, sky)
        return events
    }

    private func fullMoons(_ month: DateInterval, _ sky: SkySampler) -> [SkyEvent] {
        var events: [SkyEvent] = []
        var search = month.start
        while search < month.end {
            let found = Astronomy_SearchMoonPhase(180, Self.astro(search), 40)
            guard found.status == ASTRO_SUCCESS else { break }
            let peak = Self.date(found.time)
            guard peak < month.end else { break }
            search = peak.addingTimeInterval(5 * 86400)
            guard let window = sky.window(near: peak, target: .body("Moon"), minAltitude: 5, sunBelow: -6)
            else { continue }
            let localMonth = Calendar.current.component(.month, from: peak)
            let previous = Self.date(
                Astronomy_SearchMoonPhase(180, Self.astro(peak.addingTimeInterval(-35 * 86400)), 40).time)
            let isBlue = Calendar.current.isDate(previous, equalTo: peak, toGranularity: .month)
            let distance = Astronomy_GeoMoon(found.time)
            let km = sqrt(distance.x * distance.x + distance.y * distance.y + distance.z * distance.z) * 149_597_870.7
            let isSuper = km < 362_000
            var title = isBlue ? "Blue Moon" : Self.moonNames[localMonth - 1] + " Moon"
            if isSuper { title = "Super " + title }
            let art = Self.moonArt[(localMonth - 1) % Self.moonArt.count]
            events.append(
                event(
                    id: "full-moon", peak: peak, kind: .moon, title: title, window: window,
                    about: (isBlue
                        ? "A second full Moon in the same calendar month — the rare “Blue Moon”."
                        : "\(Self.monthName(peak))’s full Moon rises around sunset and lights up the sky all night long.")
                        + (isSuper
                            ? "\n\nIt is also a supermoon: only \(Int(km).formatted()) km away, so it looks a little bigger and brighter than usual."
                            : ""),
                    tips: "Catch it just after moonrise, when it sits low on the horizon and looks its biggest.",
                    artwork: art))
        }
        return events
    }

    private func lunarEclipses(_ month: DateInterval, _ sky: SkySampler) -> [SkyEvent] {
        let eclipse = Astronomy_SearchLunarEclipse(Self.astro(month.start))
        guard eclipse.status == ASTRO_SUCCESS else { return [] }
        let peak = Self.date(eclipse.peak)
        guard peak < month.end else { return [] }
        let half = (eclipse.sd_partial > 0 ? eclipse.sd_partial : eclipse.sd_penum) * 60
        let span = DateInterval(start: peak.addingTimeInterval(-half), end: peak.addingTimeInterval(half))
        guard let window = sky.window(within: span, target: .body("Moon"), minAltitude: 0, sunBelow: 90)
        else { return [] }
        let name =
            switch eclipse.kind {
            case ECLIPSE_TOTAL: "Total Lunar Eclipse"
            case ECLIPSE_PARTIAL: "Partial Lunar Eclipse"
            default: "Penumbral Lunar Eclipse"
            }
        return [
            event(
                id: "lunar-eclipse", peak: peak, kind: .moon, title: name, window: window,
                about:
                    "The Moon slides into Earth’s shadow. "
                    + (eclipse.kind == ECLIPSE_TOTAL
                        ? "At totality it can glow a deep coppery red, lit only by sunlight bent through Earth’s atmosphere."
                        : eclipse.kind == ECLIPSE_PARTIAL
                            ? "Part of the Moon looks as if a bite has been taken out of it."
                            : "Only the faint outer shadow touches the Moon, so look for a subtle darkening on one side."),
                tips: "No equipment needed and it’s completely safe to watch. Binoculars bring out the colours.",
                artwork: Self.art(.coldMoon))
        ]
    }

    private func solarEclipses(_ month: DateInterval, _ sky: SkySampler) -> [SkyEvent] {
        let eclipse = Astronomy_SearchLocalSolarEclipse(Self.astro(month.start), sky.observer)
        guard eclipse.status == ASTRO_SUCCESS else { return [] }
        let peak = Self.date(eclipse.peak.time)
        guard peak < month.end else { return [] }
        let span = DateInterval(start: Self.date(eclipse.partial_begin.time), end: Self.date(eclipse.partial_end.time))
        guard let window = sky.window(within: span, target: .body("Sun"), minAltitude: 0, sunBelow: 90)
        else { return [] }
        let name =
            switch eclipse.kind {
            case ECLIPSE_TOTAL: "Total Solar Eclipse"
            case ECLIPSE_ANNULAR: "Annular Solar Eclipse"
            default: "Partial Solar Eclipse"
            }
        return [
            event(
                id: "solar-eclipse", peak: peak, kind: .event, title: name, window: window,
                about:
                    "The Moon passes in front of the Sun as seen from your location, covering about \(Int((eclipse.obscuration * 100).rounded()))% of its disc at the peak.",
                tips:
                    "Never look at the Sun directly. Use certified eclipse glasses or a pinhole projector the whole time.",
                artwork: Self.art(.wolfMoon))
        ]
    }

    private func oppositions(_ month: DateInterval, _ sky: SkySampler) -> [SkyEvent] {
        let bodies: [(astro_body_t, String)] = [
            (BODY_MARS, "Mars"), (BODY_JUPITER, "Jupiter"), (BODY_SATURN, "Saturn"),
            (BODY_URANUS, "Uranus"), (BODY_NEPTUNE, "Neptune"),
        ]
        return bodies.compactMap { body, name in
            let found = Astronomy_SearchRelativeLongitude(body, 0, Self.astro(month.start))
            guard found.status == ASTRO_SUCCESS else { return nil }
            let peak = Self.date(found.time)
            guard peak < month.end,
                let window = sky.window(near: peak, target: .body(name), minAltitude: 10, sunBelow: -6)
            else { return nil }
            let faint = body == BODY_URANUS || body == BODY_NEPTUNE
            return event(
                id: "\(name.lowercased())-opposition", peak: peak, kind: .object, title: "\(name) at Opposition",
                window: window,
                about:
                    "Earth passes between the Sun and \(name), so the planet is at its closest and brightest for the year and stays up all night.",
                tips: faint
                    ? "\(name) is very faint. Use binoculars or a small telescope under a dark sky."
                    : "\(name) is easy to spot with the naked eye — look for a bright, steady point that doesn’t twinkle.",
                artwork: Self.art(.uranus))
        }
    }

    private func elongations(_ month: DateInterval, _ sky: SkySampler) -> [SkyEvent] {
        [(BODY_MERCURY, "Mercury"), (BODY_VENUS, "Venus")].compactMap { body, name in
            let found = Astronomy_SearchMaxElongation(body, Self.astro(month.start))
            guard found.status == ASTRO_SUCCESS else { return nil }
            let peak = Self.date(found.time)
            guard peak < month.end,
                let window = sky.window(near: peak, target: .body(name), minAltitude: 3, sunBelow: -4)
            else { return nil }
            let evening = found.visibility == VISIBLE_EVENING
            return event(
                id: "\(name.lowercased())-elongation", peak: peak, kind: .object,
                title: "\(name) at Greatest \(evening ? "Eastern" : "Western") Elongation", window: window,
                about:
                    "\(name) reaches its widest separation from the Sun — \(Int(found.elongation.rounded()))° — making this one of the best times to see it in the \(evening ? "evening" : "morning") sky.",
                tips: evening
                    ? "Look low toward the sunset glow shortly after the Sun goes down."
                    : "Look low toward where the Sun will rise, in the hour before dawn.",
                artwork: Self.art(.venus))
        }
    }

    private func venusPeak(_ month: DateInterval, _ sky: SkySampler) -> [SkyEvent] {
        let found = Astronomy_SearchPeakMagnitude(BODY_VENUS, Self.astro(month.start))
        guard found.status == ASTRO_SUCCESS else { return [] }
        let peak = Self.date(found.time)
        guard peak < month.end,
            let window = sky.window(near: peak, target: .body("Venus"), minAltitude: 3, sunBelow: -4)
        else { return [] }
        return [
            event(
                id: "venus-brightness", peak: peak, kind: .object, title: "Venus at Greatest Brightness",
                window: window,
                about:
                    "Venus shines at magnitude \(found.mag.formatted(.number.precision(.fractionLength(1)))), outshining every other planet and star in the sky.",
                tips: "It’s the brightest point of light you’ll see — once it’s dark enough, you can’t miss it.",
                artwork: Self.art(.venus))
        ]
    }

    private func conjunctions(_ month: DateInterval, _ sky: SkySampler) -> [SkyEvent] {
        let planets: [(astro_body_t, String)] = [
            (BODY_VENUS, "Venus"), (BODY_MARS, "Mars"), (BODY_JUPITER, "Jupiter"), (BODY_SATURN, "Saturn"),
        ]
        var pairs: [(astro_body_t, String, astro_body_t, String, Double, TimeInterval)] = []
        for (body, name) in planets { pairs.append((BODY_MOON, "Moon", body, name, 4, 2 * 3600)) }
        for i in planets.indices {
            for j in planets.indices where j > i {
                pairs.append((planets[i].0, planets[i].1, planets[j].0, planets[j].1, 2, 12 * 3600))
            }
        }
        var events: [SkyEvent] = []
        for (a, aName, b, bName, limit, step) in pairs {
            for (peak, separation) in Self.closeApproaches(a, b, in: month, step: step, limit: limit) {
                // Skip pairs lost in the Sun's glare.
                guard Self.separation(a, BODY_SUN, at: peak) > 15,
                    let window = sky.window(
                        near: peak, target: .pair(aName, bName), minAltitude: 8, sunBelow: -6)
                else { continue }
                let isMoon = a == BODY_MOON
                let angle = separation.formatted(.number.precision(.fractionLength(1)))
                events.append(
                    event(
                        id: "\(aName.lowercased())-\(bName.lowercased())", peak: peak, kind: .event,
                        title: "\(aName) & \(bName) Conjunction", window: window,
                        about: isMoon
                            ? "The Moon passes just \(angle)° from \(bName), making the planet easy to find."
                            : "\(aName) and \(bName) appear only \(angle)° apart. Although millions of kilometres apart, the two planets seem to meet from our point of view on Earth.",
                        tips: isMoon
                            ? "Find the Moon first, then look for the bright, steady point of light beside it."
                            : "Both fit in one binocular view. Look for two bright points that don’t twinkle.",
                        artwork: Self.art(isMoon ? .moonJupiter : .marsJupiter)))
            }
        }
        return events
    }

    private func meteorShowers(_ month: DateInterval, _ sky: SkySampler) -> [SkyEvent] {
        Self.showers.compactMap { shower in
            let found = Astronomy_SearchSunLongitude(shower.solarLongitude, Self.astro(month.start), 32)
            guard found.status == ASTRO_SUCCESS else { return nil }
            let peak = Self.date(found.time)
            guard peak < month.end,
                let window = sky.window(
                    near: peak, target: .radiant(ra: shower.ra, dec: shower.dec), minAltitude: 10, sunBelow: -12)
            else { return nil }
            let moon = Astronomy_Illumination(BODY_MOON, found.time).phase_fraction
            let moonNote =
                moon > 0.6
                ? " A bright Moon (\(Int((moon * 100).rounded()))% lit) will wash out the fainter meteors this year."
                : moon < 0.25 ? " The Moon is dark, so conditions are excellent." : ""
            return event(
                id: shower.id, peak: peak, kind: .event, title: shower.title, window: window,
                about: shower.about + "\n\nUnder a dark sky expect up to \(shower.rate) meteors an hour at the peak.",
                tips: "Get away from city lights, lie back and give your eyes 20 minutes to adjust. No telescope needed."
                    + moonNote,
                artwork: Self.art(.meteor))
        }
    }

    // MARK: Building events

    private func event(
        id: String, peak: Date, kind: SkyEvent.Kind, title: String, window: SkySampler.Window, about: String,
        tips: String, artwork: SkyEvent.Artwork
    ) -> SkyEvent {
        let dates = Self.dateText(window.start, window.end)
        return SkyEvent(
            id: "\(id)-\(Self.idFormat.string(from: peak))", kind: kind, title: title,
            start: window.start, end: window.end, headerDate: dates.header, detailDate: dates.detail,
            viewingTime: Self.timeText(window.start) + " – " + Self.timeText(window.end),
            direction: Self.directionText(azimuth: window.azimuth, altitude: window.altitude),
            about: about, tips: tips, artwork: artwork, target: window.target)
    }

    private static func dateText(_ start: Date, _ end: Date) -> (header: String, detail: String) {
        let calendar = Calendar.current
        let us = Locale(identifier: "en_US")
        let last = end.addingTimeInterval(-1)
        if calendar.isDate(start, inSameDayAs: last) {
            let text = start.formatted(.dateTime.month(.wide).day().year().locale(us))
            return (text, text)
        }
        let month = start.formatted(.dateTime.month(.wide).locale(us))
        let year = calendar.component(.year, from: last)
        if calendar.isDate(start, equalTo: last, toGranularity: .month) {
            let a = calendar.component(.day, from: start), b = calendar.component(.day, from: last)
            return ("\(month) \(a)-\(b), \(year)", "\(month) \(a)–\(b), \(year)")
        }
        let text =
            start.formatted(.dateTime.month(.wide).day().locale(us)) + " – "
            + last.formatted(.dateTime.month(.wide).day().year().locale(us))
        return (text, text)
    }

    private static func timeText(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().hour(.twoDigits(amPM: .abbreviated)).minute(.twoDigits)
            .locale(Locale(identifier: "en_US")))
    }

    private static func directionText(azimuth: Double, altitude: Double) -> String {
        let names = [
            "Northern", "North-Eastern", "Eastern", "South-Eastern", "Southern", "South-Western", "Western",
            "North-Western",
        ]
        let index = Int(((azimuth.truncatingRemainder(dividingBy: 360) + 360 + 22.5) / 45)) % 8
        if altitude >= 75 { return "Overhead" }
        return "\(names[index]) Sky · \(Int(altitude.rounded()))° up"
    }

    // MARK: Astronomy helpers

    static func astro(_ date: Date) -> astro_time_t {
        Astronomy_TimeFromDays((date.timeIntervalSince1970 - 946_728_000) / 86400)
    }
    static func date(_ time: astro_time_t) -> Date {
        Date(timeIntervalSince1970: time.ut * 86400 + 946_728_000)
    }

    /// Where a target sits for an observer: azimuth/altitude in degrees (refraction included) and the
    /// matching horizon unit vector (east, north, up) used by the camera finder.
    static func horizon(of target: SkyEvent.Target, at date: Date, location: ObserverLocation)
        -> (azimuth: Double, altitude: Double, direction: SIMD3<Double>)
    {
        horizon(
            of: target, at: date,
            observer: Astronomy_MakeObserver(location.latitude, location.longitude, max(0, location.elevation)))
    }

    fileprivate static func horizon(of target: SkyEvent.Target, at date: Date, observer: astro_observer_t)
        -> (azimuth: Double, altitude: Double, direction: SIMD3<Double>)
    {
        func vector(_ azimuth: Double, _ altitude: Double) -> SIMD3<Double> {
            let a = azimuth * .pi / 180, h = altitude * .pi / 180
            return SIMD3(sin(a) * cos(h), cos(a) * cos(h), sin(h))
        }
        var time = astro(date)
        switch target {
        case .body(let name):
            let body = Astronomy_BodyCode(name)
            let eq = Astronomy_Equator(body, &time, observer, EQUATOR_OF_DATE, ABERRATION)
            let h = Astronomy_Horizon(&time, observer, eq.ra, eq.dec, REFRACTION_NORMAL)
            return (h.azimuth, h.altitude, vector(h.azimuth, h.altitude))
        case .pair(let a, let b):
            let first = horizon(of: .body(a), at: date, observer: observer)
            let second = horizon(of: .body(b), at: date, observer: observer)
            let mid = simd_normalize(first.direction + second.direction)
            let azimuth = (atan2(mid.x, mid.y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
            // Both must be up, so the pair counts as high as its lower member.
            return (azimuth, min(first.altitude, second.altitude), mid)
        case .radiant(let ra, let dec):
            let h = Astronomy_Horizon(&time, observer, ra, dec, REFRACTION_NORMAL)
            return (h.azimuth, h.altitude, vector(h.azimuth, h.altitude))
        }
    }

    fileprivate static func separation(_ a: astro_body_t, _ b: astro_body_t, at date: Date) -> Double {
        let time = astro(date)
        let angle = Astronomy_AngleBetween(
            Astronomy_GeoVector(a, time, ABERRATION), Astronomy_GeoVector(b, time, ABERRATION))
        return angle.status == ASTRO_SUCCESS ? angle.angle : .infinity
    }

    /// Local minima of the geocentric separation between two bodies, refined to about a minute.
    private static func closeApproaches(
        _ a: astro_body_t, _ b: astro_body_t, in month: DateInterval, step: TimeInterval, limit: Double
    ) -> [(Date, Double)] {
        var samples: [(Date, Double)] = []
        var t = month.start.addingTimeInterval(-step)
        while t <= month.end.addingTimeInterval(step) {
            samples.append((t, separation(a, b, at: t)))
            t += step
        }
        guard samples.count > 2 else { return [] }
        var found: [(Date, Double)] = []
        for i in 1..<(samples.count - 1)
        where samples[i].1 <= samples[i - 1].1 && samples[i].1 < samples[i + 1].1 && samples[i].1 < limit + 1 {
            // Golden-section refinement between the neighbouring samples.
            var lo = samples[i - 1].0.timeIntervalSince1970, hi = samples[i + 1].0.timeIntervalSince1970
            let ratio = (sqrt(5) - 1) / 2
            while hi - lo > 60 {
                let m1 = hi - ratio * (hi - lo), m2 = lo + ratio * (hi - lo)
                if separation(a, b, at: Date(timeIntervalSince1970: m1))
                    < separation(a, b, at: Date(timeIntervalSince1970: m2))
                {
                    hi = m2
                } else {
                    lo = m1
                }
            }
            let peak = Date(timeIntervalSince1970: (lo + hi) / 2)
            let value = separation(a, b, at: peak)
            if value < limit, month.contains(peak), peak < month.end { found.append((peak, value)) }
        }
        return found
    }

    private static let utc: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "UTC")!
        return value
    }()
    private static func utcMonthStart(_ date: Date) -> Date {
        utc.dateInterval(of: .month, for: date)?.start ?? date
    }
    private static let idFormat: DateFormatter = {
        let value = DateFormatter()
        value.calendar = utc
        value.timeZone = utc.timeZone
        value.locale = Locale(identifier: "en_US_POSIX")
        value.dateFormat = "yyyy-MM-dd"
        return value
    }()
    private static func monthName(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).locale(Locale(identifier: "en_US")))
    }

    // MARK: Content

    private static let moonNames = [
        "Wolf", "Snow", "Worm", "Pink", "Flower", "Strawberry", "Buck", "Sturgeon", "Harvest", "Hunter’s",
        "Beaver", "Cold",
    ]

    private enum Art { case beaverMoon, coldMoon, wolfMoon, meteor, uranus, venus, marsJupiter, moonJupiter }
    /// Card placements from the Figma design.
    private static func art(_ value: Art) -> SkyEvent.Artwork {
        switch value {
        case .beaverMoon: .init(asset: "celyx-event-beaver-moon", size: 146, x: -30, y: -18, flipped: true)
        case .coldMoon: .init(asset: "celyx-event-cold-moon", size: 146, x: -26, y: -18, flipped: true)
        case .wolfMoon: .init(asset: "celyx-event-wolf-moon", size: 146, x: -32, y: -19, flipped: true)
        case .meteor: .init(asset: "celyx-event-meteor-card", size: 281, x: -100, y: -85)
        case .uranus: .init(asset: "celyx-event-uranus", size: 155, x: -30, y: -23)
        case .venus: .init(asset: "celyx-event-venus", size: 146, x: -26, y: -18)
        case .marsJupiter: .init(asset: "celyx-event-mars-jupiter", size: 223, x: -65, y: -53)
        case .moonJupiter: .init(asset: "celyx-event-moon-jupiter", size: 169, x: -28, y: -24, flipped: true)
        }
    }
    private static let moonArt: [SkyEvent.Artwork] = [art(.wolfMoon), art(.beaverMoon), art(.coldMoon)]

    private struct Shower {
        let id: String
        let title: String
        /// Solar longitude (J2000) of the peak, from the IMO meteor shower calendar.
        let solarLongitude: Double
        /// Radiant in hours / degrees.
        let ra: Double
        let dec: Double
        let rate: Int
        let about: String
    }
    private static let showers: [Shower] = [
        Shower(
            id: "quadrantids", title: "Quadrantid Meteor Shower", solarLongitude: 283.15, ra: 15.33, dec: 49.5,
            rate: 110,
            about: "A short, sharp shower from the northern sky, left behind by the asteroid 2003 EH1."),
        Shower(
            id: "lyrids", title: "Lyrid Meteor Shower", solarLongitude: 32.32, ra: 18.07, dec: 33.3, rate: 18,
            about: "One of the oldest recorded showers, made of dust from Comet Thatcher and radiating near Vega."),
        Shower(
            id: "eta-aquariids", title: "Eta Aquariid Meteor Shower", solarLongitude: 45.5, ra: 22.53, dec: -1.0,
            rate: 50, about: "Fast meteors from debris of Halley’s Comet, best seen in the hours before dawn."),
        Shower(
            id: "delta-aquariids", title: "Southern Delta Aquariid Meteor Shower", solarLongitude: 127.0,
            ra: 22.67, dec: -16.4, rate: 25, about: "A steady summer shower with faint meteors from Aquarius."),
        Shower(
            id: "perseids", title: "Perseid Meteor Shower", solarLongitude: 140.0, ra: 3.2, dec: 58.0, rate: 100,
            about: "The most popular shower of the year — bright, fast meteors from Comet Swift–Tuttle."),
        Shower(
            id: "draconids", title: "Draconid Meteor Shower", solarLongitude: 195.4, ra: 17.47, dec: 54.0,
            rate: 10, about: "Slow meteors from Comet Giacobini–Zinner, best seen in the early evening."),
        Shower(
            id: "orionids", title: "Orionid Meteor Shower", solarLongitude: 208.0, ra: 6.33, dec: 15.6, rate: 20,
            about: "Swift meteors from Halley’s Comet streaking out of Orion’s raised club."),
        Shower(
            id: "leonids", title: "Leonid Meteor Shower", solarLongitude: 235.27, ra: 10.27, dec: 21.6, rate: 15,
            about:
                "The Leonids streak out of the constellation Leo as Earth passes through dust left behind by Comet Tempel–Tuttle."
        ),
        Shower(
            id: "geminids", title: "Geminid Meteor Shower", solarLongitude: 262.2, ra: 7.47, dec: 32.3, rate: 150,
            about: "One of the richest meteor showers of the year, with bright, slow meteors radiating from Gemini."),
        Shower(
            id: "ursids", title: "Ursid Meteor Shower", solarLongitude: 270.7, ra: 14.47, dec: 74.8, rate: 10,
            about: "A modest shower near the winter solstice, radiating from the Little Dipper."),
    ]
}

/// Samples the sky for one observer to find when a target is up while the sky is dark.
@MainActor
private struct SkySampler {
    typealias Target = SkyEvent.Target
    struct Window {
        let target: Target
        let start: Date
        let end: Date
        /// Direction at the best moment (target highest).
        let azimuth: Double
        let altitude: Double
    }

    let observer: astro_observer_t

    init(location: ObserverLocation) {
        observer = Astronomy_MakeObserver(location.latitude, location.longitude, max(0, location.elevation))
    }

    /// The dark-sky window closest to `peak`, within ±18 hours.
    func window(near peak: Date, target: Target, minAltitude: Double, sunBelow: Double) -> Window? {
        let span = DateInterval(start: peak.addingTimeInterval(-18 * 3600), end: peak.addingTimeInterval(18 * 3600))
        return window(within: span, target: target, minAltitude: minAltitude, sunBelow: sunBelow, near: peak)
    }

    /// The part of `span` where the target is above `minAltitude` and the Sun below `sunBelow`.
    func window(
        within span: DateInterval, target: Target, minAltitude: Double, sunBelow: Double, near peak: Date? = nil
    ) -> Window? {
        let step: TimeInterval = span.duration > 6 * 3600 ? 600 : 120
        var segments: [[(Date, Double, Double)]] = []
        var current: [(Date, Double, Double)] = []
        var t = span.start
        while t <= span.end {
            let up = horizon(target, at: t)
            let sun = sunBelow >= 90 ? -90 : horizon(.body("Sun"), at: t).altitude
            if up.altitude >= minAltitude && sun < sunBelow {
                current.append((t, up.azimuth, up.altitude))
            } else if !current.isEmpty {
                segments.append(current)
                current = []
            }
            t += step
        }
        if !current.isEmpty { segments.append(current) }
        let anchor = peak ?? span.start
        func distance(_ segment: [(Date, Double, Double)]) -> TimeInterval {
            let first = segment.first!.0, last = segment.last!.0
            if anchor >= first && anchor <= last { return 0 }
            return min(abs(first.timeIntervalSince(anchor)), abs(last.timeIntervalSince(anchor)))
        }
        guard
            let best = segments.filter({ $0.count > 1 || step < 600 })
                .min(by: { distance($0) == distance($1) ? $0.count > $1.count : distance($0) < distance($1) }),
            let top = best.max(by: { $0.2 < $1.2 })
        else { return nil }
        return Window(
            target: target, start: Self.round(best.first!.0, down: true), end: Self.round(best.last!.0, down: false),
            azimuth: top.1, altitude: top.2)
    }

    private func horizon(_ target: Target, at date: Date) -> (azimuth: Double, altitude: Double) {
        let value = SkyEventCatalog.horizon(of: target, at: date, observer: observer)
        return (value.azimuth, value.altitude)
    }

    /// Rounds to 5 minutes so the card shows tidy times.
    private static func round(_ date: Date, down: Bool) -> Date {
        let value = date.timeIntervalSince1970 / 300
        return Date(timeIntervalSince1970: (down ? value.rounded(.down) : value.rounded(.up)) * 300)
    }
}
