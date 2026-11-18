import SwiftUI
import Testing
@testable import Asterra

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

    @Test func guidedSunPersistsWithoutACameraPhotoAndReplayPreservesItsNote() throws {
        let name = "celyx.tests.guided-sun"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let model = HomeViewModel(location: AppPreviewData.location, date: AppPreviewData.date, defaults: defaults)
        try model.saveGuidedSun(image: nil, date: AppPreviewData.date, location: AppPreviewData.location)
        #expect(model.collectionItems.contains { $0.star.isSun })
        model.updateObservationNote(id: CatalogStar.sun.id, note: "My first Sun")
        try model.saveGuidedSun(image: AppPreviewData.albumPhoto, date: Date(), location: AppPreviewData.location)
        let restored = HomeViewModel(defaults: defaults)
        #expect(restored.collected[CatalogStar.sun.id]?.note == "My first Sun")
        #expect(restored.collected[CatalogStar.sun.id]?.date == AppPreviewData.date)
        #expect(restored.collected[CatalogStar.sun.id]?.identificationNote == OnboardingCopy.guidedSunIdentificationNote)
        #expect(restored.collected[990_001] == nil)
    }

    @Test func oldObservationsDecodeWithoutAPlaceName() throws {
        let data = Data(#"{"id":1,"date":0,"latitude":-6.38,"longitude":106.87}"#.utf8)
        let record = try JSONDecoder().decode(CollectedStar.self,from:data)
        #expect(record.placeName == nil)
        #expect(record.latitude == -6.38)
    }

    @Test func repeatCapturesPreserveLegacyHistoryAndDeleteOnlyTheSelectedPhoto() throws {
        let suite = "asterra.repeat-captures.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let star = AppPreviewData.star
        var legacy = AppPreviewData.record
        legacy.photoFilename = try StarPhotoStore.save(AppPreviewData.albumPhoto)
        defer { if let filename = legacy.photoFilename { StarPhotoStore.remove(filename) } }
        legacy.note = "First observation"
        defaults.set(try JSONEncoder().encode([legacy]), forKey: "collectedStars")
        let model = HomeViewModel(defaults: defaults)
        let firstID = try #require(model.observationHistory(for: star.id).first?.captureID)
        let next = try model.saveCameraObservation(.init(star: star, image: AppPreviewData.albumPhoto,
            date: legacy.date.addingTimeInterval(60), location: AppPreviewData.location,
            identificationNote: "Second identification"), note: "Second observation")
        defer { if let filename = next.photoFilename { StarPhotoStore.remove(filename) } }
        let secondID = try #require(next.captureID)
        model.updateObservationNote(captureID: firstID, note: "Edited first")
        model.updateObservationPlace(captureID: secondID, name: "Bandung")

        let restored = HomeViewModel(defaults: defaults)
        #expect(restored.collectionItems.filter { $0.id == star.id }.count == 1)
        #expect(restored.observationHistory(for: star.id).compactMap(\.captureID) == [secondID, firstID])
        #expect(restored.observation(captureID: firstID)?.note == "Edited first")
        #expect(restored.observation(captureID: secondID)?.note == "Second observation")
        #expect(restored.observation(captureID: secondID)?.placeName == "Bandung")
        #expect(StarPhotoStore.load(legacy.photoFilename) != nil)
        #expect(StarPhotoStore.load(next.photoFilename) != nil)

        restored.deleteObservation(captureID: secondID)
        #expect(restored.collected[star.id]?.captureID == firstID)
        #expect(StarPhotoStore.load(next.photoFilename) == nil)
        #expect(StarPhotoStore.load(legacy.photoFilename) != nil)
        restored.deleteObservation(captureID: firstID)
        #expect(restored.collected[star.id] == nil)
    }

    @Test func cityNamesPreferReadablePlacesAndFallBackWithoutCoordinates() {
        #expect(ObservationPlaceName.readableName(city:"  Depok, Jawa Barat  ",region:"Indonesia") == "Depok, Jawa Barat")
        #expect(ObservationPlaceName.readableName(city:"  ",region:"Indonesia") == "Indonesia")
        var record = AppPreviewData.record; record.placeName = "Depok, Jawa Barat"
        #expect(GardenCollectionItem(star:AppPreviewData.star,record:record).albumLocation == "Depok, Jawa Barat")
    }
}
