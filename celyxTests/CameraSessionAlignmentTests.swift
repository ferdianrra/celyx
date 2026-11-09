import Foundation
import Testing
import UIKit
import simd

@testable import celyx

@MainActor
struct CameraSessionAlignmentTests {
    private func ray(azimuth: Double, altitude: Double) -> SIMD3<Float> {
        let a = azimuth * .pi / 180
        let h = altitude * .pi / 180
        return SIMD3(Float(sin(a) * cos(h)), Float(sin(h)), Float(-cos(a) * cos(h)))
    }
    private func star(id: Int, mag: Double) -> CatalogStar {
        CatalogStar(
            id: id, ra_deg: 0, dec_deg: 0, mag: mag, bv: nil, name: "Candidate \(id)", designation: nil,
            distance_ly: nil, con: nil, collectible_candidate: true)
    }

    @Test func insufficientPatternOffersManualReferenceAfterBoundedSearch() {
        var progress = CameraAutomaticMappingProgress()
        progress.update(at: 10, lightCount: 1)
        #expect(progress.isSearching)
        progress.update(at: 18, lightCount: 1)
        #expect(!progress.isSearching)
        #expect(progress.message.contains("Confirm a star"))
        progress.update(at: 19, lightCount: 4)
        #expect(progress.message.contains("No clear star pattern"))
    }

    @Test func sparseEstimatesCanMatchOneOrTwoStarsFromCompassDirection() throws {
        let target = star(id: 1, mag: 0.45)
        let candidates = [
            (target, ray(azimuth: 120, altitude: 30)),
            (star(id: 2, mag: 2), ray(azimuth: 145, altitude: 50)),
        ]
        for count in [1, 2] {
            let result = CameraCandidateMatcher.assess(
                direction: ray(azimuth: 120.2, altitude: 30),
                isDisc: false, zoom: 1, headingAccuracy: 5, candidates: Array(candidates.prefix(count)))
            #expect(try #require(result.match).star.id == target.id)
        }
    }

    @Test func sparseEstimatesStillRejectEquallyPlausibleNames() {
        let result = CameraCandidateMatcher.assess(
            direction: ray(azimuth: 120, altitude: 30),
            isDisc: false, zoom: 1, headingAccuracy: 5,
            candidates: [
                (star(id: 1, mag: 1), ray(azimuth: 119.9, altitude: 30)),
                (star(id: 2, mag: 1), ray(azimuth: 120.1, altitude: 30)),
            ])
        #expect(result.match == nil)
        #expect(result.issue == .ambiguous)
    }

    @Test func trackingStartupDoesNotInvalidateAnAlignment() {
        var recovery = CameraTrackingRecovery()
        let needsAlignment1 = recovery.update(isNormal: false, time: 0)
        #expect(!needsAlignment1)
        let needsAlignment2 = recovery.update(isNormal: false, time: 10)
        #expect(!needsAlignment2)
    }

    @Test func briefMovementRecoversWithoutDiscardingTheSkyMap() {
        var recovery = CameraTrackingRecovery()
        for (normal, time, expected) in [
            (true, 0.0, false), (false, 0.1, false), (false, 1.0, false),
            (true, 1.1, false), (false, 2.0, false), (false, 4.0, true),
            (false, 5.0, false), (true, 5.1, false),
        ] {
            let needsReset = recovery.update(isNormal: normal, time: time)
            #expect(needsReset == expected)
        }
    }

    @Test func aFreshInstallCannotGuessNamesBeforeConfirmingAReference() {
        let name = "CameraSessionAlignmentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let alignment = CameraSkyAlignment(defaults: defaults, notifications: NotificationCenter())
        #expect(alignment.requiresCalibration)
        #expect(alignment.reference == nil)
    }

