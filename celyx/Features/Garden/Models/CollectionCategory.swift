import Foundation

enum CollectionCategory: String, CaseIterable, Hashable, Identifiable {
    case stars = "Stars"
    case planets = "Planet"
    case skyEvents = "Sky event"
    case constellations = "Constellation"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .stars: "Stars"
        case .planets: "Planets & Moon"
        case .skyEvents: "Sky events"
        case .constellations: "Constellations"
        }
    }

    /// The Sun is a star; the Moon sits with the planets (the solar-system bodies).
    static func stars(_ items: [GardenCollectionItem]) -> [GardenCollectionItem] {
        items.filter { !$0.star.isSolarSystemBody || $0.star.isSun }
    }
    static func planets(_ items: [GardenCollectionItem]) -> [GardenCollectionItem] {
        items.filter { $0.star.isPlanet || $0.star.isMoon }
    }
    /// Constellations with at least one collected star, most collected first.
    static func constellations(_ items: [GardenCollectionItem]) -> [(
        code: String, name: String, items: [GardenCollectionItem]
    )] {
        Dictionary(grouping: items.filter { $0.star.con != nil }) { $0.star.con! }
            .map { code, members in (code, ConstellationNames.name(for: code) ?? code, members) }
            .sorted {
                $0.items.count == $1.items.count ? $0.name < $1.name : $0.items.count > $1.items.count
            }
    }
}

/// List of what you've collected in one category (opened from a tile on "Your Collection").
