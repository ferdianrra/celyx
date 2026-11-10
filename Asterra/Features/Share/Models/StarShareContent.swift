import Foundation

struct StarShareContent {
    let item: GardenCollectionItem
    let collectionNumber: Int?
    // Temporary design data; supply the measured rating here when available.
    var lightPollution: String = "6.2/9"
    var note: String {
        let value = item.record.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "A sky moment captured with Asterra." : value
    }
    var lightTravel: String {
        guard let distance = item.star.distance_ly, distance.isFinite, distance > 0,
            !item.star.isSolarSystemBody else { return "A moment under your sky." }
        let years = distance.formatted(.number.precision(.fractionLength(0)).locale(Locale(identifier: "en_US")))
        return "The light you saw left \(item.star.title) ~\(years) years ago."
    }
    var date: String {
        item.record.date.formatted(.dateTime.month(.abbreviated).day().year().locale(Locale(identifier: "en_US")))
    }
    var time: String {
        item.record.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
            .locale(Locale(identifier: "en_GB")))
    }
}
