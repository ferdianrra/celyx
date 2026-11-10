import Foundation

enum CameraCollectionMode: Identifiable, Hashable {
    case star
    case event(SkyEvent)
    var id: String {
        switch self {
        case .star: "star"
        case .event(let event): "event-" + event.id
        }
    }
}
