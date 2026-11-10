// DEBUG-only collection override for the Libra, Aries and Capricornus pattern stars.
// Uses real observing coordinates and time; only optical verification is bypassed.
#if DEBUG
import SwiftUI
import simd

enum DemoSky {
    struct Entry: Identifiable {
        let star: CatalogStar
        let direction: SIMD3<Double>
        var id: Int { star.id }
    }
    struct Projection: Identifiable {
        let star: CatalogStar
        let point: CGPoint?
        let arrow: CGVector?
        var id: Int { star.id }
    }
    static let constellationCodes = ["Lib", "Ari", "Cap"]
    /// Existing catalog IDs around Capricornus: Sadalsuud, 62 Sagittarii, Albali,
    /// Bunda, Terebellum, Ancha and Aldhanab. Coordinates always come from the catalog.
    static let nearbyStarIDs: Set<Int> = [160, 843, 404, 1115, 1134, 619, 174]

    /// Use the catalog's figure endpoints, including unnamed members needed to complete each pattern.
    static func stars(in catalogue: [CatalogStar]) -> [CatalogStar] {
        guard let url = try? SkyAssets.url("constellations", extension: "json"),
            let data = try? Data(contentsOf: url),
            let figures = try? JSONDecoder().decode([String: Constellation].self, from: data)
        else { return [] }
        let ids = Set(constellationCodes.flatMap { figures[$0]?.segments.flatMap { $0 } ?? [] }).union(nearbyStarIDs)
        return catalogue.filter { ids.contains($0.id) }.sorted { $0.id < $1.id }
    }

    /// Keep one uncollected Capricornus member for the final capture; never erase real observations.
    /// A fresh collection leaves Deneb Algedi (the brightest pattern member) uncollected.
    @discardableResult
    static func prepareCapricornus(model: HomeViewModel, date: Date, location: ObserverLocation) throws -> CatalogStar? {
        guard let figure = GardenZodiacFigure.load().first(where: { $0.id == "Cap" }) else { return nil }
        let stars = model.stars.filter { figure.requiredStarIDs.contains($0.id) }.sorted {
            $0.mag == $1.mag ? $0.id < $1.id : $0.mag < $1.mag
        }
        guard let last = stars.first(where: { model.collected[$0.id] == nil }) else { return nil }
        let records = stars.filter { $0.id != last.id && model.collected[$0.id] == nil }.map {
            CollectedStar(id: $0.id, date: date, latitude: location.latitude, longitude: location.longitude,
                identificationNote: "Pre-collected Capricornus demo star (debug build). Added for testing constellation completion; no camera capture was performed.")
        }
        try model.seedDemoObservations(records)
        return last
    }

    /// Adds the surrounding demo sky without replacing any saved observations.
    @discardableResult
    static func prepareCollection(model: HomeViewModel, date: Date, location: ObserverLocation) throws -> CatalogStar? {
        let finalStar = try prepareCapricornus(model: model, date: date, location: location)
        let records = model.stars.filter { nearbyStarIDs.contains($0.id) && model.collected[$0.id] == nil }.map {
            CollectedStar(id: $0.id, date: date, latitude: location.latitude, longitude: location.longitude,
                identificationNote: "Pre-collected nearby demo star (debug build). Added around Capricornus; no camera capture was performed.")
        }
        try model.seedDemoObservations(records)
        return finalStar
    }

    /// The same apparent horizon coordinates used by the live sky and garden, never recentered on the phone.
    static func entries(in catalogue: [CatalogStar], date: Date, location: ObserverLocation?) -> [Entry] {
        guard let location else { return [] }
        let sky = AstronomyService.snapshot(date: date, location: location)
        return stars(in: catalogue).map { star in
            Entry(star: star, direction: Refraction.apparent(sky.direction(ra: star.ra_deg, dec: star.dec_deg)))
        }
    }

