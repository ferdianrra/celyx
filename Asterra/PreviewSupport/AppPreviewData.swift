import SwiftUI
import UIKit

/// Deterministic, isolated canvas data. These defaults never touch the user's collection.
@MainActor enum AppPreviewData {
    static var isRunning: Bool { ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" }
    static let date = Date(timeIntervalSince1970:1793633400)
    static let location = ObserverLocation(latitude:-6.1754,longitude:106.8272,isManual:true)
    static let star = (try? SkyAssets.stars())?.first(where:{ $0.title == "Sirius" }) ?? CatalogStar.sun
    static var record: CollectedStar { .init(id:star.id,date:date,latitude:location.latitude,longitude:location.longitude,
        note:"A clear evening above the city.",placeName:"Jakarta Pusat, Jakarta") }
    static var item: GardenCollectionItem { .init(star:star,record:record) }
    static var model: HomeViewModel { makeModel(collected:false) }
    static var collectedModel: HomeViewModel { makeModel(collected:true) }
    /// Deterministic sample photograph used only by previews and UI tests.
    static var albumPhoto: UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size:CGSize(width:600,height:760),format:format).image { context in
            UIColor(red:0.025,green:0.035,blue:0.09,alpha:1).setFill()
            context.fill(CGRect(x:0,y:0,width:600,height:760))
            for index in 0..<180 {
                let x = CGFloat((index*137+41)%600), y = CGFloat((index*211+73)%760)
                UIColor.white.withAlphaComponent(Double(index%6+1)/8).setFill()
                context.fill(CGRect(x:x,y:y,width:1.5,height:1.5))
            }
            context.cgContext.setShadow(offset:.zero,blur:18,color:UIColor.white.cgColor)
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in:CGRect(x:296,y:270,width:6,height:6))
        }
    }
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
