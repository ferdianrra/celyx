//
//  StarStyle.swift
//  StarKit
//
//  Turns catalog data (HYG columns: ci, spect, lum, var, var_min, var_max) into
//  shader parameters. One rule for every star: no per-star hand tuning.
//

import Foundation

// MARK: - Your data → StarKit

/// Anything that can be drawn as a star. Conform your own model (struct, SwiftData,
/// Core Data) by exposing the HYG fields you already store. Only `colorIndex` and
/// `spectralType` matter much; the rest are optional.
public protocol StarRenderable {
    /// HYG `ci` — B−V color index.
    var colorIndex: Double? { get }
    /// HYG `spect` — spectral type, e.g. "B8Ia", "M2Ib", "G2V".
    var spectralType: String? { get }
    /// HYG `lum` — luminosity in solar units.
    var luminosity: Double? { get }
    /// HYG `var` — variable-star designation, nil/empty if not variable.
    var variableDesignation: String? { get }
    /// HYG `var_min` — faintest magnitude of a variable.
    var variableMinMagnitude: Double? { get }
    /// HYG `var_max` — brightest magnitude of a variable.
    var variableMaxMagnitude: Double? { get }
}

public extension StarRenderable {
    var luminosity: Double? { nil }
    var variableDesignation: String? { nil }
    var variableMinMagnitude: Double? { nil }
    var variableMaxMagnitude: Double? { nil }

    /// Shader parameters derived from this star's data.
    var starStyle: StarStyle { StarStyle(self) }
}

// MARK: - Global tuning

/// Multipliers applied to every star. Defaults are the settings chosen for Rigel
/// in the web preview (Turbulence 0.50, Corona glow 0.89, Speed 2.27).
public struct StarTuning: Sendable, Equatable {
    public var turbulence: Float
    public var corona: Float
    public var speed: Float
    /// Multiplies the breathing of corona, bloom and disk brightness (1 = StarKit default).
    public var pulse: Float
    /// Diffraction-spike strength in `.header` mode (0 = none; `.hero` always shows them).
    public var sparkle: Float
    /// Disk size in `.header` mode relative to the default; < 1 leaves more room for the corona.
    public var diskScale: Float
    /// Contrast of the convection cells and surface highlights (1 = StarKit default,
    /// lower = smoother, less glassy surface).
    public var granulation: Float

    public init(turbulence: Float = 0.50, corona: Float = 0.89, speed: Float = 2.27,
                pulse: Float = 1, sparkle: Float = 0, diskScale: Float = 1, granulation: Float = 1) {
        self.turbulence = turbulence
        self.corona = corona
        self.speed = speed
        self.pulse = pulse
        self.sparkle = sparkle
        self.diskScale = diskScale
        self.granulation = granulation
    }

    public static let `default` = StarTuning()
}

// MARK: - Style

public enum LuminosityClass: String, Sendable {
    case supergiant = "I", brightGiant = "II", giant = "III", subgiant = "IV", dwarf = "V", subdwarf = "VI"

    /// < 1 = few huge convection cells (supergiants), > 1 = fine granulation (dwarfs).
    var turbulence: Float {
        switch self {
        case .supergiant: 0.55
        case .brightGiant: 0.70
        case .giant: 0.85
        case .subgiant: 1.00
        case .dwarf: 1.20
        case .subdwarf: 1.30
        }
    }

    /// Big stars churn more slowly.
    var speed: Float {
        switch self {
        case .supergiant: 0.7
        case .brightGiant: 0.8
        case .giant: 0.9
        case .subgiant, .dwarf, .subdwarf: 1.0
        }
    }
}

public struct StarStyle: Sendable, Equatable {
    public var deep: SIMD3<Float>          // limb and dark-lane color
    public var core: SIMD3<Float>          // bright surface color
    public var glow: SIMD3<Float>          // corona color
    public var turbulence: Float           // from luminosity class
    public var corona: Float               // from luminosity
    public var pulse: Float                // from variability
    public var speed: Float                // from luminosity class
    public var hot: Float                  // 0 = cool (strong granulation) … 1 = hot (smooth)
    public var spotAmount: Float           // starspots: cool dwarfs only
    public var temperature: Double         // kelvin
    public var luminosityClass: LuminosityClass

    public init(_ star: some StarRenderable) {
        self.init(colorIndex: star.colorIndex,
                  spectralType: star.spectralType,
                  luminosity: star.luminosity,
                  variableDesignation: star.variableDesignation,
                  variableMinMagnitude: star.variableMinMagnitude,
                  variableMaxMagnitude: star.variableMaxMagnitude)
    }