    static func target(in projections: [Projection], collected: Set<Int>, excludedID: Int?,
                       lockedID: Int?, center: CGPoint, radius: CGFloat, lockRadius: CGFloat) -> Projection? {
        let candidates = projections.filter { !collected.contains($0.id) && $0.id != excludedID && $0.point != nil }
        func distance(_ entry: Projection) -> CGFloat {
            guard let point = entry.point else { return .infinity }
            return hypot(point.x - center.x, point.y - center.y)
        }
        if let held = candidates.first(where: { $0.id == lockedID && distance($0) <= lockRadius }) { return held }
        return candidates.filter { distance($0) <= radius }.min { distance($0) < distance($1) }
    }

    /// Visible virtual stars can be tapped directly; they do not need optical
    /// detection or to be inside the aim reticle. Collected sources stay excluded.
    static func tappedTarget(in projections: [Projection], at point: CGPoint,
                             collected: Set<Int>, excludedID: Int?, radius: CGFloat = 44) -> Projection? {
        target(in: projections, collected: collected, excludedID: excludedID,
               lockedID: nil, center: point, radius: radius, lockRadius: radius)
    }

    /// Paint the simulated sky into the saved frame, including when no camera is available.
    static func composite(_ image: CGImage?, stars: [(point: CGPoint, color: SIMD3<Double>)], viewSize: CGSize) -> CGImage? {
        guard viewSize.width > 0, viewSize.height > 0 else { return nil }
        let size = image.map { CGSize(width: $0.width, height: $0.height) } ?? viewSize
        let scale = size.width / viewSize.width
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(red: 0.02, green: 0.03, blue: 0.08, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            if let image { UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size)) }
            for star in stars {
                let point = CGPoint(x: star.point.x * scale, y: star.point.y * size.height / viewSize.height)
                let tint = UIColor(red: star.color.x, green: star.color.y, blue: star.color.z, alpha: 1)
                let colors = [UIColor.white.cgColor, tint.withAlphaComponent(0.55).cgColor, tint.withAlphaComponent(0).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.18, 1]) {
                    context.cgContext.drawRadialGradient(gradient, startCenter: point, startRadius: 0,
                        endCenter: point, endRadius: 16 * scale, options: [])
                }
            }
        }.cgImage
    }

    static func save(star: CatalogStar, image: CGImage, date: Date, location: ObserverLocation, model: HomeViewModel) throws {
        let draft = CameraObservationDraft(star: star, image: UIImage(cgImage: image), date: date,
            location: location,
            identificationNote: "Demo constellation capture (debug build). Position calculated from the catalog, observation location and time. Star overlay generated; optical verification bypassed.")
        try model.saveCameraObservation(draft, note: "")
    }
}

/// A believable bright star over the live camera: soft core, glow, slight twinkle.
struct DemoStarView: View {
    let color: SIMD3<Double>
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let twinkle = 0.88+0.12*sin(t*7.3)*sin(t*3.1+1.2)
            let tint = Color(red:color.x,green:color.y,blue:color.z)
            ZStack {
                Circle().fill(RadialGradient(colors:[tint.opacity(0.55),tint.opacity(0)],center:.center,startRadius:0,endRadius:18))
                    .frame(width:36,height:36)
                Circle().fill(RadialGradient(colors:[.white,.white.opacity(0.6),.white.opacity(0)],center:.center,startRadius:0,endRadius:5))
                    .frame(width:10,height:10)
                Rectangle().fill(LinearGradient(colors:[.clear,.white.opacity(0.5),.clear],startPoint:.leading,endPoint:.trailing))
                    .frame(width:30,height:0.8)
                Rectangle().fill(LinearGradient(colors:[.clear,.white.opacity(0.5),.clear],startPoint:.top,endPoint:.bottom))
                    .frame(width:0.8,height:30)
            }
            .opacity(twinkle)
            .blendMode(.screen)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Brief neutral-glass confirmation when entering demo mode.
struct DemoModeNotice: View {
    var body: some View {
        Text("Demo mode")
            .font(.body.weight(.medium))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 0.5)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .glassEffect(.regular, in: Capsule())
            .environment(\.colorScheme, .dark)
            .allowsHitTesting(false)
    }
}
#endif
