import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Asterra

@MainActor struct CameraAutomaticIdentificationTests {
    private var jupiter: CameraCandidateMatch {
        .init(star: CatalogStar.planets[3], separation: 0.3, score: 0.3)
    }
    @Test func aConsistentSingleSourceBecomesCollectibleWithoutManualSkyCalibration() throws {
        var decision = CameraAutomaticIdentification()
        for time in [10.0, 10.25, 10.5] { decision.update(candidate: jupiter, sourceID: 7, observedAt: time) }
        #expect(try #require(decision.freshMatch(at: 10.6)).star.title == "Jupiter")

    }
    @Test func aRealCapturedPhotoStaysAvailableWhileThePhoneIsLoweredToPressCollect() {
        var decision = CameraAutomaticIdentification()
        for time in [10.0, 10.25, 10.5] { decision.update(candidate: jupiter, sourceID: 7, observedAt: time) }
        #expect(decision.freshMatch(at: 12) == nil)
        #expect(decision.canOfferCapturedPhoto(starID: jupiter.star.id, sourceID: 7, at: 12))
        #expect(!decision.canOfferCapturedPhoto(starID: jupiter.star.id, sourceID: 8, at: 12))
        #expect(!decision.canOfferCapturedPhoto(starID: jupiter.star.id, sourceID: 7, at: 16))
        decision.update(candidate: nil, sourceID: 7, observedAt: 12.2)
        #expect(!decision.canOfferCapturedPhoto(starID: jupiter.star.id, sourceID: 7, at: 12.3))
    }
    @Test func aGeometricResightingKeepsTheStableNameButRequiresNewOpticalEvidence() throws {
        var decision = CameraAutomaticIdentification()
        for time in [10.0, 10.25, 10.5] { decision.update(candidate: jupiter, sourceID: 7, observedAt: time) }
        decision.continueSource(from: 7, to: 9)
        #expect(decision.freshMatch(at: 30) == nil, "Remembering a name cannot fabricate a sighting")
        decision.update(candidate: jupiter, sourceID: 9, observedAt: 30)
        #expect(try #require(decision.freshMatch(at: 30.1)).star.title == "Jupiter")
        decision.update(candidate: jupiter, sourceID: 10, observedAt: 30.2)
        #expect(decision.stableMatch == nil, "A genuinely new optical source still needs its own consensus")
    }

    @Test func repeatedRenderFramesDoNotCountAsIndependentEvidence() {
        var decision = CameraAutomaticIdentification()
        for _ in 0..<50 { decision.update(candidate: jupiter, sourceID: 7, observedAt: 10) }
        #expect(decision.stableMatch == nil)
        decision.update(candidate: jupiter, sourceID: 7, observedAt: 10.2)
        #expect(decision.stableMatch == nil)
    }
    @Test func ambiguityOrANewSourceRemovesThePreviousCollectibleIdentity() {
        var decision = CameraAutomaticIdentification()
        for time in [10.0, 10.25, 10.5] { decision.update(candidate: jupiter, sourceID: 7, observedAt: time) }
        #expect(decision.stableMatch != nil)
        decision.update(candidate: nil, sourceID: 7, observedAt: 10.7)
        #expect(decision.stableMatch == nil)
        for time in [11.0, 11.25, 11.5] { decision.update(candidate: jupiter, sourceID: 7, observedAt: time) }
        #expect(decision.stableMatch != nil)
        decision.update(candidate: jupiter, sourceID: 8, observedAt: 11.7)
        #expect(decision.stableMatch == nil)
    }
    @Test func changingCandidateNamesMustSettleAgainAndOldSupportCannotPretendToBeFresh() throws {
        var decision = CameraAutomaticIdentification()
        for time in [10.0, 10.25, 10.5] { decision.update(candidate: jupiter, sourceID: 7, observedAt: time) }
        #expect(decision.freshMatch(at: 12) == nil)
        #expect(decision.stableMatch != nil, "The captured photo may remain while the same identity is retained")
        let saturn = CameraCandidateMatch(star: CatalogStar.planets[4], separation: 0.2, score: 0.2)
        decision.update(candidate: saturn, sourceID: 7, observedAt: 10.7)
        #expect(decision.stableMatch == nil)
        decision.update(candidate: saturn, sourceID: 7, observedAt: 10.95)
        decision.update(candidate: saturn, sourceID: 7, observedAt: 11.2)
        #expect(try #require(decision.freshMatch(at: 11.3)).star.title == "Saturn")
    }
    @Test func compactInformationCardRendersWithoutTheLegacyStatusRow() throws {
        let content = CameraCollectionCard(star: jupiter.star, onCollect: {}, onDismiss: {})
            .frame(width: 353).fixedSize(horizontal: false, vertical: true)
            .padding(20).background(CelyxColor.night).preferredColorScheme(.dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try #require(renderer.uiImage)
        #expect(image.size.width == 393)
        #expect(image.size.height >= 104 && image.size.height < 200)
        try #require(image.pngData()).write(to: URL(fileURLWithPath: "/tmp/celyx-automatic-collect-card.png"))
    }
}
