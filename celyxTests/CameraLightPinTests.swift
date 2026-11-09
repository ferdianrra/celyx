import Foundation
import Testing
import simd

@testable import celyx

@MainActor
struct CameraLightPinTests {
    private let ray = SIMD3<Float>(0, 0, -1)
    private var match: CameraCandidateMatch {
        .init(star: AppPreviewData.star, separation: 1, score: 1)
    }

    @Test func aCollectibleSourceKeepsItsNameWhenCatalogCandidatesChange() throws {
        let other = CatalogStar(
            id: 322, ra_deg: 0, dec_deg: 0, mag: 4, bv: nil, name: "Star 322", designation: nil,
            distance_ly: nil, con: nil, collectible_candidate: true)
        let alternate = CameraCandidateMatch(star: other, separation: 0.1, score: 0.1)
        var pin = CameraLightPin(direction: ray, time: 10, observations: 2, opticalID: 17)
        pin.assess(.init(match: match, issue: .stabilizing))
        #expect(pin.observedMatch(at: 10) == nil)
        pin.identify(using: match)  // Same transition as retaining a collectible photograph.
        let shifted = simd_normalize(SIMD3<Float>(0.03, 0, -1))
        pin.observe(direction: shifted, time: 10.2, identifiedAs: alternate, opticalID: 17)
        pin.assess(.init(match: alternate, issue: .stabilizing))
        #expect(try #require(pin.match).star.id == match.star.id)
        #expect(try #require(pin.stableMatch(for: 17, direction: shifted)).star.id == match.star.id)
        #expect(pin.lastSeen == 10.2)
        let separate = simd_normalize(SIMD3<Float>(0.3, 0, -1))
        #expect(pin.stableMatch(for: 18, direction: separate) == nil)
        #expect(pin.canBeReplaced(by: separate, identifiedAs: alternate))
    }

    @Test func aCandidateCannotOfferCollectBeforeIdentityConfirmation() throws {
        var pin = CameraLightPin(direction: ray, time: 10, observations: 1)
        pin.assess(.init(match: match, issue: .stabilizing))
        #expect(pin.observedMatch(at: 10) == nil)
        pin.observe(direction: ray, time: 10.2)
        pin.assess(.init(match: match, issue: .stabilizing))
        #expect(!pin.isIdentified)
        #expect(pin.observedMatch(at: 10.3) == nil)
        pin.confirm(.init(match: match, issue: .stabilizing), observedAt: 10.2, insideReticle: true)
        pin.confirm(.init(match: match, issue: .stabilizing), observedAt: 10.3, insideReticle: true)
        #expect(try #require(pin.observedMatch(at: 10.3)).star.id == match.star.id)
        #expect(pin.observedMatch(at: 11) == nil)
    }

    @Test func aRememberedNameCannotRenewCollectionAfterContradictoryEvidence() {
        var pin = CameraLightPin(direction: ray, time: 10, observations: 4)
        let supported = CameraCandidateAssessment(match: match, issue: .stabilizing)
        pin.assess(supported)
        pin.confirm(supported, observedAt: 10, insideReticle: true)
        pin.confirm(supported, observedAt: 10.2, insideReticle: true)
        #expect(pin.observedMatch(at: 10.2) != nil)
        let unsupported = CameraCandidateAssessment(match: nil, issue: .ambiguous)
        pin.assess(unsupported)
        pin.confirm(unsupported, observedAt: 10.3, insideReticle: true)
        #expect(pin.isIdentified, "The remembered identity may remain for navigation")
        #expect(pin.observedMatch(at: 10.3) == nil, "It must not authorize a new photograph")
    }

    @Test func anUnsupportedSuggestionDoesNotAcquireANewPhoto() {
        var pin = CameraLightPin(direction: ray, time: 10, observations: 2)
        pin.assess(.init(match: match, issue: .stabilizing))
        pin.assess(.init(match: nil, issue: .ambiguous))
        #expect(pin.match != nil)
        #expect(pin.observedMatch(at: 10.1) == nil)
    }

    @Test func anUnnamedLightCanBeSelectedToRestoreAlignment() {
        var pin = CameraLightPin(direction: ray, time: 10, observations: 1)
        #expect(!pin.canUseAsReference(at: 10, distance: 0))
        pin.observe(direction: ray, time: 10.2)
        #expect(pin.canUseAsReference(at: 10.2, distance: 20))
        #expect(pin.match == nil)
        #expect(!pin.isIdentified, "Detecting the light must not invent its reference name")
    }

    @Test func selectingAReferenceRequiresFreshLightInsideTheReticle() {
        let pin = CameraLightPin(direction: ray, time: 10, observations: 2)
        #expect(pin.canUseAsReference(at: 10.5, distance: 28))
        #expect(!pin.canUseAsReference(at: 10.7, distance: 0))
        #expect(!pin.canUseAsReference(at: 10.1, distance: 29))
        #expect(!pin.canUseAsReference(at: 9.9, distance: 0))
    }

