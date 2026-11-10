import CoreGraphics
import Testing
import simd

@testable import Asterra

@MainActor struct CameraTargetSelectionTests {
    private let center = CGPoint(x: 200, y: 400)

    @Test func oneContinuouslyVisiblePointSurvivesASmallWorldProjectionShift() {
        #expect(
            CameraTargetSelection.continuesSingleSource(
                previousPoint: center,
                point: CGPoint(x: center.x + 4, y: center.y + 3), gap: 0.12))
        #expect(
            !CameraTargetSelection.continuesSingleSource(
                previousPoint: center,
                point: CGPoint(x: center.x + 80, y: center.y), gap: 0.12))
        #expect(!CameraTargetSelection.continuesSingleSource(previousPoint: center, point: center, gap: 2))
        #expect(!CameraTargetSelection.continuesSingleSource(previousPoint: nil, point: center, gap: 0.12))
    }

    @Test func canopusRemainsCollectibleWhenFreshPixelsMomentarilyDisappear() throws {
        func annotation(_ id: Int, _ name: String) -> CameraStarAnnotation {
            let star = CatalogStar(
                id: id, ra_deg: 0, dec_deg: 0, mag: 0, bv: nil, name: name, designation: nil,
                distance_ly: nil, con: nil, collectible_candidate: true)
            return CameraStarAnnotation(
                star: star, point: center, size: CGSize(width: 8, height: 8),
                sourceDirection: SIMD3(0, 0.5, -0.866), observedAt: 10)
        }
        let canopus = annotation(1, "Canopus")
        let sirius = annotation(2, "Sirius")
        let saved = CameraTargetSelection.captureEvidence(for: canopus.id, live: nil, retained: canopus)
        #expect(try #require(saved).id == canopus.id)
        let next = CameraTargetSelection.captureEvidence(for: sirius.id, live: sirius, retained: canopus)
        #expect(try #require(next).id == sirius.id)
        #expect(CameraTargetSelection.captureEvidence(for: sirius.id, live: nil, retained: canopus) == nil)
    }

    @Test func movingFromCanopusToAnotherLightStartsScanningWithoutCollectingCanopus() {
        #expect(
            CameraTargetSelection.beginsNewSource(
                previousPoint: CGPoint(x: 380, y: 400),
                newPoint: center, center: center, observations: 3))
        #expect(
            CameraTargetSelection.beginsNewSource(
                previousPoint: nil,
                newPoint: center, center: center, observations: 3))
    }
    @Test func slightHandShakeKeepsTheReadyPhotoAndDoesNotSwitchSources() {
        let shifted = CGPoint(x: 240, y: 400)
        #expect(CameraTargetSelection.keepsRetainedTarget(at: shifted, center: center))
        #expect(
            !CameraTargetSelection.beginsNewSource(
                previousPoint: shifted,
                newPoint: CGPoint(x: 232, y: 400), center: center, observations: 3))
        #expect(!CameraTargetSelection.keepsRetainedTarget(at: CGPoint(x: 380, y: 400), center: center))
        #expect(!CameraTargetSelection.keepsRetainedTarget(at: nil, center: center))
    }
    @Test func oneFlickeringPixelDoesNotTakeOverTheSelectedSource() {
        #expect(
            !CameraTargetSelection.beginsNewSource(
                previousPoint: nil,
                newPoint: center, center: center, observations: 1))
        #expect(
            !CameraTargetSelection.beginsNewSource(
                previousPoint: nil,
                newPoint: CGPoint(x: 300, y: 400), center: center, observations: 8))
    }
    @Test func aStableFaintLightCanMatchItsCloserFaintCatalogStar() throws {
        func ray(_ angle: Float) -> SIMD3<Float> {
            let az = angle * .pi / 180
            let altitude = Float.pi / 6
            return SIMD3(sin(az) * cos(altitude), sin(altitude), -cos(az) * cos(altitude))
        }
        func star(_ id: Int, _ mag: Double) -> CatalogStar {
            CatalogStar(
                id: id, ra_deg: 0, dec_deg: 0, mag: mag, bv: nil, name: "Star \(id)", designation: nil,
                distance_ly: nil, con: nil, collectible_candidate: true)
        }
        let faint = star(1, 5.6)
        let bright = star(2, -0.62)
        let result = CameraCandidateMatcher.assess(
            direction: ray(120), isDisc: false, zoom: 1,
            headingAccuracy: 5, candidates: [(faint, ray(120.1)), (bright, ray(124))],
            hasOpticalEvidence: true)
        #expect(try #require(result.match).star.id == faint.id)
    }
}
