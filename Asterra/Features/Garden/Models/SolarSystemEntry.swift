//
//  SolarSystemEntry.swift
//  Asterra
//
//  Created by Ahmad Zaki on 19/11/26.
//

import Foundation

enum SolarSystemEntry: String, CaseIterable, Identifiable {
    case sun = "Sun"
    case moon = "Moon"
    case mercury = "Mercury"
    case venus = "Venus"
    case mars = "Mars"
    case jupiter = "Jupiter"
    case saturn = "Saturn"
    case uranus = "Uranus"
    case neptune = "Neptune"

    var id: String { rawValue }

    var category: String {
        switch self {
        case .sun: "Star"
        case .moon: "Natural satellite"
        default: "Planet"
        }
    }

    var catalogBody: CatalogStar? {
        switch self {
        case .sun: .sun
        case .moon: .moon
        default: CatalogStar.planets.first { $0.title == rawValue }
        }
    }

    func item(in model: HomeViewModel) -> GardenCollectionItem? {
        guard let body = catalogBody else { return nil }
        return model.collectionItems.first { $0.id == body.id }
    }

    var about: String {
        switch self {
        case .sun:
            "The Sun is the star at the centre of our solar system."
        case .moon:
            "The Moon is Earth’s natural satellite."
        case .mercury:
            "Mercury is the closest planet to the Sun."
        case .venus:
            "Venus is the second planet from the Sun."
        case .mars:
            "Mars is the fourth planet from the Sun."
        case .jupiter:
            "Jupiter is a gas giant in the outer solar system."
        case .saturn:
            "Saturn is a gas giant surrounded by rings."
        case .uranus:
            "Uranus is an ice giant and the seventh planet from the Sun."
        case .neptune:
            "Neptune is an ice giant and the eighth planet from the Sun."
        }
    }

    var funFact: String {
        switch self {
        case .sun:
            "The Moon and planets shine by reflecting sunlight."
        case .moon:
            "Earth’s Moon is one of hundreds of moons in our solar system."
        case .mercury:
            "Mercury was one of the five planets known to ancient skywatchers."
        case .venus:
            "Venus was one of the five planets known to ancient skywatchers."
        case .mars:
            "Mars was one of the five planets known to ancient skywatchers."
        case .jupiter:
            "Jupiter also has a ring system."
        case .saturn:
            "Jupiter, Uranus and Neptune have rings too."
        case .uranus:
            "Uranus has the third-largest diameter among the planets."
        case .neptune:
            "Voyager 2 flew past Neptune in 1989."
        }
    }
}
