#if DEBUG
import Foundation

@MainActor enum StarSharePreviewData {
    static let observationLogModel = model(withObservationLog: true)
    static var item: GardenCollectionItem {
        let star = ((try? SkyAssets.stars()) ?? []).first { $0.title == "Rigel" } ?? AppPreviewData.star
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 21))!
        return GardenCollectionItem(star: star,
            record: CollectedStar(id: star.id, date: date, latitude: -6.23, longitude: 106.85,
                note: "Last night, I captured a breathtaking moment while photographing the stars. Mars and Jupiter danced closely in the night sky, resembling two lovers meeting under the vast cosmos.",
                placeName: "Tebet, South Jakarta"))
    }

    static func model(withObservationLog: Bool = false) -> HomeViewModel {
        let fixture = item
        let earlier = ((try? SkyAssets.stars()) ?? []).filter { $0.id != fixture.id }.prefix(2)
        var records = earlier.enumerated().map { index, star in
            CollectedStar(id: star.id, date: fixture.record.date.addingTimeInterval(Double(index - 2) * 60),
                          latitude: -6.23, longitude: 106.85)
        }
        records.append(fixture.record)
        let suite = withObservationLog ? "asterra.observations.preview" : "asterra.share.preview"
        let defaults = UserDefaults(suiteName: suite)!
        if withObservationLog {
            if let data = defaults.data(forKey: "collectedStars"),
               let previous = try? JSONDecoder().decode([CollectedStar].self, from: data) {
                Set(previous.compactMap(\.photoFilename)).forEach(StarPhotoStore.remove)
            }
            let photo = try? StarPhotoStore.save(AppPreviewData.albumPhoto)
            records[records.count - 1].photoFilename = photo
            records[records.count - 1].lightPollution = .init(sqm: 19, bortleClass: 6, datasetID: "preview")
            records.append(CollectedStar(id: fixture.id, date: fixture.record.date.addingTimeInterval(-86_400),
                latitude: -7.94, longitude: 112.95, photoFilename: photo,
                note: "Rigel above the ridge.", placeName: "Mount Bromo, East Java",
                lightPollution: .init(sqm: 21.8, bortleClass: 2, datasetID: "preview")))
        }
        defaults.removePersistentDomain(forName: suite)
        defaults.set(try? JSONEncoder().encode(records), forKey: "collectedStars")
        return HomeViewModel(location: AppPreviewData.location, date: fixture.record.date, defaults: defaults)
    }
}
#endif
