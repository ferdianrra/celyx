import CoreVideo
import Foundation
import Testing
import simd
@testable import Asterra

struct CameraSkyContextTests {
    @Test func compactLightInOpenSkyPassesButBuildingEdgesAndLampHalosDoNot() throws {
        for mode in 0..<4 {
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault,320,240,kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,nil,&buffer)
            let image = try #require(buffer)
            CVPixelBufferLockBaseAddress(image,[])
            let bytes = try #require(CVPixelBufferGetBaseAddressOfPlane(image,0)).assumingMemoryBound(to:UInt8.self)
            let row = CVPixelBufferGetBytesPerRowOfPlane(image,0)
            for y in 0..<240 { for x in 0..<320 {
                let distance = hypot(Double(x-160),Double(y-120))
                var value = 24.0 + (distance < 2 ? 100 : 0)
                if mode == 1 { value += ((x/5+y/5)%2 == 0 ? 40 : 0) }
                if mode == 2 { value += 90*exp(-distance*distance/300) }
                if mode == 3 {
                    var seed = UInt32(x+y*320) &* 747796405 &+ 2891336453
                    seed = (seed ^ (seed >> 16)) &* 2246822519
                    value += Double(Int(seed%25)-12)
                }
                bytes[y*row+x] = UInt8(clamping:Int(value))
            } }
            CVPixelBufferUnlockBaseAddress(image,[])
            #expect(CameraSkyContext.permits(CGPoint(x:0.5,y:0.5),in:image) == (mode == 0 || mode == 3))
        }
    }

    @Test func nearbySurfaceNeedsAClusterInTheObservedDirection() {
        let direction = SIMD3<Float>(0,0,-1)
        #expect(!CameraSkyContext.hasNearbySurface(direction:direction,origin:.zero,features:[SIMD3(0,0,-5)]))
        #expect(CameraSkyContext.hasNearbySurface(direction:direction,origin:.zero,
            features:[SIMD3(0,0,-5),SIMD3(0.01,0,-5),SIMD3(-0.01,0,-5)]))
        #expect(!CameraSkyContext.hasNearbySurface(direction:direction,origin:.zero,
            features:[SIMD3(0,0,-100),SIMD3(0,0,-150),SIMD3(0,0,-200)]))
    }

    @Test @MainActor func aResolvedLampCannotAcquireAnOrdinaryStarName() {
        let result = CameraCandidateMatcher.assess(direction:SIMD3(0,0.5,-sqrt(0.75)),isDisc:true,
            zoom:1,headingAccuracy:5,candidates:[(AppPreviewData.star,SIMD3(0,0.5,-sqrt(0.75)))])
        #expect(result.match == nil)
    }
}
