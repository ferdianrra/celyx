import Foundation

// Connects the bundled HYG-derived catalog to StarKit. `stars.json` keeps only `bv`,
// magnitude and distance, so spectral type and variability are unavailable: StarKit
// then falls back to its defaults (dwarf luminosity class, no pulse boost).
extension CatalogStar: StarRenderable {
    /// HYG `ci` (B−V).
    var colorIndex: Double? { bv }

    /// Not stored in `stars.json`.
    var spectralType: String? { isSun ? "G2V" : nil }

    /// Solar luminosities from apparent magnitude and distance, the same way HYG derives
    /// `lum` from `absmag`. Nil when the distance is missing, so StarKit uses 1.
    var luminosity: Double? {
        if isSun { return 1 }
        guard let distance_ly, distance_ly > 0 else { return nil }
        let parsecs = distance_ly / 3.261_563_777
        let absoluteMagnitude = mag - 5 * (log10(parsecs) - 1)
        return pow(10, 0.4 * (4.83 - absoluteMagnitude))
    }
}

extension StarTuning {
    /// Asterra's look: brighter, wider corona with visible breathing and a soft sparkle,
    /// on a slightly smaller disk so the light has room inside small portrait frames.
    /// Low granulation and turbulence give a smooth, mottled photosphere instead of
    /// sharp glass-like cells at portrait sizes.
    static let asterra = StarTuning(turbulence: 0.38, corona: 1.35, speed: 2.27, pulse: 2.2,
                                    sparkle: 0.35, diskScale: 0.86, granulation: 0.3)
}
