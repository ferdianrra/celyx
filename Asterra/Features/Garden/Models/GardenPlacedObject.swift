import Foundation

struct GardenPlacedObject: Identifiable {
    let item: GardenCollectionItem
    let object: NightSeaObject
    var isPreview = false
    var id: Int { item.id }
}