    @Test func aRememberedLightSurvivesWithoutNewCameraObservations() {
        var pin = CameraLightPin(direction: ray, time: 10, observations: 2)
        pin.assess(.init(match: nil, issue: .ambiguous))
        #expect(pin.isRecognizing(at: 12))
        #expect(!pin.isRecognizing(at: 17))
        #expect(pin.direction == ray)
        #expect(pin.lastSeen == 10)
        pin.assess(.init(match: match, issue: .stabilizing))
        #expect(pin.match?.star.id == match.star.id)
        #expect(!pin.isRecognizing(at: 18))
        #expect(pin.lastSeen == 10, "A catalog assessment must not invent a fresh optical observation")
    }

    @Test func recognizingAPinNeverCountsCachedFramesAsNewLight() {
        var pin = CameraLightPin(direction: ray, time: 10, observations: 1)
        pin.assess(.init(match: match, issue: .stabilizing))
        #expect(pin.match == nil)
        pin.observe(direction: ray, time: 10)
        #expect(pin.observationCount == 1)
        pin.observe(direction: ray, time: 10.2)
        pin.assess(.init(match: match, issue: .stabilizing))
        #expect(pin.observationCount == 2)
        #expect(pin.match != nil)
    }

    @Test func laterAmbiguityKeepsTheLastSupportedSuggestion() {
        var pin = CameraLightPin(direction: ray, time: 0, observations: 3)
        pin.assess(.init(match: match, issue: .stabilizing))
        pin.assess(.init(match: nil, issue: .ambiguous))
        #expect(pin.match?.star.id == match.star.id)
        #expect(pin.issue == .ambiguous)
    }

    @Test func aTurnReprojectsThePinOutsideTheReticleWithoutMovingItsWorldRay() throws {
        let pin = CameraLightPin(direction: ray, time: 0, observations: 2)
        var projection = matrix_identity_float4x4
        projection.columns.2 = SIMD4(0, 0, -1, -1)
        projection.columns.3 = SIMD4(0, 0, -0.02, 0)
        let size = CGSize(width: 400, height: 800)
        let initial = SkyFinderProjection.project(
            direction: pin.direction, view: matrix_identity_float4x4, projection: projection, size: size)
        #expect(try #require(initial.point).x == 200)
        let turn = simd_float4x4(simd_quatf(angle: Float.pi / 3, axis: SIMD3(0, 1, 0)))
        let turned = SkyFinderProjection.project(
            direction: pin.direction, view: turn, projection: projection, size: size)
        #expect(turned.point == nil)
        #expect(abs(turned.separation - 60) < 0.01)
        #expect(abs(turned.arrow.dx) > 0.99)
        #expect(pin.direction == ray)
    }

    @Test func onlyANearbyRayCanRefreshTheSamePin() {
        let pin = CameraLightPin(direction: ray, time: 0, observations: 2)
        let near = simd_quatf(angle: 0.2 * .pi / 180, axis: SIMD3<Float>(0, 1, 0)).act(ray)
        let other = simd_quatf(angle: 3 * .pi / 180, axis: SIMD3<Float>(0, 1, 0)).act(ray)
        #expect(pin.isSameSource(near))
        #expect(!pin.isSameSource(other))
    }

    @Test func settlingExpiresOnUptimeAndResetsForANewSession() {
        var settling = CameraControlSettling()
        settling.begin(at: 1000)
        #expect(settling.isActive(at: 1000.2))
        #expect(!settling.isActive(at: 1000.7))
        settling.begin(at: 2000)
        settling.reset()
        #expect(!settling.isActive(at: 2000.1))
    }
    @Test func aReturningLightNeedsFreshIndependentSightingsBeforeBecomingDetected() {
        var pin = CameraLightPin(direction: ray, time: 0, observations: 3)
        let assessment = CameraCandidateAssessment(match: match, issue: .stabilizing)
        pin.assess(assessment)
        pin.confirm(assessment, observedAt: nil, insideReticle: true)
        #expect(!pin.isDetected(at: 10), "A remembered position alone cannot detect a light")
        pin.confirm(assessment, observedAt: 10, insideReticle: true)
        pin.confirm(assessment, observedAt: 10, insideReticle: true)
        #expect(!pin.isDetected(at: 10.1), "Cached frames must not finish reacquisition")
        pin.confirm(assessment, observedAt: 10.2, insideReticle: true)
        #expect(pin.isDetected(at: 10.3))
        #expect(!pin.isDetected(at: 11), "Old observations expire")
    }