    @Test func pausingAfterCaptureClearsTheReferenceAndRotation() {
        let name = "CameraSessionAlignmentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let alignment = CameraSkyAlignment(defaults: defaults, notifications: NotificationCenter())
        alignment.save(
            rotation: simd_quatf(angle: 0.3, axis: SIMD3(0, 1, 0)), reference: "Rigel", date: Date())
        let generation = alignment.generation
        alignment.pause(reason: "Capture opened the album")
        #expect(alignment.requiresCalibration)
        #expect(alignment.reference == nil)
        #expect(alignment.date == nil)
        #expect(alignment.generation > generation)
        #expect(
            simd_length(alignment.correct(ray(azimuth: 90, altitude: 30)) - ray(azimuth: 90, altitude: 30))
                < 0.00001)
    }

    @Test func appSwitchInvalidatesTheMapEvenWithTheCameraScreenCovered() {
        let name = "CameraSessionAlignmentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let notifications = NotificationCenter()
        let alignment = CameraSkyAlignment(defaults: defaults, notifications: notifications)
        alignment.save(rotation: simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)), reference: "Rigel", date: Date())
        notifications.post(name: UIApplication.willResignActiveNotification, object: nil)
        #expect(alignment.requiresCalibration)
        #expect(alignment.reference == nil)
        let generation = alignment.generation
        notifications.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        #expect(alignment.requiresCalibration, "Returning to the app cannot verify a star identity")
        #expect(alignment.generation == generation)
    }

    @Test func anInterruptedSessionCannotReuseItsSkyCorrection() {
        let name = "CameraSessionAlignmentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let alignment = CameraSkyAlignment(defaults: defaults)
        alignment.save(
            rotation: simd_quatf(angle: 0.2, axis: SIMD3(0, 1, 0)), reference: "Achernar", date: Date())
        let generation = alignment.generation
        alignment.enterBackground()
        #expect(alignment.requiresCalibration)
        #expect(alignment.reference == nil)
        #expect(alignment.generation > generation)
        alignment.save(
            rotation: simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)), reference: "Achernar", date: Date())
        #expect(!alignment.requiresCalibration)
    }

    @Test func oneKnownReferenceCorrectsOtherDirectionsInTheSameWorld() throws {
        let existing = 3 * Double.pi / 180
        let total = 14 * Double.pi / 180
        let trueReference = ray(azimuth: 120, altitude: 30)
        let worldError = simd_quatf(angle: Float(total), axis: SIMD3(0, 1, 0))
        let rotation = try #require(
            CalibrationReference.localRotation(
                expected: trueReference,
                observed: worldError.act(trueReference), existingOffset: existing))
        let previous = simd_quatf(angle: Float(existing), axis: SIMD3(0, 1, 0))
        for direction in [trueReference, ray(azimuth: 180, altitude: 50), ray(azimuth: 240, altitude: 15)] {
            #expect(simd_length(rotation.act(previous.act(direction)) - worldError.act(direction)) < 0.00001)
            #expect(abs(rotation.act(previous.act(direction)).y - direction.y) < 0.00001)
        }
    }

    @Test func aWrongHeightCannotBecomeTheSingleStarReference() {
        #expect(
            CalibrationReference.localRotation(
                expected: ray(azimuth: 120, altitude: 30),
                observed: ray(azimuth: 105, altitude: 45), existingOffset: 0) == nil)
    }

    @Test func calibratedMatchingNeverUsesTheOldWideCompassSearchRadius() {
        let observed = ray(azimuth: 120, altitude: 30)
        let distant = (star(id: 1, mag: -1.44), ray(azimuth: 126, altitude: 30))
        let result = CameraCandidateMatcher.assess(
            direction: observed, isDisc: false, zoom: 1,
            headingAccuracy: nil, candidates: [distant], isCalibrated: true)
        #expect(result.match == nil)
    }

    @Test func calibratedGeometryWinsOverABrighterButFurtherStar() throws {
        let observed = ray(azimuth: 120, altitude: 30)
        let nearby = (star(id: 1, mag: 3.12), ray(azimuth: 120.1, altitude: 30))
        let bright = (star(id: 2, mag: -1.44), ray(azimuth: 121.3, altitude: 30))
        let result = CameraCandidateMatcher.assess(
            direction: observed, isDisc: false, zoom: 1,
            headingAccuracy: nil, candidates: [bright, nearby], isCalibrated: true)
        #expect(try #require(result.match).star.id == nearby.0.id)
    }

    @Test func aCalibratedNearTieRemainsAmbiguous() {
        let observed = ray(azimuth: 120, altitude: 30)
        let a = (star(id: 1, mag: 1), ray(azimuth: 119.9, altitude: 30))
        let b = (star(id: 2, mag: 1), ray(azimuth: 120.1, altitude: 30))
        let result = CameraCandidateMatcher.assess(
            direction: observed, isDisc: false, zoom: 1,
            headingAccuracy: nil, candidates: [a, b], isCalibrated: true)
        #expect(result.match == nil)
        #expect(result.issue == .ambiguous)
    }

    @Test func returningToTheReticleHasAnExitMarginWithoutWaitingForFreshPixels() {
        var gate = CameraReticleGate()
        gate.update(id: 1, distance: 27, enabled: true)
        #expect(gate.centeredID == 1)
        gate.update(id: 1, distance: 35, enabled: true)
        #expect(gate.centeredID == 1)
        gate.update(id: 1, distance: 41, enabled: true)
        #expect(gate.centeredID == nil)
        gate.update(id: 1, distance: 27, enabled: true)
        #expect(gate.centeredID == 1)
        gate.update(id: 2, distance: 35, enabled: true)
        #expect(gate.centeredID == nil)
        gate.update(id: 2, distance: 20, enabled: false)
        #expect(gate.centeredID == nil)
    }

    @Test func observedSiriusGeometrySeparatesCanopusFromStar164AcrossZoomLevels() throws {
        // Bundled J2000 coordinates, transformed to one shared horizon frame.
        func horizon(ra: Double, dec: Double) -> SIMD3<Float> {
            let h = (100 - ra) * .pi / 180
            let d = dec * .pi / 180
            let p = -6.2 * Double.pi / 180
            return SIMD3(
                Float(-cos(d) * sin(h)), Float(sin(p) * sin(d) + cos(p) * cos(d) * cos(h)),
                Float(-(cos(p) * sin(d) - sin(p) * cos(d) * cos(h))))
        }
        let sirius = horizon(ra: 101.2875, dec: -16.716)
        let canopus = horizon(ra: 95.988, dec: -52.696)
        let unnamed = horizon(ra: 102.4845, dec: -50.615)
        let error = simd_quatf(angle: 12 * .pi / 180, axis: SIMD3<Float>(0, 1, 0))
        let reference = CameraCandidateReference(observed: error.act(sirius), expected: sirius)
        let candidates = [
            (star(id: 0, mag: -1.44), sirius), (star(id: 1, mag: -0.62), canopus),
            (star(id: 164, mag: 2.94), unnamed),
        ]
        for zoom in [1.0, 3, 10] {
            let result = CameraCandidateMatcher.assess(
                direction: error.act(canopus), isDisc: false, zoom: zoom,
                headingAccuracy: 10, candidates: candidates, reference: reference)
            #expect(try #require(result.match).star.id == 1)
            // Do not simply force the brightest star: a real observation of 164
            // must retain its own identity after the same geometric correction.
            let other = CameraCandidateMatcher.assess(
                direction: error.act(unnamed), isDisc: false, zoom: zoom,
                headingAccuracy: 10, candidates: candidates, reference: reference)
            #expect(try #require(other.match).star.id == 164)
        }
    }

    @Test func compassUncertaintyDoesNotAllowAStarAtTheWrongAltitude() {
        let result = CameraCandidateMatcher.assess(
            direction: ray(azimuth: 120, altitude: 30), isDisc: false,
            zoom: 1, headingAccuracy: 20,
            candidates: [(star(id: 1, mag: -1.44), ray(azimuth: 120, altitude: 36))])
        #expect(result.match == nil)
    }

    @Test func anInconsistentEstimatedReferenceCannotRotateTheCatalog() {
        let reference = CameraCandidateReference(
            observed: ray(azimuth: 120, altitude: 30),
            expected: ray(azimuth: 120, altitude: 40))
        #expect(reference.rotation == nil)
        let distant = CameraCandidateReference(
            observed: ray(azimuth: 150, altitude: 30),
            expected: ray(azimuth: 120, altitude: 30))
        #expect(distant.rotation == nil)
    }
}
