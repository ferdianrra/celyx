import Testing
import Foundation
import simd
@testable import Asterra

struct SkyPatternMatcherTests {
    private func direction(_ azimuth: Double,_ altitude: Double) -> SIMD3<Float> {
        let a = azimuth * .pi/180, h = altitude * .pi/180
        return SIMD3(Float(sin(a)*cos(h)),Float(sin(h)),Float(-cos(a)*cos(h)))
    }
    private var stars: [CalibrationCatalogPoint] {
        [(4.0,20.0),(16,29),(31,43),(49,55)].enumerated().map {
            .init(id:$0.offset+1,direction:direction($0.element.0,$0.element.1),magnitude:Double($0.offset+1))
        }
    }
    private func observations(offset: Double = 12) -> [CalibrationObservation] {
        let rotation = simd_quatf(angle:Float(offset * .pi/180),axis:SIMD3(0,1,0))
        return stars.enumerated().map { .init(id:$0.offset,direction:rotation.act($0.element.direction)) }
    }
    @Test func fourPointGeometryRecoversTheCorrectionAndAnchorIdentity() throws {
        let fit = try #require(SkyPatternMatcher.solve(observations:observations(),catalogue:stars,anchorID:1))
        #expect(abs(fit.headingOffset*180 / .pi-12) < 0.05)
        #expect(fit.starIDs == [1,2,3,4])
        #expect(fit.anchorStarID == 2)
        #expect(fit.residualDegrees < 0.05)
    }
    @Test func brightnessCannotReplaceACloserGeometricMatch() throws {
        var catalogue = stars
        catalogue.append(.init(id:99,direction:direction(16.3,29),magnitude:-2))
        let fit = try #require(SkyPatternMatcher.solve(observations:observations(),catalogue:catalogue,anchorID:1))
        #expect(fit.anchorStarID == 2)
        #expect(!fit.starIDs.contains(99))
    }
    @Test func anUnresolvedNeighborAtTheAnchorIsNotGivenAnArbitraryName() {
        var catalogue = stars
        catalogue.append(.init(id:99,direction:direction(16.05,29),magnitude:-2))
        #expect(SkyPatternMatcher.solve(observations:observations(),catalogue:catalogue,anchorID:1) == nil)
    }
    @MainActor @Test func realBundledSkyCanSupplyAnUnlabeledPattern() throws {
        let model = HomeViewModel.preview()
        let sky = try #require(model.snapshot)
        let catalogue = model.stars.filter { $0.mag <= 5.5 }.map { star -> CalibrationCatalogPoint in
            let d = Refraction.apparent(sky.direction(ra:star.ra_deg,dec:star.dec_deg))
            return .init(id:star.id,direction:SIMD3(Float(d.x),Float(d.z),Float(-d.y)),magnitude:star.mag)
        }
        let visible = catalogue.filter { $0.direction.y > sin(15 * Float.pi/180) && $0.direction.y < sin(65 * Float.pi/180) }
            .sorted { $0.magnitude < $1.magnitude }
        // The camera cannot supply two independent rays for an unresolved catalog pair.
        // Choose isolated physical directions; the separate ambiguity test covers close neighbors.
        let isolated = visible.filter { star in
            !catalogue.contains { $0.id != star.id && simd_dot($0.direction,star.direction) > cos(0.3 * Float.pi/180) }
        }
        let center = try #require(isolated.first)
        let patch = isolated.filter { simd_dot($0.direction,center.direction) > cos(35 * Float.pi/180) }
        let sample = Array(patch.prefix(5))
        #expect(sample.count == 5)
        let rotation = simd_quatf(angle:Float(9 * Double.pi/180),axis:SIMD3(0,1,0))
        let seen = sample.enumerated().map { CalibrationObservation(id:$0.offset,direction:rotation.act($0.element.direction)) }
        let solved = SkyPatternMatcher.solve(observations:seen,catalogue:catalogue,anchorID:0)
        let fit = try #require(solved)
        #expect(fit.matches.count == 5)
        #expect(fit.anchorStarID == sample[0].id)
        #expect(abs(fit.headingOffset*180 / .pi-9) < 0.05)
    }
    @Test func aCompetingPatternIsRejectedRatherThanChoosingTheBrighterOne() {
        let rotated = simd_quatf(angle:Float(-20 * Double.pi/180),axis:SIMD3(0,1,0))
        let duplicate = stars.map { CalibrationCatalogPoint(id:$0.id+100,direction:rotated.act($0.direction),magnitude:-1) }
        #expect(SkyPatternMatcher.solve(observations:observations(),catalogue:stars+duplicate,anchorID:0) == nil)
    }
    @Test func unconfirmedThreeLightsOrAnUnmatchedCenterCannotAutoCalibrate() {
        #expect(SkyPatternMatcher.solve(observations:Array(observations().prefix(3)),catalogue:stars,anchorID:0) == nil)
        var seen = observations()
        seen.append(.init(id:99,direction:direction(100,65)))
        #expect(SkyPatternMatcher.solve(observations:seen,catalogue:stars,anchorID:99) == nil)
    }
    @Test func mirroredOrRepeatedDetectionsCannotCreateAValidPattern() {
        let mirrored = observations().map { CalibrationObservation(id:$0.id,direction:SIMD3(-$0.direction.x,$0.direction.y,$0.direction.z)) }
        #expect(SkyPatternMatcher.solve(observations:mirrored,catalogue:stars,anchorID:0) == nil)
        let repeated = (0..<4).map { CalibrationObservation(id:$0,direction:observations()[0].direction) }
        #expect(SkyPatternMatcher.solve(observations:repeated,catalogue:stars,anchorID:0) == nil)
    }
    @Test func aLocalSearchDoesNotPretendToSolveAnUnrelatedSkyPatch() {
        #expect(SkyPatternMatcher.solve(observations:observations(offset:80),catalogue:stars,anchorID:0) == nil)
    }
    @Test func calibrationRequiresIndependentFramesAndEnoughElapsedTime() throws {
        let fit = try #require(SkyPatternMatcher.solve(observations:observations(),catalogue:stars,anchorID:0))
        var consensus = SkyPatternConsensus()
        #expect(consensus.add(fit,at:0) == 0)
        for _ in 0..<10 { #expect(consensus.add(fit,at:0) == 0) }
        #expect(consensus.add(fit,at:0.3) < 1)
        #expect(consensus.add(fit,at:0.6) < 1)
        #expect(consensus.add(fit,at:0.9) < 1)
        #expect(consensus.add(fit,at:1.3) == 1)
    }
    @Test func aLostPatternResetsTheLoadingProgress() throws {
        let fit = try #require(SkyPatternMatcher.solve(observations:observations(),catalogue:stars,anchorID:0))
        var consensus = SkyPatternConsensus()
        _ = consensus.add(fit,at:0)
        _ = consensus.add(fit,at:0.4)
        _ = consensus.add(nil,at:1.5)
        #expect(consensus.add(fit,at:1.8) == 0)
    }
}
