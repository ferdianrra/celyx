import CoreGraphics
import Foundation
import Testing
import simd
@testable import Asterra

@MainActor struct GardenCameraLifecycleTests {
    @Test(arguments: [0.0, 0.45, 1.2])
    func pausingGyroKeepsTheRenderedCameraAndStarPositions(roll: Double) throws {
        let suite = "asterra.camera-lifecycle.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let garden = GardenViewModel(model: HomeViewModel(defaults: defaults))
        let attitude = simd_quatd(angle: 2, axis: SIMD3(1, 0, 0))
            * simd_quatd(angle: roll, axis: SIMD3(0, 0, 1))
        garden.receiveAttitude(simd_double3x3(attitude), at: 1)
        garden.camera.zoom = 1.8
        let camera = garden.camera
        let directions = [camera.forward,
                          simd_normalize(camera.forward + camera.right * 0.15),
                          simd_normalize(camera.forward - camera.up * 0.1)]
        let size = CGSize(width: 402, height: 874)
        let before = directions.compactMap { camera.project($0, in: size) }

        // Opening Start Collecting pauses the garden before the system cover finishes animating.
        garden.stopGyro()
        garden.stopGyro() // onDisappear can also stop the same garden.

        #expect(!garden.gyroLive)
        #expect(garden.usesGyro)
        #expect(garden.camera == camera)
        let after = directions.compactMap { garden.camera.project($0, in: size) }
        #expect(before.count == directions.count && after.count == before.count)
        for (a, b) in zip(before, after) {
            #expect(hypot(a.x - b.x, a.y - b.y) < 1e-6)
        }
    }
}
