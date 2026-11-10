import CoreGraphics
import ImageIO
import CoreVideo
import Foundation
import Testing
import simd
@testable import celyx

private final class SolarDiscFixtureBundle: NSObject {}

@MainActor struct CameraSolarDiscTests {
    private let ray = simd_normalize(SIMD3<Float>(0, 0.6, -0.8))

    @Test(arguments: [false, true], [false, true])
    func userSunBesideCloudIsDetectedAtItsOpticalCenter(videoRange: Bool, rotated: Bool) throws {
        // Camera-only crop of the reported screenshot: no labels or reticle.
        let url = try #require(Bundle(for: SolarDiscFixtureBundle.self).url(forResource: "sun-beside-cloud", withExtension: "png"))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let cg = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let width = cg.width, height = cg.height
        var gray = [UInt8](repeating: 0, count: width * height)
        let context = try #require(CGContext(data: &gray, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let imageWidth = rotated ? height : width, imageHeight = rotated ? width : height
        var output: CVPixelBuffer?
        let format = videoRange ? kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange : kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        CVPixelBufferCreate(kCFAllocatorDefault, imageWidth, imageHeight, format, nil, &output)
        let image = try #require(output)
        CVPixelBufferLockBaseAddress(image, [])
        let bytes = try #require(CVPixelBufferGetBaseAddressOfPlane(image, 0)).assumingMemoryBound(to: UInt8.self)
        let row = CVPixelBufferGetBytesPerRowOfPlane(image, 0)
        for y in 0..<height { for x in 0..<width {
            let dx = rotated ? height - 1 - y : x, dy = rotated ? x : y
            let value = gray[y * width + x]
            bytes[dy * row + dx] = videoRange ? UInt8(16 + Int(value) * 219 / 255) : value
        } }
        CVPixelBufferUnlockBaseAddress(image, [])
        let expected = rotated ? CGPoint(x: height - 1 - 445, y: 484) : CGPoint(x: 484, y: 445)
        let sources = CameraStarDetector.detectDiscs(in: image, daylight: true)
        let disc = try #require(sources.first)
        #expect(hypot(disc.point.x * Double(imageWidth) - expected.x, disc.point.y * Double(imageHeight) - expected.y) < 25)
        #expect(CameraSkyContext.permits(disc.point, in: image, isDisc: true, sourceBounds: disc.bounds))
    }

    @Test(arguments: [false, true], [0, 1, 2])
    func smallSunThroughCloudPassesDetectionAndContext(videoRange: Bool, phase: Int) throws {
        // Camera-only crop of the reported screenshot: no labels or reticle.
        let url = try #require(Bundle(for: SolarDiscFixtureBundle.self).url(forResource: "sun-through-cloud", withExtension: "png"))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let cg = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let width = cg.width, height = cg.height
        var gray = [UInt8](repeating: 0, count: width * height)
        let context = try #require(CGContext(data: &gray, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Preserve the reported source's native pixels, within a camera-sized sky.
        // The tight crop excludes the app's reticle; its surrounding cloud stays.
        let imageWidth = 640, imageHeight = 480
        for transmission in [1.0, 0.85] { for phaseY in 0..<3 {
            let originX = 294 + phase, originY = 214 + phaseY
            var output: CVPixelBuffer?
            let format = videoRange ? kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange : kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            CVPixelBufferCreate(kCFAllocatorDefault, imageWidth, imageHeight, format, nil, &output)
            let image = try #require(output)
            CVPixelBufferLockBaseAddress(image, [])
            let bytes = try #require(CVPixelBufferGetBaseAddressOfPlane(image, 0)).assumingMemoryBound(to: UInt8.self)
            let row = CVPixelBufferGetBytesPerRowOfPlane(image, 0)
            for y in 0..<imageHeight { for x in 0..<imageWidth { let sky = Int(150 * transmission); bytes[y * row + x] = UInt8(videoRange ? 16 + sky * 219 / 255 : sky) } }
            for y in 0..<height { for x in 0..<width {
                let dx = originX + x, dy = originY + y
                let value = Int(Double(gray[y * width + x]) * transmission)
                bytes[dy * row + dx] = UInt8(videoRange ? 16 + value * 219 / 255 : value)
            } }
            CVPixelBufferUnlockBaseAddress(image, [])
            let expected = CGPoint(x: originX + 26, y: originY + 26)
            let sources = CameraStarDetector.detectDiscs(in: image, daylight: true)
            let disc = try #require(sources.first)
            #expect(hypot(disc.point.x * Double(imageWidth) - expected.x, disc.point.y * Double(imageHeight) - expected.y) < 5)
            #expect(CameraSkyContext.permits(disc.point, in: image, isDisc: true, sourceBounds: disc.bounds))
        } }
    }

