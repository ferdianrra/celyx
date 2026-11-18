import Foundation

enum ShareCollectionOrder {
    /// Chronological rank in the current star collection, derived rather than persisted.
    static func number(for id: Int, in items: [GardenCollectionItem]) -> Int? {
        let stars = CollectionCategory.stars(items).sorted {
            $0.record.date == $1.record.date ? $0.id < $1.id : $0.record.date < $1.record.date
        }
        return stars.firstIndex { $0.id == id }.map { $0 + 1 }
    }
}

enum ShareBadgeTier: String, CaseIterable {
    case silver, gold, astungkara
    init(number: Int) {
        self = number >= 100 ? .astungkara : number >= 50 ? .gold : .silver
    }
    var asset: String { "asterra-badge-\(rawValue)" }
}
