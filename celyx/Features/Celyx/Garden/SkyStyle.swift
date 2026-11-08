//  SkyStyle.swift
//  Which galaxy layer the Night Sea draws. Being explored with the user: a DEBUG chip on Home cycles them
//  live; the chosen one becomes the default.

import Foundation

enum SkyStyle: Int, CaseIterable {
    /// The Night Sea kit's real Milky Way map (detailed: dust lanes, nebulae).
    case kit = 0
    /// The real Milky Way, heavily blurred into a soft lilac-indigo band.
    case softVeil = 1
    /// Only the band's shape, painted with a smooth indigo -> rose -> teal gradient.
    case dreamy = 2
    /// No band: very faint soft violet/teal clouds across the sky.
    case nebulaWash = 3
    /// No galaxy at all.
    case clean = 4

    static let storageKey = "skyStyle"
    static let defaultStyle: SkyStyle = .kit

    static var current: SkyStyle {
        guard UserDefaults.standard.object(forKey:storageKey) != nil else { return defaultStyle }
        return SkyStyle(rawValue:UserDefaults.standard.integer(forKey:storageKey)) ?? defaultStyle
    }

    var title: String {
        switch self {
        case .kit: "0 · Kit"
        case .softVeil: "1 · Soft Veil"
        case .dreamy: "2 · Dreamy"
        case .nebulaWash: "3 · Nebula Wash"
        case .clean: "4 · Clean"
        }
    }
    var next: SkyStyle { SkyStyle(rawValue:(rawValue+1) % SkyStyle.allCases.count) ?? .kit }
}
