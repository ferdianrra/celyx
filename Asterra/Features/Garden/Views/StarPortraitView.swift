import SwiftUI

struct StarPortraitView: View {
    let star: CatalogStar
    var solarAltitude: Double = 60
    var body: some View {
        ZStack {
            if star.isSun {
                SunPortraitView(altitude: solarAltitude)
            } else if let look = PlanetLook.look(for: star) {
                // Moon and planets: their garden textures on a lit, slowly rotating sphere.
                PlanetView(look: look)
            } else {
                // Live StarKit star from the catalog's B−V and luminosity (header mode:
                // transparent, so it blends with each sheet's or card's background).
                StarView(star: star, tuning: .asterra)
            }
        }
        // StarView and PlanetView hide themselves from VoiceOver; keep one labelled element.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            star.isSun
                ? "Illustration of the Sun"
                : star.isMoon
                    ? "Illustration of the Moon"
                    : star.isPlanet
                        ? "Illustration of \(star.title)"
                        : "Animated illustration of \(star.title), color based on the star catalog")
    }
}

// The Sun drawn by StarKit as the G2V star it is, reddened like a low sun near the horizon.
private struct SunPortraitView: View {
    let altitude: Double

    private var style: StarStyle {
        let low = altitude < 10
        var style = StarStyle(colorIndex: low ? 1.35 : CatalogStar.sun.bv, spectralType: "G2V", luminosity: 1)
        // As seen from Earth the Sun is a dazzling yellow-white disk: few spots, a warm
        // bright surface and a generous glow (a 1 L☉ dwarf would otherwise look dim).
        let sunlight: SIMD3<Float> = low ? SIMD3(1.0, 0.62, 0.30) : SIMD3(1.0, 0.93, 0.70)
        style.core = style.core + (sunlight - style.core) * 0.7
        style.glow = style.glow + (sunlight - style.glow) * 0.5
        style.deep = style.deep + (sunlight * SIMD3(0.95, 0.72, 0.42) - style.deep) * 0.85
        style.spotAmount *= 0.25
        style.corona = 1.05
        return style
    }

    var body: some View {
        StarView(style: style, tuning: .asterra)
    }
}

#Preview("Star portrait") {
    StarPortraitView(star: AppPreviewData.star).frame(width: 160, height: 160).padding().background(
        CelyxColor.night)
}

#Preview("Solar system portraits") {
    HStack {
        ForEach([CatalogStar.sun, .moon] + CatalogStar.planets) { body in
            StarPortraitView(star: body).frame(width: 64, height: 64)
        }
    }.padding().background(CelyxColor.night)
}

#Preview("Low Sun portrait") {
    SunPortraitView(altitude: 5).frame(width: 160, height: 160).padding().background(CelyxColor.night)
}
