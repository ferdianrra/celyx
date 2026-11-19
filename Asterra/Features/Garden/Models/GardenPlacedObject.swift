import Foundation

struct GardenPlacedObject: Identifiable {
    let item: GardenCollectionItem
    let object: NightSeaObject
    var isPreview = false
    var memberName: String? = nil
    var id: Int { object.id }
    var title: String { memberName ?? item.star.title }
    var titleIsAbove: Bool { memberName != nil && id == item.id }

    var selectionItem: GardenCollectionItem {
        guard let memberName else { return item }
        let body = memberName == CatalogStar.moon.title ? CatalogStar.moon
            : CatalogStar.planets.first { $0.title == memberName }
        guard let body else { return item }
        return GardenCollectionItem(star: body, record: item.record)
    }
}
