import SwiftUI
import Testing
@testable import celyx

@MainActor struct StarAlbumTests {
    /// The share image follows the Figma frame (402×874 pt at 3×).
    @Test func storyExportsAnOpaque1206By2622PNG() throws {
        var record = AppPreviewData.record
        record.identificationNote = "Uncalibrated catalog estimate."
        record.note = String(repeating:"A moment under the night sky. ",count:80)
        let item = GardenCollectionItem(star:AppPreviewData.star,record:record)
        let data = try #require(StarStoryRenderer.png(item:item,photo:AppPreviewData.albumPhoto))
        #expect(Array(data.prefix(8)) == [137,80,78,71,13,10,26,10])
        let image = try #require(UIImage(data:data)?.cgImage)
        #expect(image.width == 1206)
        #expect(image.height == 2622)
    }

    @Test func userNotesPersistWithoutChangingIdentificationMetadata() throws {
        let defaults = try #require(UserDefaults(suiteName:"celyx.tests.album-notes"))
        defaults.removePersistentDomain(forName:"celyx.tests.album-notes")
        defer { defaults.removePersistentDomain(forName:"celyx.tests.album-notes") }
        let model = HomeViewModel(location:AppPreviewData.location,date:AppPreviewData.date,defaults:defaults)
        try model.saveCameraObservation(.init(star:AppPreviewData.star,image:AppPreviewData.albumPhoto,
            date:AppPreviewData.date,location:AppPreviewData.location,identificationNote:"Estimated identity"),note:"")
        defer { model.deleteCollected(id:AppPreviewData.star.id) }
        model.updateObservationNote(id:AppPreviewData.star.id,note:"  My first star  ")
        model.updateObservationPlace(id:AppPreviewData.star.id,name:"Depok, Jawa Barat")
        let restored = HomeViewModel(location:AppPreviewData.location,date:AppPreviewData.date,defaults:defaults)
        #expect(restored.collected[AppPreviewData.star.id]?.note == "My first star")
        #expect(restored.collected[AppPreviewData.star.id]?.identificationNote == "Estimated identity")
        #expect(restored.collected[AppPreviewData.star.id]?.placeName == "Depok, Jawa Barat")
        #expect(StarPhotoStore.load(restored.collected[AppPreviewData.star.id]?.photoFilename) != nil)
    }

    @Test func oldObservationsDecodeWithoutAPlaceName() throws {
        let data = Data(#"{"id":1,"date":0,"latitude":-6.38,"longitude":106.87}"#.utf8)
        let record = try JSONDecoder().decode(CollectedStar.self,from:data)
        #expect(record.placeName == nil)
        #expect(record.latitude == -6.38)
    }

    @Test func cityNamesPreferReadablePlacesAndFallBackWithoutCoordinates() {
        #expect(ObservationPlaceName.readableName(city:"  Depok, Jawa Barat  ",region:"Indonesia") == "Depok, Jawa Barat")
        #expect(ObservationPlaceName.readableName(city:"  ",region:"Indonesia") == "Indonesia")
        var record = AppPreviewData.record; record.placeName = "Depok, Jawa Barat"
        #expect(GardenCollectionItem(star:AppPreviewData.star,record:record).albumLocation == "Depok, Jawa Barat")
    }
}
