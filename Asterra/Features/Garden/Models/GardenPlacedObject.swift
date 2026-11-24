import Foundation

struct GardenPlacedObject: Identifiable {
    let item: GardenCollectionItem
    let object: NightSeaObject
    var id: Int { item.id }
}
