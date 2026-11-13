import CoreVideo
import Foundation
import Testing
import simd
@testable import Asterra

@MainActor struct CameraStickyScanTests {
    private let center = CGPoint(x: 200, y: 400)
    private let heldRay = simd_normalize(SIMD3<Float>(0, 0.5, -0.866))
    private let otherRay = simd_normalize(SIMD3<Float>(0.2, 0.5, -0.84))
    private func track(_ id: Int, ray: SIMD3<Float>, hits: Int = 4, time: Double = 11) -> CameraOpticalTrack {
        CameraOpticalTrack(id: id, hits: hits, direction: ray, size: CGSize(width: 8, height: 8),
            time: time, firstSeen: 10)
    }

    @Test func scanningStartsAwayFromTheTinyReticleAndKeepsTheSameLightAfterItDrifts() throws {
        let first = track(1, ray: heldRay, hits: 1, time: 10)
        let acquired = try #require(CameraTrackingPolicy.select(fresh: [first], pinned: nil, now: 10,
            center: center, project: { _ in CGPoint(x: 270, y: 400) }))
        #expect(acquired.id == 1)
        let pin = CameraLightPin(direction: heldRay, time: 10, observations: 1, opticalID: 1)
        let moved = try #require(CameraTrackingPolicy.select(fresh: [track(1, ray: heldRay)], pinned: pin,
            now: 11, center: center, project: { _ in CGPoint(x: 330, y: 400) }))
        #expect(moved.id == 1, "Leaving the old 28-point circle must not restart scanning")
    }

    @Test func aLightNearTheCenterCannotStealThePinDuringHandShake() throws {
        let pin = CameraLightPin(direction: heldRay, time: 10, observations: 4, opticalID: 1)
        let selected = CameraTrackingPolicy.select(fresh: [track(2, ray: otherRay), track(1, ray: heldRay)],
            pinned: pin, now: 11, center: center,
            project: { $0.x < 0.1 ? CGPoint(x: 252, y: 400) : CGPoint(x: 245, y: 400) })
        #expect(try #require(selected).id == 1)
        let deliberate = CameraTrackingPolicy.select(fresh: [track(2, ray: otherRay), track(1, ray: heldRay)],
            pinned: pin, now: 11, center: center,
            project: { $0.x < 0.1 ? CGPoint(x: 390, y: 400) : self.center })
        #expect(try #require(deliberate).id == 2, "A deliberate aim at another stable source must still work")
    }

    @Test func flickerAndSlowerAnalysisKeepScanMemoryWithoutInventingFreshPhotoEvidence() {
        #expect(CameraTrackingPolicy.acceptsAnalysis(capturedAt: 10, now: 11))
        #expect(!CameraTrackingPolicy.acceptsAnalysis(capturedAt: 10, now: 13))
        #expect(!CameraTrackingPolicy.acceptsAnalysis(capturedAt: 11, now: 10))
        #expect(CameraTargetSelection.continuesSingleSource(previousPoint: center,
            point: CGPoint(x: 223, y: 400), gap: 0.7))
        var pin = CameraLightPin(direction: heldRay, time: 10, observations: 4, opticalID: 1, firstSeen: 9)
        let match = CameraCandidateMatch(star: AppPreviewData.star, separation: 0, score: 0)
        let assessment = CameraCandidateAssessment(match: match, issue: .stabilizing)
        pin.assess(assessment)
        pin.confirm(assessment, observedAt: 10, insideReticle: true)
        pin.confirm(assessment, observedAt: 10.2, insideReticle: true)
        #expect(CameraTrackingPolicy.keepsScan(lastSeen: pin.lastSeen, now: 12))
        #expect(pin.observedMatch(at: 12) == nil, "A remembered scan must not pretend to be a new photograph")
        #expect(!CameraTrackingPolicy.keepsScan(lastSeen: pin.lastSeen, now: 16))
    }

    private func image(width: Int, height: Int, background: UInt8 = 118) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nil, &buffer)
        let result = try #require(buffer)
        CVPixelBufferLockBaseAddress(result, [])
        let base = try #require(CVPixelBufferGetBaseAddressOfPlane(result, 0)).assumingMemoryBound(to: UInt8.self)
        let row = CVPixelBufferGetBytesPerRowOfPlane(result, 0)
        for y in 0..<height { for x in 0..<width { base[y * row + x] = background } }
        CVPixelBufferUnlockBaseAddress(result, [])
        return result
    }

    @Test func observedSoftLightProfileSurvivesEveryScanGridAlignment() throws {
        // Measured 17x17 luminance profile around the submitted visible light.
        // Only its compact core is reconstructed; screenshot reticle marks outside
        // that core are deliberately excluded because they are not camera pixels.
        let profile: [UInt8] = [
            117, 118, 118, 118, 119, 119, 118, 117, 117, 116, 116, 117, 118, 119, 120, 121, 121,
            117, 118, 118, 118, 119, 119, 119, 118, 119, 118, 118, 119, 120, 121, 121, 121, 121,
            118, 118, 118, 119, 119, 120, 122, 125, 127, 130, 127, 123, 122, 121, 121, 121, 120,
            118, 118, 120, 120, 120, 121, 129, 136, 143, 150, 142, 132, 126, 121, 120, 120, 120,
            117, 118, 120, 123, 125, 131, 143, 155, 164, 173, 160, 146, 135, 125, 121, 121, 120,
            114, 116, 119, 126, 141, 157, 174, 190, 193, 197, 185, 172, 154, 135, 126, 122, 120,
            112, 115, 120, 133, 158, 182, 201, 218, 218, 218, 207, 196, 173, 147, 133, 124, 120,
            116, 122, 131, 149, 181, 207, 216, 224, 224, 224, 219, 213, 190, 162, 142, 127, 120,
            120, 128, 142, 165, 202, 230, 230, 230, 230, 230, 230, 230, 206, 175, 151, 130, 120,
            120, 127, 139, 161, 197, 224, 227, 230, 230, 230, 230, 230, 204, 170, 145, 125, 117,
            120, 126, 137, 157, 192, 219, 225, 230, 230, 230, 230, 230, 201, 164, 140, 121, 114,
            118, 120, 126, 141, 167, 190, 205, 219, 219, 219, 214, 209, 181, 146, 128, 117, 114,
            115, 129, 126, 122, 139, 158, 184, 207, 207, 207, 196, 184, 158, 127, 115, 113, 114,
            130, 174, 174, 127, 124, 135, 154, 171, 172, 174, 166, 157, 140, 120, 114, 113, 115,
            175, 175, 175, 171, 118, 115, 120, 124, 128, 132, 130, 127, 123, 118, 116, 115, 116,
            176, 175, 171, 117, 110, 108, 107, 107, 111, 115, 115, 116, 116, 117, 117, 116, 116,
            176, 171, 118, 113, 110, 108, 108, 108, 110, 113, 114, 116, 116, 116, 116, 116, 116
        ]
        for shiftY in 0..<3 { for shiftX in 0..<3 {
            let buffer = try image(width: 128, height: 128)
            CVPixelBufferLockBaseAddress(buffer, [])
            let bytes = try #require(CVPixelBufferGetBaseAddressOfPlane(buffer, 0)).assumingMemoryBound(to: UInt8.self)
            let row = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            for y in 0..<17 { for x in 0..<17 where hypot(Double(x - 9), Double(y - 9)) <= 7 {
                bytes[(56 + shiftY + y) * row + 56 + shiftX + x] = profile[y * 17 + x]
            } }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            let detected = CameraStarDetector.detect(in: buffer, focusRegion: CGRect(x: 0, y: 0, width: 1, height: 1))
            #expect(detected.contains {
                hypot($0.point.x * 128 - Double(65 + shiftX), $0.point.y * 128 - Double(65 + shiftY)) < 3
            }, "The same light disappeared at pixel offset (\(shiftX), \(shiftY))")
        } }
    }

    @Test func wideDiscoveryIsBoundedAndPreservesNormalizedSourceCoordinates() throws {
        let buffer = try image(width: 1280, height: 720, background: 24)
        CVPixelBufferLockBaseAddress(buffer, [])
        let bytes = try #require(CVPixelBufferGetBaseAddressOfPlane(buffer, 0)).assumingMemoryBound(to: UInt8.self)
        let row = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        for y in 340..<380 { for x in 620..<660 {
            let radius = Double((x - 640) * (x - 640) + (y - 360) * (y - 360))
            bytes[y * row + x] = UInt8(24 + Int(150 * exp(-radius / 8)))
        } }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        let overview = try #require(CameraAnalysisOverview.make(from: buffer))
        #expect(CVPixelBufferGetWidth(overview) == 960 && CVPixelBufferGetHeight(overview) == 540)
        #expect(CameraStarDetector.detect(in: overview).contains {
            hypot($0.point.x - 0.5, $0.point.y - 0.5) < 0.005
        })
    }
}
