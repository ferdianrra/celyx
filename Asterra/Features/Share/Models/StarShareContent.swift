import Foundation

struct StarShareContent {
    let item: GardenCollectionItem
    let collectionNumber: Int?
    var hasLightPollution: Bool { item.record.lightPollution != nil }

    var lightPollution: String {
        guard let estimate = item.record.lightPollution else { return "Unavailable" }
        let sqm = estimate.sqm.formatted(.number.precision(.fractionLength(2)))
        return "Bortle \(estimate.bortleClass) · SQM \(sqm)"
    }

    var lightPollutionDetail: String {
        hasLightPollution ? "\(lightPollution) mag/arcsec²" : lightPollution
    }
    var note: String {
        let value = item.record.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "A sky moment captured with Asterra." : value
    }
    var lightTravel: String {
        if item.star.isSun { return "Sunlight takes about 8 minutes to reach Earth." }
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
