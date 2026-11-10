import Foundation
import Testing
import simd
@testable import celyx

@MainActor
struct CalibrationCatalogTests {
    private func ray(azimuth: Double,altitude: Double) -> SIMD3<Float> {
        let a = azimuth * .pi/180, h = altitude * .pi/180
        return SIMD3(Float(sin(a)*cos(h)),Float(sin(h)),Float(-cos(a)*cos(h)))
    }
    @Test func aSingleConfirmedReferenceCanCalibrateWithoutOtherLights() throws {
        let offset = try #require(CalibrationReference.correction(expected:ray(azimuth:50,altitude:30),
                                                                observed:ray(azimuth:42,altitude:30)))
        #expect(abs(offset*180 / .pi-8) < 0.001)
    }
    @Test func aSingleReferenceStillNeedsValidGeometry() {
        #expect(CalibrationReference.correction(expected:ray(azimuth:50,altitude:30),
                                               observed:ray(azimuth:42,altitude:10)) == nil)
        #expect(CalibrationReference.correction(expected:SIMD3(0,0,0),observed:ray(azimuth:42,altitude:30)) == nil)
    }
    @Test func calibrationCatalogFiltersMagnitudeAndAltitude() {
        let filter = CalibrationCatalogFilter()
        #expect(filter.allows(magnitude:5.5,altitude:8))
        #expect(!filter.allows(magnitude:5.6,altitude:30))
        #expect(!filter.allows(magnitude:1,altitude:-5))
        #expect(!filter.allows(magnitude:1,altitude:83))
        #expect(!filter.allows(magnitude:.nan,altitude:30))
    }
    @Test func calibrationCatalogIsSeparateFromVisibleNowAndNeedsNoCameraDetection() {
        let home = AppPreviewData.model
        let originalVisible = home.predictedVisibleObjects.map(\.id)
        let originalFilters = home.visibilityFilters
        let engine = SkyPatternCalibrationService(catalogue:home.stars,alignment:home.cameraAlignment,preview:true)
        #expect(!engine.candidates.isEmpty)
        #expect(engine.lights.isEmpty)
        let initialCount = engine.candidates.count
        engine.filters.maximumMagnitude = 1
        #expect(engine.candidates.count < initialCount)
        #expect(engine.candidates.allSatisfy { $0.star.mag <= 1 })
        #expect(home.visibilityFilters == originalFilters)
        #expect(home.predictedVisibleObjects.map(\.id) == originalVisible)
    }
    @Test func removingASelectedCandidateWithAFilterClearsTheSelection() throws {
        let home = AppPreviewData.model
        let engine = SkyPatternCalibrationService(catalogue:home.stars,alignment:home.cameraAlignment,preview:true)
        let faint = try #require(engine.candidates.first(where:{ $0.star.mag > 2 }))
        engine.selectedCatalogID = faint.id
        engine.filters.maximumMagnitude = 1
        #expect(engine.selectedCatalogID == nil)
    }
}
