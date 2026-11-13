import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Asterra

@MainActor
struct StarShareTests {
    private func items(count: Int) throws -> [GardenCollectionItem] {
        let stars = try SkyAssets.stars()
        return stars.prefix(count).enumerated().map { index, star in
            GardenCollectionItem(star: star, record: CollectedStar(id: star.id,
                date: Date(timeIntervalSince1970: Double(index)), latitude: -6.2, longitude: 106.85))
        }
    }

    @Test func badgesUseTheExactTierBoundaries() {
        for number in [0, 1, 3, 49] { #expect(ShareBadgeTier(number: number) == .silver) }
        for number in [50, 53, 99] { #expect(ShareBadgeTier(number: number) == .gold) }
        for number in [100, 101, 123, 1000] { #expect(ShareBadgeTier(number: number) == .astungkara) }
    }

    @Test func deletingAStarClosesTheGapAndLatestMatchesTheRemainingTotal() throws {
        let collection = try items(count: 5)
        let latest = try #require(collection.last)
        #expect(ShareCollectionOrder.number(for: latest.id, in: collection.reversed()) == 5)
        let deleted = collection[1].id
        let remaining = collection.filter { $0.id != deleted }
        #expect(ShareCollectionOrder.number(for: latest.id, in: remaining) == remaining.count)
        #expect(ShareCollectionOrder.number(for: collection[2].id, in: remaining) == 2)
        #expect(ShareCollectionOrder.number(for: deleted, in: remaining) == nil)
    }

    @Test func onlyStarsAreCountedAndEqualDatesHaveAStableOrder() throws {
        let collection = try items(count: 2)
        let date = Date(timeIntervalSince1970: 0)
        let sameDate = collection.map { GardenCollectionItem(star: $0.star,
            record: CollectedStar(id: $0.id, date: date, latitude: 0, longitude: 0)) }
        let moon = GardenCollectionItem(star: .moon,
            record: CollectedStar(id: -2, date: date, latitude: 0, longitude: 0))
        let sun = GardenCollectionItem(star: .sun,
            record: CollectedStar(id: -1, date: date, latitude: 0, longitude: 0))
        let all = sameDate.reversed() + [moon, sun]
        #expect(ShareCollectionOrder.number(for: -2, in: all) == nil)
        #expect(ShareCollectionOrder.number(for: -1, in: all) == 1)
        #expect(ShareCollectionOrder.number(for: sameDate.map(\.id).max()!, in: all) == 3)
    }

    @Test func existingRecordsRenumberAfterDeletionAndReloadWithoutMigration() throws {
        let collection = try items(count: 51)
        let latest = try #require(collection.last)
        let suite = "asterra.share.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode(collection.map(\.record)), forKey: "collectedStars")
        let model = HomeViewModel(defaults: defaults)
        #expect(ShareCollectionOrder.number(for: latest.id, in: model.collectionItems) == 51)
        model.deleteCollected(id: collection[0].id)
        model.deleteCollected(id: collection[1].id)
        let restored = HomeViewModel(defaults: defaults)
        let number = try #require(ShareCollectionOrder.number(for: latest.id, in: restored.collectionItems))
        #expect(number == 49)
        #expect(ShareBadgeTier(number: number) == .silver)
    }

    @Test func cardsUseSavedObservationTextAndHonestFallbacks() {
        let item = StarSharePreviewData.item
        let content = StarShareContent(item: item, collectionNumber: 3)
        #expect(content.note == item.record.note)
        #expect(content.lightTravel.contains(item.star.title))
        #expect(content.date.contains("2026"))
        #expect(!content.time.isEmpty)
        var record = item.record; record.note = "  \n "
        let empty = StarShareContent(item: GardenCollectionItem(star: item.star, record: record), collectionNumber: nil)
        #expect(empty.note == "A sky moment captured with Asterra.")
        #expect(StarShareContent(item: GardenCollectionItem(star: .moon, record: record), collectionNumber: nil)
            .lightTravel == "A moment under your sky.")
    }

    @Test func instagramUsesTheBundleIDAndStickerWithoutAMetaID() throws {
        let image = Data([1, 2, 3])
        let bundleID = "com.para-apple-intelligence.asterra"
        for id in [nil, "", "  ", "$(ASTERRA_META_APP_ID)", "12&other=1"] as [String?] {
            let handoff = try StarSocialShare.instagramHandoff(imageData: image, appID: id, bundleID: bundleID)
            let parts = try #require(URLComponents(url: handoff.url, resolvingAgainstBaseURL: false))
            #expect(parts.scheme == "instagram-stories")
            #expect(parts.host == "share")
            #expect(parts.queryItems == [URLQueryItem(name: "source_application", value: bundleID)])
            #expect(handoff.items["com.instagram.sharedSticker.stickerImage"] as? Data == image)
            #expect(handoff.items["com.instagram.sharedSticker.backgroundImage"] == nil)
        }
        let registered = try StarSocialShare.instagramHandoff(
            imageData: image, appID: " 123456789 ", bundleID: bundleID)
        #expect(registered.url.query == "source_application=123456789")
        #expect(registered.items["com.instagram.sharedSticker.backgroundImage"] as? Data == image)
        #expect(throws: StarSocialShare.Failure.self) {
            try StarSocialShare.instagramHandoff(imageData: image, appID: nil, bundleID: nil)
        }
    }

    @Test func moreHandoffContainsAPNGAndCanBeCleanedUp() throws {
        let request = try StarSocialShare.pngFile(AppPreviewData.albumPhoto)
        defer { request.removeFile() }
        #expect(request.url.pathExtension == "png")
        let data = try Data(contentsOf: request.url)
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        let image = try #require(UIImage(data: data))
        #expect(image.size.width == AppPreviewData.albumPhoto.size.width)
        let another = try StarSocialShare.pngFile(AppPreviewData.albumPhoto)
        defer { another.removeFile() }
        #expect(request.url != another.url)
        request.removeFile()
        #expect(!FileManager.default.fileExists(atPath: request.url.path))
        #expect(FileManager.default.fileExists(atPath: another.url.path))
    }

    @Test func installedAppChecksAreDeclaredInTheBuiltApp() throws {
        let schemes = try #require(Bundle.main.object(forInfoDictionaryKey: "LSApplicationQueriesSchemes") as? [String])
        #expect(schemes.contains("instagram-stories"))
        #expect(schemes.contains("whatsapp"))
        let appID = try #require(Bundle.main.object(forInfoDictionaryKey: "FacebookAppID") as? String)
        #expect(!appID.contains("$("))
    }

    @Test func allFigmaAssetsAreBundled() {
        for name in ["asterra-share-background", "asterra-instagram", "asterra-whatsapp", "asterra-logo-orbit", "asterra-logo-symbol",
                     "asterra-telescope", "asterra-card-light"] + ShareBadgeTier.allCases.map(\.asset) {
            #expect(UIImage(named: name) != nil)
        }
    }

    @Test func bothLayoutsRenderAtStoryResolutionAndBadgesRenderForReview() throws {
        let content = StarShareContent(item: StarSharePreviewData.item, collectionNumber: 3)
        for layout in ShareCardLayout.allCases {
            let image = try #require(StarShareRenderer.image(content: content, layout: layout, photo: nil))
            let cg = try #require(image.cgImage)
            #expect(cg.width == 1080 && cg.height == 1920)
            let data = try #require(image.pngData())
            try data.write(to: URL(fileURLWithPath: "/private/tmp/asterra-card-\(layout.rawValue).png"))
        }
        let badges = HStack(spacing: 20) {
            ForEach([3, 53, 123], id: \.self) { ShareCollectionBadge(number: $0) }
        }.padding(20).background(Color(white: 0.12))
        let renderer = ImageRenderer(content: badges); renderer.scale = 3
        try #require(renderer.uiImage?.pngData()).write(to: URL(fileURLWithPath: "/private/tmp/asterra-badges.png"))
    }

    @Test func photoAndLongNoteCanRenderWithoutChangingCanvasSize() throws {
        var record = StarSharePreviewData.item.record
        record.note = String(repeating: "A beautiful sky observation. ", count: 40)
        let content = StarShareContent(item: GardenCollectionItem(star: StarSharePreviewData.item.star, record: record),
                                       collectionNumber: 123)
        for layout in ShareCardLayout.allCases {
            let image = try #require(StarShareRenderer.image(content: content, layout: layout, photo: AppPreviewData.albumPhoto))
            #expect(image.cgImage?.width == 1080)
            #expect(image.cgImage?.height == 1920)

        }
    }
}
