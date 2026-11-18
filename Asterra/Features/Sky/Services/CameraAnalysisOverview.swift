import Accelerate
import CoreVideo
import Foundation

/// Wide discovery uses a bounded image. Native-resolution center and pinned patches
/// still detect faint sources, so broad analysis cannot monopolize every scan pass.
nonisolated enum CameraAnalysisOverview {
    static func make(from image: CVPixelBuffer, maximumDimension: Int = 960) -> CVPixelBuffer? {
        guard CVPixelBufferIsPlanar(image), CVPixelBufferGetPlaneCount(image) > 0 else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(image, 0)
        let height = CVPixelBufferGetHeightOfPlane(image, 0)
        guard max(width, height) > maximumDimension else { return image }
        let scale = Double(maximumDimension) / Double(max(width, height))
        let targetWidth = max(32, Int(Double(width) * scale) / 2 * 2)
        let targetHeight = max(32, Int(Double(height) * scale) / 2 * 2)
        var output: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, targetWidth, targetHeight,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nil, &output) == kCVReturnSuccess,
            let output else { return nil }
        CVPixelBufferLockBaseAddress(image, .readOnly)
        CVPixelBufferLockBaseAddress(output, [])
        defer {
            CVPixelBufferUnlockBaseAddress(output, [])
            CVPixelBufferUnlockBaseAddress(image, .readOnly)
        }
        guard let source = CVPixelBufferGetBaseAddressOfPlane(image, 0),
              let destination = CVPixelBufferGetBaseAddressOfPlane(output, 0) else { return nil }
        var input = vImage_Buffer(data: source, height: vImagePixelCount(height), width: vImagePixelCount(width),
                                  rowBytes: CVPixelBufferGetBytesPerRowOfPlane(image, 0))
        var target = vImage_Buffer(data: destination, height: vImagePixelCount(targetHeight), width: vImagePixelCount(targetWidth),
                                   rowBytes: CVPixelBufferGetBytesPerRowOfPlane(output, 0))
        guard vImageScale_Planar8(&input, &target, nil, vImage_Flags(kvImageHighQualityResampling)) == kvImageNoError else { return nil }
        return output
    }
}
