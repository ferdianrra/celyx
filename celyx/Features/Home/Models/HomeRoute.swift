import Foundation

enum HomeRoute: Hashable {
    case calendar
    case event(SkyEvent)
    case collection(CollectionCategory)
}