    @Test func leavingTheReticleOrAnAmbiguousIdentityResetsReacquisition() {
        var pin = CameraLightPin(direction: ray, time: 0, observations: 3)
        let assessment = CameraCandidateAssessment(match: match, issue: .stabilizing)
        pin.assess(assessment)
        pin.confirm(assessment, observedAt: 1, insideReticle: true)
        pin.confirm(assessment, observedAt: 1.2, insideReticle: true)
        #expect(pin.isDetected(at: 1.3))
        pin.confirm(assessment, observedAt: nil, insideReticle: false)
        #expect(!pin.isDetected(at: 1.3))
        pin.confirm(assessment, observedAt: 2, insideReticle: true)
        pin.confirm(.init(match: nil, issue: .ambiguous), observedAt: 2.2, insideReticle: true)
        #expect(!pin.isDetected(at: 2.3))
        #expect(pin.match != nil, "Keep the navigation suggestion while rechecking its identity")
    }

    @Test func aGapBetweenSightingsCannotConfirmThePin() {
        var pin = CameraLightPin(direction: ray, time: 0, observations: 3)
        let assessment = CameraCandidateAssessment(match: match, issue: .stabilizing)
        pin.assess(assessment)
        pin.confirm(assessment, observedAt: 1, insideReticle: true)
        pin.confirm(assessment, observedAt: 2, insideReticle: true)
        #expect(!pin.isDetected(at: 2.1))
    }

    @Test func identificationSurvivesLeavingTheCircleAndLosingFreshEvidence() {
        var pin = CameraLightPin(direction: ray, time: 0, observations: 3)
        let assessment = CameraCandidateAssessment(match: match, issue: .stabilizing)
        pin.assess(assessment)
        pin.confirm(assessment, observedAt: 1, insideReticle: true)
        pin.confirm(assessment, observedAt: 1.2, insideReticle: true)
        pin.confirm(assessment, observedAt: nil, insideReticle: false)
        pin.assess(.init(match: nil, issue: .ambiguous))
        #expect(pin.isIdentified)
        #expect(pin.identifiedMatch?.star.id == match.star.id)
        #expect(pin.match?.star.id == match.star.id)
        #expect(!pin.isDetected(at: 100), "Remembering a name does not authorize collection")
        #expect(!pin.isRecognizing(at: 100))
        #expect(pin.direction == ray)
    }

    @Test func aNewAmbiguousLightCannotReplaceTheLastIdentifiedStar() {
        var pin = CameraLightPin(direction: ray, time: 0, observations: 3)
        pin.identify(using: match)
        let otherRay = simd_quatf(angle: 0.1, axis: SIMD3<Float>(0, 1, 0)).act(ray)
        #expect(!pin.canBeReplaced(by: otherRay, identifiedAs: nil))
        #expect(!pin.canBeReplaced(by: otherRay, identifiedAs: match))
        let other = CameraCandidateMatch(star: .moon, separation: 1, score: 1)
        #expect(pin.canBeReplaced(by: otherRay, identifiedAs: other))
        #expect(!pin.canBeReplaced(by: ray, identifiedAs: other))
    }

    @Test func repeatedCatalogAssessmentsCannotRenameAnIdentifiedSource() {
        var pin = CameraLightPin(direction: ray, time: 0, observations: 3)
        pin.identify(using: match)
        pin.assess(.init(match: .init(star: .moon, separation: 0.5, score: 0.5), issue: .stabilizing))
        #expect(pin.match?.star.id == match.star.id)
        let otherRay = simd_quatf(angle: 0.1, axis: SIMD3<Float>(0, 1, 0)).act(ray)
        pin.observe(direction: otherRay, time: 1)
        #expect(pin.direction == ray)
        #expect(pin.lastSeen == 0)
    }

    @Test func aFreshSameIdentityReattachesAfterABoundedTrackingDiscontinuity() {
        var pin = CameraLightPin(direction: ray, time: 0, observations: 3)
        pin.identify(using: match)
        let shifted = simd_quatf(angle: 2 * .pi / 180, axis: SIMD3<Float>(0, 1, 0)).act(ray)
        pin.observe(direction: shifted, time: 1)
        #expect(pin.direction == ray, "A remembered position alone cannot move the pin")
        pin.observe(direction: shifted, time: 1, identifiedAs: match)
        #expect(pin.direction == shifted)
        #expect(pin.lastSeen == 1)
        #expect(pin.identifiedMatch?.star.id == match.star.id)
        let distant = simd_quatf(angle: 10 * .pi / 180, axis: SIMD3<Float>(0, 1, 0)).act(ray)
        pin.observe(direction: distant, time: 2, identifiedAs: match)
        #expect(pin.direction == shifted, "A matching name cannot teleport a pin to a distant light")
    }

    @Test func aNearbyDifferentIdentifiedLightCannotDragTheOldPin() {
        var pin = CameraLightPin(direction: ray, time: 0, observations: 3)
        pin.identify(using: match)
        let nearby = simd_quatf(angle: 0.2 * .pi / 180, axis: SIMD3<Float>(0, 1, 0)).act(ray)
        pin.observe(direction: nearby, time: 1, identifiedAs: .init(star: .moon, separation: 0, score: 0))
        #expect(pin.direction == ray)
        #expect(pin.lastSeen == 0)
    }

}
