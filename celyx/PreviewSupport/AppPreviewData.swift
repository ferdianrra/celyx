import SwiftUI

/// Deterministic, isolated canvas data. These defaults never touch the user's collection.
@MainActor enum AppPreviewData {
    static var isRunning: Bool { ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" }
    static let date = Date(timeIntervalSince1970:1793633400)
    static let location = ObserverLocation(latitude:-6.1754,longitude:106.8272,isManual:true)
    static let star = (try? SkyAssets.stars())?.first(where:{ $0.title == "Sirius" }) ?? CatalogStar.sun
    static var record: CollectedStar { .init(id:star.id,date:date,latitude:location.latitude,longitude:location.longitude,note:"A clear evening above the city.") }
    static var item: GardenCollectionItem { .init(star:star,record:record) }
    static var model: HomeViewModel { makeModel(collected:false) }
    static var collectedModel: HomeViewModel { makeModel(collected:true) }
    private static func makeModel(collected: Bool) -> HomeViewModel {
        let suite = "celyx.canvas.\(collected ? "collected" : "empty")"
        let defaults = UserDefaults(suiteName:suite)!
        defaults.removePersistentDomain(forName:suite)
        if collected { defaults.set(try? JSONEncoder().encode([record]),forKey:"collectedStars") }
        let model = HomeViewModel(location:location,date:date,defaults:defaults)
        model.scene.reduceMotion = true
        return model
    }
}
