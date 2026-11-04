import Foundation
import Observation

@MainActor @Observable
final class AstronomyEventsService {
    private(set) var events: [AstronomyEvent] = []
    private(set) var isLoading = false
    private(set) var message: String?
    private(set) var updatedAt: Date?
    private(set) var isUsingSavedEvents = false
    private var range: String?
    private struct SavedResponse: Codable {
        let from: String
        let to: String
        let fetched: Date
        let data: Data
    }
    private var cacheURL: URL? {
        guard let root = FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask).first else { return nil }
        return root.appendingPathComponent("upcoming-astronomy-events.json")
    }
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
            if let date = iso.date(from:string) { return date }
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from:string) { return date }
            throw DecodingError.dataCorruptedError(in:container,debugDescription:"Invalid event time")
        }
        return decoder
    }
    func load(force: Bool = false) async {
        guard !isLoading else { return }
        let now = Date()
        var calendar = Calendar(identifier:.gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT:0)!
        let formatter = DateFormatter(); formatter.locale = Locale(identifier:"en_US_POSIX")
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd"
        let from = formatter.string(from:now)
        let to = formatter.string(from:calendar.date(byAdding:.month,value:6,to:now) ?? now.addingTimeInterval(180*86400))
        let key = from+"/"+to
        if !force, range == key, let updatedAt, now.timeIntervalSince(updatedAt) < 21600 { return }
        var saved: SavedResponse?
        if let cacheURL, let data = try? Data(contentsOf:cacheURL), let record = try? JSONDecoder().decode(SavedResponse.self,from:data),
           record.to >= from, let decoded = try? Self.decoder().decode(AstronomyEventsResponse.self,from:record.data) {
            saved = record
            events = deduplicated(decoded.events)
            updatedAt = record.fetched
            isUsingSavedEvents = true
            if !force, record.from == from, record.to == to, now.timeIntervalSince(record.fetched) < 21600 {
                range = key; isUsingSavedEvents = false; return
            }
        }
        isLoading = true; message = nil
        defer { isLoading = false }
        do {
            var components = URLComponents(string:"https://spacecatalog.org/api/v1/events")!
            components.queryItems = [URLQueryItem(name:"from",value:from),URLQueryItem(name:"to",value:to),URLQueryItem(name:"limit",value:"500")]
            var request = URLRequest(url:components.url!,cachePolicy:force ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy,timeoutInterval:20)
            request.setValue("application/json",forHTTPHeaderField:"Accept")
            let (data,response) = try await URLSession.shared.data(for:request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
            let decoded = try Self.decoder().decode(AstronomyEventsResponse.self,from:data)
            events = deduplicated(decoded.events); updatedAt = Date(); range = key; isUsingSavedEvents = false
            if let cacheURL, let encoded = try? JSONEncoder().encode(SavedResponse(from:from,to:to,fetched:updatedAt!,data:data)) {
                try? encoded.write(to:cacheURL,options:.atomic)
            }
        } catch {
            guard !Task.isCancelled else { return }
            if saved != nil {
                message = "You’re seeing saved events. Pull down to check for updates."
            } else {
                message = "We couldn’t load the events. Check your connection and try again."
            }
        }
    }
    private func deduplicated(_ input: [AstronomyEvent]) -> [AstronomyEvent] {
        Dictionary(input.map { ($0.id,$0) },uniquingKeysWith:{ first,_ in first }).values.sorted { $0.time == $1.time ? $0.id < $1.id : $0.time < $1.time }
    }
}
