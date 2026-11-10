import CoreVideo
import Foundation
import SwiftUI
import Testing
import UIKit
import simd
@testable import celyx

@MainActor struct CameraDimTargetTests {
    private let center = CGPoint(x: 200, y: 400)
    private let aim = SIMD3<Float>(0, 0, -1)
    private let brightRay = simd_normalize(SIMD3<Float>(0.2, 0.5, -0.84))
    private let faintRay = simd_normalize(SIMD3<Float>(0, 0.5, -0.866))

    @Test func aFaintCentralSourceCanReplaceABrightSourceStillNearby() throws {
        let bright = CameraOpticalTrack(id: 1, hits: 30, direction: brightRay, size: CGSize(width: 14, height: 14), time: 11, firstSeen: 8)
        let faint = CameraOpticalTrack(id: 2, hits: 4, direction: faintRay, size: CGSize(width: 5, height: 5), time: 11, firstSeen: 10)
        let pin = CameraLightPin(direction: brightRay, time: 10, observations: 20, opticalID: 1, aimDirection: aim)
        // The bright source remains visible and inside the generous hold area.
        for brightOffset in [20.0, 80.0] {
            let selected = CameraTrackingPolicy.select(fresh: [bright, faint], pinned: pin, now: 11,
                center: center, currentAim: aim,
                project: { $0.x > 0.1 ? CGPoint(x: 200 + brightOffset, y: 400) : self.center })
            #expect(try #require(selected).id == 2)
        }
    }

    @Test func twoVisibleSourcesCannotShareTheBrightSourcesIdentityAtHighZoom() {
        let closeRay = simd_quatf(angle: 0.3 * .pi / 180, axis: SIMD3<Float>(0, 1, 0)).act(brightRay)
        let bright = CameraOpticalTrack(id: 1, hits: 30, direction: brightRay, size: CGSize(width: 14, height: 14), time: 11)
        let faint = CameraOpticalTrack(id: 2, hits: 4, direction: closeRay, size: CGSize(width: 5, height: 5), time: 11)
        let pin = CameraLightPin(direction: brightRay, time: 10, observations: 20, opticalID: 1, aimDirection: aim)
        #expect(!CameraTrackingPolicy.continuesPinnedSource(faint, pinned: pin, fresh: [bright, faint]))
        #expect(CameraTrackingPolicy.continuesPinnedSource(bright, pinned: pin, fresh: [bright, faint]))
    }

    @Test func smallAimChangesKeepTheLastTargetBeyondATimerButLargeTurnsReleaseIt() {
        let small = simd_quatf(angle: 8 * .pi / 180, axis: SIMD3<Float>(0, 1, 0)).act(aim)
        let large = simd_quatf(angle: 30 * .pi / 180, axis: SIMD3<Float>(0, 1, 0)).act(aim)
        #expect(CameraTrackingPolicy.keepsTarget(lastSeen: 10, now: 90, referenceAim: aim, currentAim: small))
        #expect(!CameraTrackingPolicy.keepsTarget(lastSeen: 10, now: 90, referenceAim: aim, currentAim: large))
        let pin = CameraLightPin(direction: faintRay, time: 10, observations: 4, opticalID: 2, aimDirection: aim)
        let transient = CameraOpticalTrack(id: 3, hits: 1, direction: brightRay, size: CGSize(width: 8, height: 8), time: 90)
        #expect(CameraTrackingPolicy.select(fresh: [transient], pinned: pin, now: 90, center: center,
            currentAim: small, project: { _ in self.center }) == nil,
            "A single new flash must not replace the remembered target")
    }

    @Test func averagingCanResolveTheFaintPointWhileAMuchBrighterNeighborIsVisible() throws {
        let intrinsics = simd_float3x3(columns: (SIMD3<Float>(280, 0, 0), SIMD3(0, 280, 0), SIMD3(160, 120, 1)))
        var stack = CameraPointStack()
        var sources: [CameraLightPoint] = []
        for frame in 0..<8 {
            var output: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 320, 240, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nil, &output)
            let image = try #require(output)
            CVPixelBufferLockBaseAddress(image, [])
            let bytes = try #require(CVPixelBufferGetBaseAddressOfPlane(image, 0)).assumingMemoryBound(to: UInt8.self)
            let row = CVPixelBufferGetBytesPerRowOfPlane(image, 0)
            for y in 0..<240 { for x in 0..<320 {
                let dimR = Double((x - 160) * (x - 160) + (y - 120) * (y - 120))
                let brightR = Double((x - 230) * (x - 230) + (y - 120) * (y - 120))
                let noise = Double((x * 17 + y * 13 + frame * 7) % 3 - 1)
                let signal = 6 * exp(-dimR / 1.62) + 150 * exp(-brightR / 3)
                bytes[y * row + x] = UInt8(clamping: Int((40 + noise + signal).rounded()))
            } }
            CVPixelBufferUnlockBaseAddress(image, [])
            sources = stack.detect(in: image, intrinsics: intrinsics, pose: matrix_identity_float4x4,
                time: Double(frame) * 0.2, region: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        }
        #expect(sources.contains { hypot($0.point.x * 320 - 160, $0.point.y * 240 - 120) < 3 })
        #expect(sources.contains { hypot($0.point.x * 320 - 230, $0.point.y * 240 - 120) < 3 })
    }

    @Test func scanMarkerRendersWithoutASecondScanningLabel() throws {
        let content = CameraPinnedLightOverlay(guide: .init(point: CGPoint(x: 150, y: 80), arrow: .zero, separation: 0),
            title: "Scanning…", isRecognizing: true, showsLabel: false)
            .frame(width: 300, height: 200).background(.black)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try #require(renderer.uiImage)
        try #require(image.pngData()).write(to: URL(fileURLWithPath: "/tmp/celyx-unlabeled-scan-marker.png"))
    }
}
