import Foundation

struct AstronomyEvent: Codable, Identifiable, Sendable {
    let id: String
    let kind: String
    let time: Date
    let title: String
    let description: String?
    let summary: String?
    let objects: [String]?
    let url: String?
    let source: EventSource?
    var position: Position? = nil
    var circumstances: Circumstances? = nil

    struct Position: Codable, Sendable {
        let ra_deg: Double
        let dec_deg: Double
    }
    struct Circumstances: Codable, Sendable {
        var magnitude: Double? = nil
        var distance_ld: Double? = nil
        var greatest_at: GeographicPoint? = nil
        struct GeographicPoint: Codable, Sendable {
            let lat_deg: Double
            let lon_deg: Double
        }
    }

    struct EventSource: Codable, Sendable {
        let name: String?
        let url: String?
        let license: String?
        let attribution: String?
    }
    enum Category: String, CaseIterable, Identifiable {
        case all = "All", eclipse = "Eclipses", planets = "Planets", meteors = "Meteors", moon = "Moon", other = "More"
        var id: String { rawValue }
    }
    var category: Category {
        switch kind {
        case "eclipse": .eclipse
        case "conjunction", "elongation", "opposition": .planets
        case "shower": .meteors
        case "moon": .moon
        default: .other
        }
    }
    var cardTitle: String {
        if kind == "conjunction", let objects, objects.count == 2 {
            return objects.map { $0.capitalized }.joined(separator:" & ")
        }
        if kind == "shower" { return title.replacingOccurrences(of:" at maximum",with:"")+" Meteor Shower" }
        if kind == "flyby" { return title.components(separatedBy:" passes").first.map { $0+" Flyby" } ?? title }
        return title.prefix(1).uppercased()+title.dropFirst()
    }
    var artwork: String? {
        switch category {
        case .eclipse: return "event-eclipse"
        case .planets: return "event-planets"
        case .meteors: return "event-meteor"
        case .moon: return "event-moon"
        default: return nil
        }
    }
    var symbol: String {
        switch category {
        case .eclipse: "moonphase.new.moon"
        case .planets: "sparkles"
        case .meteors: "sparkles"
        case .moon: "moon.fill"
        default: kind == "flyby" ? "circle.dotted" : "sun.max"
        }
    }
    var sourceURL: URL? {
        guard let url, let target = URL(string:url), target.scheme == "https" else { return nil }
        return target
    }
    var producerURL: URL? {
        guard let url = source?.url, let target = URL(string:url), target.scheme == "https" else { return nil }
        return target
    }
}

struct AstronomyEventsResponse: Codable {
    let events: [AstronomyEvent]
}
