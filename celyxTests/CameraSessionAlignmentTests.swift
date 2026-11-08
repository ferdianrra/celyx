import Foundation
import Testing
import simd
@testable import celyx

@MainActor
struct CameraSessionAlignmentTests {
    private func ray(azimuth: Double,altitude: Double) -> SIMD3<Float> {
        let a = azimuth * .pi/180, h = altitude * .pi/180
        return SIMD3(Float(sin(a)*cos(h)),Float(sin(h)),Float(-cos(a)*cos(h)))
    }
    private func star(id: Int,mag: Double) -> CatalogStar {
        CatalogStar(id:id,ra_deg:0,dec_deg:0,mag:mag,bv:nil,name:"Candidate \(id)",designation:nil,
                    distance_ly:nil,con:nil,collectible_candidate:true)
    }

    @Test func oneKnownReferenceCorrectsOtherDirectionsInTheSameWorld() throws {
        let existing = 3 * Double.pi/180, total = 14 * Double.pi/180
        let trueReference = ray(azimuth:120,altitude:30)
        let worldError = simd_quatf(angle:Float(total),axis:SIMD3(0,1,0))
        let rotation = try #require(CalibrationReference.localRotation(expected:trueReference,
            observed:worldError.act(trueReference),existingOffset:existing))
        let previous = simd_quatf(angle:Float(existing),axis:SIMD3(0,1,0))
        for direction in [trueReference,ray(azimuth:180,altitude:50),ray(azimuth:240,altitude:15)] {
            #expect(simd_length(rotation.act(previous.act(direction))-worldError.act(direction)) < 0.00001)
            #expect(abs(rotation.act(previous.act(direction)).y-direction.y) < 0.00001)
        }
    }

    @Test func aWrongHeightCannotBecomeTheSingleStarReference() {
        #expect(CalibrationReference.localRotation(expected:ray(azimuth:120,altitude:30),
            observed:ray(azimuth:105,altitude:45),existingOffset:0) == nil)
    }

    @Test func calibratedMatchingNeverUsesTheOldWideCompassSearchRadius() {
        let observed = ray(azimuth:120,altitude:30)
        let distant = (star(id:1,mag:-1.44),ray(azimuth:126,altitude:30))
        let result = CameraCandidateMatcher.assess(direction:observed,isDisc:false,zoom:1,
            headingAccuracy:nil,candidates:[distant],isCalibrated:true)
        #expect(result.match == nil)
    }

    @Test func calibratedGeometryWinsOverABrighterButFurtherStar() throws {
        let observed = ray(azimuth:120,altitude:30)
        let nearby = (star(id:1,mag:3.12),ray(azimuth:120.1,altitude:30))
        let bright = (star(id:2,mag:-1.44),ray(azimuth:121.3,altitude:30))
        let result = CameraCandidateMatcher.assess(direction:observed,isDisc:false,zoom:1,
            headingAccuracy:nil,candidates:[bright,nearby],isCalibrated:true)
        #expect(try #require(result.match).star.id == nearby.0.id)
    }

    @Test func aCalibratedNearTieRemainsAmbiguous() {
        let observed = ray(azimuth:120,altitude:30)
        let a = (star(id:1,mag:1),ray(azimuth:119.9,altitude:30))
        let b = (star(id:2,mag:1),ray(azimuth:120.1,altitude:30))
        let result = CameraCandidateMatcher.assess(direction:observed,isDisc:false,zoom:1,
            headingAccuracy:nil,candidates:[a,b],isCalibrated:true)
        #expect(result.match == nil)
        #expect(result.issue == .ambiguous)
    }

    @Test func returningToTheReticleHasAnExitMarginWithoutWaitingForFreshPixels() {
        var gate = CameraReticleGate()
        gate.update(id:1,distance:27,enabled:true)
        #expect(gate.centeredID == 1)
        gate.update(id:1,distance:35,enabled:true)
        #expect(gate.centeredID == 1)
        gate.update(id:1,distance:41,enabled:true)
        #expect(gate.centeredID == nil)
        gate.update(id:1,distance:27,enabled:true)
        #expect(gate.centeredID == 1)
        gate.update(id:2,distance:35,enabled:true)
        #expect(gate.centeredID == nil)
        gate.update(id:2,distance:20,enabled:false)
        #expect(gate.centeredID == nil)
    }

    @Test func observedSiriusGeometrySeparatesCanopusFromStar164AcrossZoomLevels() throws {
        // Bundled J2000 coordinates, transformed to one shared horizon frame.
        func horizon(ra: Double,dec: Double) -> SIMD3<Float> {
            let h = (100-ra) * .pi/180, d = dec * .pi/180, p = -6.2 * Double.pi/180
            return SIMD3(Float(-cos(d)*sin(h)),Float(sin(p)*sin(d)+cos(p)*cos(d)*cos(h)),
                         Float(-(cos(p)*sin(d)-sin(p)*cos(d)*cos(h))))
        }
        let sirius = horizon(ra:101.2875,dec:-16.716)
        let canopus = horizon(ra:95.988,dec:-52.696)
        let unnamed = horizon(ra:102.4845,dec:-50.615)
        let error = simd_quatf(angle:12 * .pi/180,axis:SIMD3<Float>(0,1,0))
        let reference = CameraCandidateReference(observed:error.act(sirius),expected:sirius)
        let candidates = [(star(id:0,mag:-1.44),sirius),(star(id:1,mag:-0.62),canopus),
                          (star(id:164,mag:2.94),unnamed)]
        for zoom in [1.0,3,10] {
            let result = CameraCandidateMatcher.assess(direction:error.act(canopus),isDisc:false,zoom:zoom,
                headingAccuracy:10,candidates:candidates,reference:reference)
            #expect(try #require(result.match).star.id == 1)
            // Do not simply force the brightest star: a real observation of 164
            // must retain its own identity after the same geometric correction.
            let other = CameraCandidateMatcher.assess(direction:error.act(unnamed),isDisc:false,zoom:zoom,
                headingAccuracy:10,candidates:candidates,reference:reference)
            #expect(try #require(other.match).star.id == 164)
        }
    }

    @Test func compassUncertaintyDoesNotAllowAStarAtTheWrongAltitude() {
        let result = CameraCandidateMatcher.assess(direction:ray(azimuth:120,altitude:30),isDisc:false,
            zoom:1,headingAccuracy:20,candidates:[(star(id:1,mag:-1.44),ray(azimuth:120,altitude:36))])
        #expect(result.match == nil)
    }

    @Test func anInconsistentEstimatedReferenceCannotRotateTheCatalog() {
        let reference = CameraCandidateReference(observed:ray(azimuth:120,altitude:30),
            expected:ray(azimuth:120,altitude:40))
        #expect(reference.rotation == nil)
        let distant = CameraCandidateReference(observed:ray(azimuth:150,altitude:30),
            expected:ray(azimuth:120,altitude:30))
        #expect(distant.rotation == nil)
    }
}
