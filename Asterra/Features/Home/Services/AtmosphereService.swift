//
//  AtmosphereService.swift
//  celyx
//
//  Created by Ferdiansyah Annora on 02/11/26.
//
import Foundation

// Public Open-Meteo/CAMS model data. Coordinates are sent only when the user enables online conditions.
// Missing/null/stale data remains unknown; it is never presented as a clear-sky measurement.
enum AtmosphereService {
    private struct Reply: Decodable {
        struct Current: Decodable {
            let time: Double
            let cloud_cover: Double?
            let aerosol_optical_depth: Double?
            let pm2_5: Double?
        }
        let current: Current
    }
    private static func fetch(host: String, path: String, variables: String, location: ObserverLocation) async throws -> Reply.Current {
        var parts = URLComponents()
        parts.scheme = "https"; parts.host = host; parts.path = path
        parts.queryItems = [URLQueryItem(name:"latitude",value:String(location.latitude)),
            URLQueryItem(name:"longitude",value:String(location.longitude)),
            URLQueryItem(name:"current",value:variables),URLQueryItem(name:"timeformat",value:"unixtime")]
        var request = URLRequest(url: parts.url!); request.timeoutInterval = 15
        let (data,response) = try await URLSession.shared.data(for:request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        let value = try JSONDecoder().decode(Reply.self,from:data).current
        guard abs(Date(timeIntervalSince1970:value.time).timeIntervalSinceNow) < 10800 else { throw URLError(.resourceUnavailable) }
        return value
    }
    static func load(location: ObserverLocation) async -> Atmosphere {
        async let weather: Result<Reply.Current,Error> = result { try await fetch(host:"api.open-meteo.com",path:"/v1/forecast",variables:"cloud_cover",location:location) }
        async let air: Result<Reply.Current,Error> = result { try await fetch(host:"air-quality-api.open-meteo.com",path:"/v1/air-quality",variables:"aerosol_optical_depth,pm2_5",location:location) }
        let (w,a) = await (weather,air)
        var value = Atmosphere(); value.fetchedAt = Date()
        switch w { case .success(let x): value.cloudCover = x.cloud_cover; value.weatherDate = Date(timeIntervalSince1970:x.time)
        case .failure: value.weatherError = "Cloud forecasts aren’t available right now" }
        switch a { case .success(let x): value.aerosolOpticalDepth = x.aerosol_optical_depth; value.pm25 = x.pm2_5; value.airDate = Date(timeIntervalSince1970:x.time)
        case .failure: value.airError = "Air-quality forecasts aren’t available right now" }
        return value
    }
    private static func result<T>(_ operation: () async throws -> T) async -> Result<T,Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }
}
