//
//  LightPollutionService.swift
//  Asterra
//
//  Created by Ahmad Zaki on 15/11/26.
//

import Foundation

struct LightPollutionEstimate: Codable {
    let sqm: Double
    let bortleClass: Int
    let datasetID: String
}

enum LightPollutionService {
    static func lookup(latitude: Double, longitude: Double) async -> LightPollutionEstimate? {
        guard let endpoint = Bundle.main.object(
            forInfoDictionaryKey: "LightPollutionAPIURL"
        ) as? String,
              var components = URLComponents(string: endpoint),
              components.scheme == "https",
              components.host != nil else { return nil }

        components.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lng", value: String(longitude))
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

            let estimate = try JSONDecoder().decode(LightPollutionEstimate.self, from: data)
            guard estimate.sqm.isFinite,
                  (1...9).contains(estimate.bortleClass),
                  !estimate.datasetID.isEmpty else { return nil }
            return estimate
        } catch {
            return nil
        }
    }
}