    @Test func aSmallPartlyOccludedDiscStillSuppliesOpticalEvidence() throws {
        var output: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 640, 480, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nil, &output)
        let image = try #require(output)
        CVPixelBufferLockBaseAddress(image, [])
        let bytes = try #require(CVPixelBufferGetBaseAddressOfPlane(image, 0)).assumingMemoryBound(to: UInt8.self)
        let row = CVPixelBufferGetBytesPerRowOfPlane(image, 0)
        for y in 0..<480 { for x in 0..<640 {
            let dx = x - 320, dy = y - 240
            let disc = dx * dx + dy * dy <= 12 * 12
            bytes[y * row + x] = disc ? (dy < 0 ? 175 : 250) : 130
        } }
        CVPixelBufferUnlockBaseAddress(image, [])
        let disc = try #require(CameraStarDetector.detectDiscs(in: image, daylight: true).first)
        #expect(hypot(disc.point.x * 640 - 320, disc.point.y * 480 - 240) < 10)
    }

    @Test func flatCloudAndAnIsolatedHotPixelCannotSupplySolarDiscEvidence() throws {
        for hotPixel in [false, true] {
            var output: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 320, 240, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nil, &output)
            let image = try #require(output)
            CVPixelBufferLockBaseAddress(image, [])
            let bytes = try #require(CVPixelBufferGetBaseAddressOfPlane(image, 0)).assumingMemoryBound(to: UInt8.self)
            let row = CVPixelBufferGetBytesPerRowOfPlane(image, 0)
            for y in 0..<240 { for x in 0..<320 { bytes[y * row + x] = 205 } }
            if hotPixel { bytes[120 * row + 159] = 255 }
            CVPixelBufferUnlockBaseAddress(image, [])
            #expect(CameraStarDetector.detectDiscs(in: image, daylight: true).isEmpty)
        }
    }

    @Test func resolvedSunCoreWinsOverASmallCloudHighlightCloserToTheReticle() throws {
        let smallRay = simd_normalize(SIMD3<Float>(0.02, 0.6, -0.8))
        let sun = CameraOpticalTrack(id: 1, hits: 4, direction: ray, size: CGSize(width: 40, height: 40), time: 10, isDisc: true)
        let cloud = CameraOpticalTrack(id: 2, hits: 4, direction: smallRay, size: CGSize(width: 6, height: 6), time: 10, isDisc: true)
        let selected = CameraSolarDiscPolicy.preferredCore(from: [cloud, sun], center: CGPoint(x: 200, y: 400),
            project: { $0.x == 0 ? CGPoint(x: 200, y: 530) : CGPoint(x: 200, y: 401) })
        #expect(try #require(selected).id == sun.id, "Solar acquisition allows a 130pt offset and prioritizes the actual disc")
        #expect(CameraSolarDiscPolicy.preferredCore(from: [sun], center: .zero, project: { _ in CGPoint(x: 200, y: 530) }) == nil)
    }

    @Test func daylightCannotOfferAnOrdinaryStarEvenWhenItsCatalogDirectionMatches() {
        for altitude: Double? in [nil, .nan, 50, 0, -5, -6] {
            #expect(!CameraIdentityPolicy.permitsPointIdentification(sunAltitude: altitude))
        }
        #expect(CameraIdentityPolicy.permitsPointIdentification(sunAltitude: -6.1))
        #expect(CameraIdentityPolicy.permitsPointIdentification(sunAltitude: -30))
    }

    @Test func sunAndMoonBecomeCollectibleAfterIndependentDiscObservations() throws {
        for body in [CatalogStar.sun, .moon] {
            for aligned in [false, true] {
                var decision = CameraAutomaticIdentification()
                for time in [10.0, 10.25, 10.5] {
                    let result = CameraSolarDiscPolicy.assess(direction: ray, isDisc: true,
                        headingAccuracy: aligned ? nil : 8, hasReferenceAlignment: aligned,
                        candidates: [(body, ray), (AppPreviewData.star, ray)])
                    decision.update(candidate: result.match, sourceID: 1, observedAt: time)
                }
                #expect(try #require(decision.freshMatch(at: 10.6)).star.id == body.id)
                #expect(decision.canOfferCapturedPhoto(starID: body.id, sourceID: 1, at: 12))
            }
        }
    }

    @Test func flareWrongDirectionAndBelowHorizonCannotAcquireTheSun() {
        let wrong = simd_quatf(angle: 30 * .pi / 180, axis: SIMD3<Float>(0, 1, 0)).act(ray)
        let below = SIMD3<Float>(0, -0.6, -0.8)
        for (observed, expected, disc) in [(ray, ray, false), (wrong, ray, true), (ray, below, true)] {
            #expect(CameraSolarDiscPolicy.assess(direction: observed, isDisc: disc,
                headingAccuracy: 8, hasReferenceAlignment: false, candidates: [(.sun, expected)]).match == nil)
        }
        #expect(CameraSolarDiscPolicy.assess(direction: ray, isDisc: true,
            headingAccuracy: nil, hasReferenceAlignment: false, candidates: [(.sun, ray)]).match == nil)
        #expect(CameraSolarDiscPolicy.assess(direction: ray, isDisc: true,
            headingAccuracy: 8, hasReferenceAlignment: false, candidates: [(.sun, ray), (.moon, ray)]).match == nil)
    }

    @Test func brightDaytimeDiscSurvivesContextChecksButRectangularLightDoesNot() throws {
        for square in [false, true] {
            var output: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 640, 480, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nil, &output)
            let image = try #require(output)
            CVPixelBufferLockBaseAddress(image, [])
            let bytes = try #require(CVPixelBufferGetBaseAddressOfPlane(image, 0)).assumingMemoryBound(to: UInt8.self)
            let row = CVPixelBufferGetBytesPerRowOfPlane(image, 0)
            for y in 0..<480 { for x in 0..<640 {
                let dx = x - 320, dy = y - 240
                let shape = square ? abs(dx) <= 24 && abs(dy) <= 24 : dx * dx + dy * dy <= 24 * 24
                bytes[y * row + x] = shape ? 255 : 130
            } }
            CVPixelBufferUnlockBaseAddress(image, [])
            let sources = CameraStarDetector.detectDiscs(in: image)
            if square { #expect(sources.isEmpty) }
            else {
                let disc = try #require(sources.first)
                #expect(disc.isDisc)
                #expect(hypot(disc.point.x - 0.5, disc.point.y - 0.5) < 0.01)
                #expect(CameraSkyContext.permits(disc.point, in: image, isDisc: true, sourceBounds: disc.bounds))
                let match = CameraSolarDiscPolicy.assess(direction: ray, isDisc: disc.isDisc,
                    headingAccuracy: 8, hasReferenceAlignment: false, candidates: [(.sun, ray)])
                #expect(match.match?.star.id == CatalogStar.sun.id)
            }
        }
    }
}
