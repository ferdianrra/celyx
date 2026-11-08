//  SkyStyle.swift
//  TEMPORARY sky test: which Milky Way map the Night Sea draws. A DEBUG chip on Home cycles them live.
//  NASA maps: NASA/Goddard Space Flight Center Scientific Visualization Studio, "Deep Star Maps 2020"
//  (svs.gsfc.nasa.gov/4851), graded by scripts/make_nasa_milky_way.swift.

import Foundation

enum SkyStyle: Int, CaseIterable {
    /// The Night Sea kit's Milky Way map.
    case kit = 0
    /// NASA's Milky Way, graded toward the user's reference (lavender band, wide glow, soft dust lanes).
    case nasaLavender = 1
    /// NASA's Milky Way as photographed (levels only).
    case nasaNatural = 2

    static let storageKey = "skyStyle"
    static let defaultStyle: SkyStyle = .kit

    static var current: SkyStyle {
        guard UserDefaults.standard.object(forKey:storageKey) != nil else { return defaultStyle }
        return SkyStyle(rawValue:UserDefaults.standard.integer(forKey:storageKey)) ?? defaultStyle
    }

    /// Milky Way map for this style (all 4096x2048, RA/Dec).
    var textureName: String {
        switch self {
        case .kit: "garden-milky-way-radec"
        case .nasaLavender: "garden-milky-way-radec-nasa-lavender"
        case .nasaNatural: "garden-milky-way-radec-nasa-natural"
        }
    }

    var title: String {
        switch self {
        case .kit: "0 · Kit"
        case .nasaLavender: "1 · NASA lavender"
        case .nasaNatural: "2 · NASA natural"
        }
    }
    var next: SkyStyle { SkyStyle(rawValue:(rawValue+1) % SkyStyle.allCases.count) ?? .kit }
}
