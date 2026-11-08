//  SkyStyle.swift
//  Which Milky Way look the Night Sea draws. Being chosen with the user: a DEBUG chip on Home cycles them
//  live; the chosen one becomes the default. The softened maps are made offline by scripts/make_soft_milky_way.swift.

import Foundation

enum SkyStyle: Int, CaseIterable {
    /// The Night Sea kit's real Milky Way map (detailed: dust lanes, nebulae).
    case kit = 0
    /// The same map, lightly softened.
    case softLight = 1
    /// Softened toward the user's reference: soft lavender band, pink-beige core, gentle dust lanes.
    case softLavender = 2
    /// The softest, dreamiest version.
    case softDreamy = 3

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
        case .softLight: "garden-milky-way-radec-soft1"
        case .softLavender: "garden-milky-way-radec-soft2"
        case .softDreamy: "garden-milky-way-radec-soft3"
        }
    }

    var title: String {
        switch self {
        case .kit: "0 · Kit"
        case .softLight: "1 · Kit Soft (light)"
        case .softLavender: "2 · Kit Soft (lavender)"
        case .softDreamy: "3 · Kit Soft (dreamy)"
        }
    }
    var next: SkyStyle { SkyStyle(rawValue:(rawValue+1) % SkyStyle.allCases.count) ?? .kit }
}
