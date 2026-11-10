import CoreImage
import Testing
@testable import Asterra

@MainActor struct StarCaptureEnhancementTests {
    private let context = CIContext(options:[.useSoftwareRenderer:true])
    private let colorSpace = CGColorSpace(name:CGColorSpace.sRGB)!

    private func pixels(_ image: CIImage) -> [UInt8] {
        var result = [UInt8](repeating:0,count:32*32*4)
        result.withUnsafeMutableBytes {
            context.render(image,toBitmap:$0.baseAddress!,rowBytes:32*4,
                bounds:CGRect(x:0,y:0,width:32,height:32),format:.RGBA8,colorSpace:colorSpace)
        }
        return result
    }

    @Test func enhancementMakesAFaintRecordedPointBrighterWithoutMovingIt() {
        let extent = CGRect(x:0,y:0,width:32,height:32)
        let background = CIImage(color:CIColor(red:0.005,green:0.005,blue:0.005)).cropped(to:extent)
        let point = CIImage(color:CIColor(red:0.08,green:0.08,blue:0.08))
            .cropped(to:CGRect(x:15,y:15,width:2,height:2))
        let original = point.composited(over:background)
        let enhanced = StarCaptureEnhancement.process(original)
        let before = pixels(original), after = pixels(enhanced)
        let center = (15*32+15)*4
        #expect(enhanced.extent == original.extent)
        #expect(after[center] > before[center])
        let originalContrast = Int(before[center])-Int(before[0])
        let enhancedContrast = Int(after[center])-Int(after[0])
        #expect(enhancedContrast > originalContrast)
        #expect(after[(10*32+10)*4] == after[0])
    }

    @Test func anEmptyBlackImageDoesNotAcquireInventedStars() {
        let black = CIImage(color:.black).cropped(to:CGRect(x:0,y:0,width:32,height:32))
        let output = pixels(StarCaptureEnhancement.process(black))
        for index in stride(from:0,to:output.count,by:4) {
            #expect(output[index] == 0)
            #expect(output[index+1] == 0)
            #expect(output[index+2] == 0)
        }
    }
}
