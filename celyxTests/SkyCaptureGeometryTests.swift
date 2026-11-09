import CoreVideo
import Foundation
import Testing
import simd
@testable import celyx

struct SkyCaptureGeometryTests {
    private let intrinsics = simd_float3x3(columns: (
        SIMD3<Float>(1300, 0, 0), SIMD3(0, 1290, 0), SIMD3(951, 537, 1)))

    @Test func projectedRaysAgreeWithPixelDisplayTransformForEveryOrientationAndZoom() throws {
        let pose = simd_float4x4(simd_quatf(angle: 0.7, axis: simd_normalize(SIMD3<Float>(1, 2, 3))))
        let camera = SkyCaptureCamera(transform: pose, intrinsics: intrinsics,
                                      imageResolution: CGSize(width: 1920, height: 1080), trackingState: .normal)
        for angle: CGFloat in [0, 90, 180, 270] {
            let viewport = (angle == 90 || angle == 270)
                ? CGSize(width: 400, height: 800) : CGSize(width: 800, height: 400)
            for zoom in [1.0, 2.0, 5.0] {
                let projection = CameraZoom.projection(camera.projectionMatrix(viewRotationAngle: angle,
                    viewportSize: viewport, zNear: 0.01, zFar: 2000), zoom: zoom)
                let view = camera.viewMatrix(viewRotationAngle: angle)
                let display = SkyCaptureCamera.imageTransform(angle: angle, imageSize: camera.imageResolution,
                    viewport: viewport).concatenating(CameraZoom.normalizedTransform(zoom))
                for pixel in [CGPoint(x: 960, y: 540), CGPoint(x: 970, y: 550), CGPoint(x: 940, y: 530)] {
                    let sensor = SIMD4<Float>((Float(pixel.x) - intrinsics[2, 0]) / intrinsics[0, 0],
                        -(Float(pixel.y) - intrinsics[2, 1]) / intrinsics[1, 1], -1, 0)
                    let world = pose * sensor
                    let result = SkyFinderProjection.project(direction: SIMD3(world.x, world.y, world.z),
                        view: view, projection: projection, size: viewport)
                    let actual = try #require(result.point)
                    let expected = CGPoint(x: pixel.x / 1920, y: pixel.y / 1080).applying(display)
                    #expect(abs(actual.x - expected.x * viewport.width) < 0.002)
                    #expect(abs(actual.y - expected.y * viewport.height) < 0.002)
                }
            }
        }
    }

    @Test func portraitNorthAndEastHaveCorrectHorizonAndScreenAxes() {
        // A portrait phone looking north: screen-right=east, screen-up=up, back=south.
        let basis = simd_float3x3(columns: (SIMD3<Float>(0, -1, 0), SIMD3(0, 0, 1), SIMD3(-1, 0, 0)))
        let portraitViewRotation = simd_float4x4(simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1)))
        for heading: Float in [0, .pi / 2, .pi, -.pi / 2] {
            let deviceToReference = simd_quatf(angle: -heading, axis: SIMD3(0, 0, 1)) * simd_quatf(basis)
            let pose = SkyCaptureCamera.sensorPose(deviceToReference: deviceToReference)
            let view = portraitViewRotation * simd_inverse(pose)
            let forward = SIMD4<Float>(sin(heading), 0, -cos(heading), 0)
            let up = SIMD4<Float>(0, 1, 0, 0)
            let right = SIMD4<Float>(cos(heading), 0, sin(heading), 0)
            #expect(simd_length(view * forward - SIMD4(0, 0, -1, 0)) < 1e-5)
            #expect(simd_length(view * up - SIMD4(0, 1, 0, 0)) < 1e-5)
            #expect(simd_length(view * right - SIMD4(1, 0, 0, 0)) < 1e-5)
        }
    }

    @Test func aspectFillTransformRoundTripsImageCoordinates() {
        for angle: CGFloat in [0, 90, 180, 270] {
            let transform = SkyCaptureCamera.imageTransform(angle: angle,
                imageSize: CGSize(width: 1920, height: 1080), viewport: CGSize(width: 393, height: 852))
            let point = CGPoint(x: 0.42, y: 0.57)
            let roundTrip = point.applying(transform).applying(transform.inverted())
            #expect(abs(roundTrip.x - point.x) < 1e-8 && abs(roundTrip.y - point.y) < 1e-8)
        }
    }

    @MainActor @Test func aCompassCoincidenceCannotNameAnIsolatedLamp() {
        let ray = SIMD3<Float>(0, 0.5, -sqrt(0.75))
        let star = AppPreviewData.star
        let unverified = CameraIdentityPolicy.assess(direction: ray, isDisc: false, zoom: 1,
            hasReferenceAlignment: false, candidates: [(star, ray)], hasOpticalEvidence: true)
        #expect(unverified.match == nil && unverified.issue == .alignment)
        let distant = simd_quatf(angle: Float.pi / 180, axis: SIMD3(0, 1, 0)).act(ray)
        let misaligned = CameraIdentityPolicy.assess(direction: distant, isDisc: false, zoom: 1,
            hasReferenceAlignment: true, candidates: [(star, ray)], hasOpticalEvidence: true)
        #expect(misaligned.match == nil)
        let resolvedLamp = CameraIdentityPolicy.assess(direction: ray, isDisc: true, zoom: 1,
            hasReferenceAlignment: true, candidates: [(star, ray)], hasOpticalEvidence: true)
        #expect(resolvedLamp.match == nil)
    }

    @Test func flashesAndDuplicateTimestampsCannotEstablishPersistence() {
        #expect(!CameraIdentityPolicy.hasPersistentEvidence(hits: 10, firstSeen: 1, lastSeen: 1))
        #expect(!CameraIdentityPolicy.hasPersistentEvidence(hits: 3, firstSeen: 1, lastSeen: 2))
        #expect(!CameraIdentityPolicy.hasPersistentEvidence(hits: 4, firstSeen: .nan, lastSeen: 2))
        #expect(!CameraIdentityPolicy.hasPersistentEvidence(hits: 4, firstSeen: 2, lastSeen: 1))
        #expect(CameraIdentityPolicy.hasPersistentEvidence(hits: 5, firstSeen: 1, lastSeen: 1.8))
    }
}
