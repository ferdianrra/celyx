import Foundation

/// Latin constellation names from the bundled Stellarium metadata (e.g. "Ori" → "Orion").
enum ConstellationNames {
    private static let names: [String: String] = {
        guard let url = try? SkyAssets.url("constellations", extension: "json"),
            let data = try? Data(contentsOf: url),
            let entries = try? JSONDecoder().decode([String: Constellation].self, from: data)
        else { return [:] }
        return entries.compactMapValues { $0.name ?? $0.english }
    }()
    static func name(for code: String) -> String? { names[code] }
}
