import Foundation
import Testing
import simd
@testable import Asterra

@MainActor struct SingleLightRecognitionTests {
    private let ray = simd_normalize(SIMD3<Float>(0.3, 0.5, -0.8))
    private var jupiter: CatalogStar { CatalogStar.planets.first { $0.title == "Jupiter" }! }

    @Test func onePointCanSuggestJupiterWithoutFourStarsOrASavedAlignment() throws {
        let result = CameraIdentityPolicy.suggest(direction: ray, isDisc: false, zoom: 1,
            headingAccuracy: 5, candidates: [(jupiter, ray)])
        #expect(try #require(result.match).star.isPlanet)
        #expect(result.match?.star.title == "Jupiter")
        // The same proposal still must not silently become a verified observation.
        #expect(CameraIdentityPolicy.assess(direction: ray, isDisc: false, zoom: 1,
            hasReferenceAlignment: false, candidates: [(jupiter, ray)], hasOpticalEvidence: true).match == nil)
    }

    @Test func onePointCanSuggestAnOrdinaryStarAsWellAsAPlanet() throws {
        let star = AppPreviewData.star
        let result = CameraIdentityPolicy.suggest(direction: ray, isDisc: false, zoom: 1,
            headingAccuracy: 3, candidates: [(star, ray)])
        #expect(try #require(result.match).star.id == star.id)
    }

    @Test func sparseProposalsRejectUncertainHeadingWrongAltitudeAndResolvedLamps() {
        for accuracy in [Double?.none, -1, .nan, 25] {
            #expect(CameraIdentityPolicy.suggest(direction: ray, isDisc: false, zoom: 1,
                headingAccuracy: accuracy, candidates: [(jupiter, ray)]).match == nil)
        }
        let tooHigh = simd_normalize(SIMD3<Float>(0, 0.95, -0.3))
        #expect(CameraIdentityPolicy.suggest(direction: ray, isDisc: false, zoom: 1,
            headingAccuracy: 5, candidates: [(jupiter, tooHigh)]).match == nil)
        #expect(CameraIdentityPolicy.suggest(direction: ray, isDisc: true, zoom: 1,
            headingAccuracy: 5, candidates: [(jupiter, ray)]).match == nil)
    }

    @Test func competingPointCandidatesDoNotAcquireAnArbitraryName() {
        let second = CatalogStar.planet(id: -7, name: "Saturn", magnitude: jupiter.mag)
        let result = CameraIdentityPolicy.suggest(direction: ray, isDisc: false, zoom: 1,
            headingAccuracy: 5, candidates: [(jupiter, ray), (second, ray)])
        #expect(result.match == nil && result.issue == .ambiguous)
    }
}
