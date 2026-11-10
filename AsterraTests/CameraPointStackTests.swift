import CoreVideo
import Foundation
import Testing
import simd
@testable import Asterra

struct CameraPointStackTests {
    private let intrinsics = simd_float3x3(SIMD3<Float>(280,0,0),SIMD3<Float>(0,280,0),SIMD3<Float>(160,120,1))
    private let region = CGRect(x:0.35,y:0.3,width:0.3,height:0.4)

    private func image(frame: Int,centerX: Double = 160,amplitude: Double = 6,
                       flash: Bool = false,hotPixel: Bool = false,glow: Bool = false,
                       noisy: Bool = true) throws -> CVPixelBuffer {
        var result: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,320,240,kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,nil,&result)
        #expect(status == kCVReturnSuccess)
        let buffer = try #require(result)
        CVPixelBufferLockBaseAddress(buffer,[])
        defer { CVPixelBufferUnlockBaseAddress(buffer,[]) }
        let bytes = try #require(CVPixelBufferGetBaseAddressOfPlane(buffer,0)).assumingMemoryBound(to:UInt8.self)
        let row = CVPixelBufferGetBytesPerRowOfPlane(buffer,0)
        for y in 0..<240 { for x in 0..<320 {
            var seed = UInt32(x+320*y) &* 747796405 &+ UInt32(frame+1) &* 2891336453
            seed = (seed ^ (seed >> 16)) &* 2246822519
            let noise = noisy ? Double(Int(seed%9)-4) : 0
            let dx = Double(x)-centerX, dy = Double(y)-120
            let sigma = glow ? 25.0 : 0.9
            let peak = flash ? (frame == 2 ? 100.0 : 0) : amplitude
            let signal = peak*exp(-(dx*dx+dy*dy)/(2*sigma*sigma))
            bytes[y*row+x] = hotPixel && x == 160 && y == 120 ? 255
                : UInt8(clamping:Int((30+noise+signal).rounded()))
        } }
        return buffer
    }

    @Test func compactDimSourceEmergesAfterIndependentFrames() throws {
        let single = CameraStarDetector.detect(in:try image(frame:0,noisy:false))
        #expect(!single.contains { hypot($0.point.x*320-160,$0.point.y*240-120) < 2 })
        var stack = CameraPointStack()
        var detections: [CameraLightPoint] = []
        for frame in 0..<8 {
            detections = stack.detect(in:try image(frame:frame),intrinsics:intrinsics,
                pose:matrix_identity_float4x4,time:Double(frame)*0.2,region:region)
            if frame < 5 { #expect(detections.isEmpty) }
        }
        #expect(stack.progress == 1)
        #expect(detections.contains { hypot($0.point.x*320-160,$0.point.y*240-120) < 2 })
    }

    @Test func compensatedRotationReturnsCurrentImageCoordinates() throws {
        var stack = CameraPointStack()
        var detections: [CameraLightPoint] = []
        var expectedX = 160.0
        for frame in 0..<8 {
            let angle = Double(frame)*0.15 * .pi/180
            expectedX = 160+280*tan(angle)
            let pose = simd_float4x4(simd_quatf(angle:Float(angle),axis:SIMD3(0,1,0)))
            detections = stack.detect(in:try image(frame:frame,centerX:expectedX,amplitude:9),
                intrinsics:intrinsics,pose:pose,time:Double(frame)*0.2,region:region)
        }
        #expect(detections.contains { hypot($0.point.x*320-expectedX,$0.point.y*240-120) < 2 })
    }

    @Test func noiseHotPixelsBroadGlowsAndOneFrameFlashesDoNotBecomeStars() throws {
        for mode in 0..<4 {
            var stack = CameraPointStack()
            var detections: [CameraLightPoint] = []
            for frame in 0..<8 {
                let buffer = try image(frame:frame,amplitude:mode == 2 ? 20 : 0,
                    flash:mode == 3,hotPixel:mode == 1,glow:mode == 2)
                detections += stack.detect(in:buffer,intrinsics:intrinsics,
                    pose:matrix_identity_float4x4,time:Double(frame)*0.2,region:region)
            }
            #expect(detections.isEmpty,"Unexpected sources for rejection mode \(mode): \(detections)")
        }
    }

    @Test func duplicateFramesGapsAndLargeMovementCannotKeepOldProgress() throws {
        var stack = CameraPointStack()
        let buffer = try image(frame:0)
        for frame in 0..<6 {
            _ = stack.detect(in:buffer,intrinsics:intrinsics,pose:matrix_identity_float4x4,time:Double(frame)*0.2,region:region)
        }
        #expect(stack.progress == 1)
        _ = stack.detect(in:buffer,intrinsics:intrinsics,pose:matrix_identity_float4x4,time:1,region:region)
        #expect(stack.progress == 1)
        _ = stack.detect(in:buffer,intrinsics:intrinsics,pose:matrix_identity_float4x4,time:2,region:region)
        #expect(abs(stack.progress-1.0/6) < 0.001)
        let turned = simd_float4x4(simd_quatf(angle:0.1,axis:SIMD3(0,1,0)))
        _ = stack.detect(in:buffer,intrinsics:intrinsics,pose:turned,time:2.2,region:region)
        #expect(abs(stack.progress-1.0/6) < 0.001)
    }

    @Test func stackingIsLimitedToNightAndAboveHorizon() {
        #expect(CameraPointStack.isEligible(sunAltitude:-20,aimAltitude:30))
        #expect(!CameraPointStack.isEligible(sunAltitude:10,aimAltitude:30))
        #expect(!CameraPointStack.isEligible(sunAltitude:-20,aimAltitude:-10))
        #expect(!CameraPointStack.isEligible(sunAltitude:.nan,aimAltitude:30))
    }

    @Test func aDisappearingSourceCannotCreateFreshEvidenceFromTheAverage() throws {
        var stack = CameraPointStack()
        for frame in 0..<6 {
            _ = stack.detect(in:try image(frame:frame,amplitude:12,noisy:false),intrinsics:intrinsics,
                pose:matrix_identity_float4x4,time:Double(frame)*0.2,region:region)
        }
        let missing = try image(frame:6,amplitude:0,noisy:false)
        let sources = stack.detect(in:missing,intrinsics:intrinsics,pose:matrix_identity_float4x4,time:1.2,region:region)
        #expect(sources.isEmpty)
    }
}