    public init(colorIndex: Double?,
                spectralType: String?,
                luminosity: Double? = nil,
                variableDesignation: String? = nil,
                variableMinMagnitude: Double? = nil,
                variableMaxMagnitude: Double? = nil) {
        let spect = spectralType ?? ""
        let t = StarStyle.temperature(colorIndex: colorIndex, spectralType: spect)
        let cls = StarStyle.luminosityClass(spect)
        let bb = StarStyle.blackbody(t)

        temperature = t
        luminosityClass = cls
        core = bb + (SIMD3<Float>(repeating: 1) - bb) * 0.35
        deep = SIMD3(powf(bb.x, 2.5), powf(bb.y, 2.5), powf(bb.z, 2.5)) * 0.75
        glow = SIMD3(powf(bb.x, 1.6), powf(bb.y, 1.6), powf(bb.z, 1.6))
        turbulence = cls.turbulence
        speed = cls.speed
        hot = Float(min(max((t - 3500) / 8000, 0), 1))
        spotAmount = 0.45 * (1 - hot) * StarStyle.smoothstep(0.9, 1.2, cls.turbulence)

        let lum = max(luminosity ?? 1, 1e-4)
        corona = Float(min(max(0.55 + 0.14 * log10(lum), 0.35), 1.6))

        if let v = variableDesignation, !v.trimmingCharacters(in: .whitespaces).isEmpty {
            if let lo = variableMinMagnitude, let hi = variableMaxMagnitude {
                pulse = Float(min(max(1 + abs(lo - hi) * 0.8, 1), 2.5))
            } else {
                pulse = 1.0
            }
        } else {
            pulse = 0.6
        }
    }

    // MARK: Rules

    /// B−V → effective temperature (Ballesteros 2012). Falls back to the spectral type.
    public static func temperature(colorIndex: Double?, spectralType: String) -> Double {
        if let bv = colorIndex, bv.isFinite {
            let c = min(max(bv, -0.4), 2.0)
            return 4600 * (1 / (0.92 * c + 1.7) + 1 / (0.92 * c + 0.62))
        }
        let order: [Character] = ["O", "B", "A", "F", "G", "K", "M"]
        let base: [Double] = [40000, 20000, 9000, 7000, 5600, 4500, 3400]
        guard let letter = spectralType.first(where: { order.contains($0) }),
              let i = order.firstIndex(of: letter) else { return 5800 }
        let next = i + 1 < base.count ? base[i + 1] : 2800
        let afterLetter = spectralType.drop(while: { $0 != letter }).dropFirst()
        let digit = afterLetter.first?.wholeNumberValue ?? 5
        return base[i] + (next - base[i]) * Double(digit) / 10
    }

    /// First Roman-numeral luminosity class in the spectral type ("B8Ia" → I, "K5III" → III).
    public static func luminosityClass(_ spectralType: String) -> LuminosityClass {
        let tokens: [(String, LuminosityClass)] = [
            ("Iab", .supergiant), ("Ia", .supergiant), ("Ib", .supergiant),
            ("III", .giant), ("II", .brightGiant), ("IV", .subgiant),
            ("VI", .subdwarf), ("V", .dwarf), ("I", .supergiant)
        ]
        // skip the temperature class ("B8", "M1.5") before looking for the numeral
        let rest = Substring(spectralType)
            .drop(while: { "OBAFGKM".contains($0) })
            .drop(while: { $0.isNumber || $0 == "." })
        var index = rest.startIndex
        while index < rest.endIndex {
            let tail = rest[index...]
            for (token, cls) in tokens where tail.hasPrefix(token) { return cls }
            index = rest.index(after: index)
        }
        return .dwarf
    }

    /// Blackbody color (Tanner Helland approximation), kelvin → 0…1 RGB.
    public static func blackbody(_ kelvin: Double) -> SIMD3<Float> {
        let t = kelvin / 100
        let r: Double = t <= 66 ? 255 : 329.698727446 * pow(t - 60, -0.1332047592)
        let g: Double = t <= 66 ? 99.4708025861 * log(t) - 161.1195681661
                                : 288.1221695283 * pow(t - 60, -0.0755148492)
        let b: Double = t >= 66 ? 255 : (t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307)
        func c(_ v: Double) -> Float { Float(min(max(v, 0), 255) / 255) }
        return SIMD3(c(r), c(g), c(b))
    }

    static func smoothstep(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
