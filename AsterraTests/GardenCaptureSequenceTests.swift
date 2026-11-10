import Testing
import Foundation
import simd
@testable import Asterra

@MainActor
struct GardenCaptureSequenceTests {
    private func transition(itemID: Int? = 42) -> WormholeHandover {
        let freeze = WormholeFreeze.placeholder(size: CGSize(width: 402, height: 874))
        return WormholeHandover(freeze: freeze, star: CGPoint(x: 201, y: 437), itemID: itemID,
            scene: WormholeScene(objects: [], newID: nil, moon: nil, equatorial: nil))
    }

    @Test func revealsThenReturnsToGyroBeforeRequestingTheAlbum() async {
        let handover = transition()
        var phases: [WormholeHandover.Phase] = []
        await handover.run { _ in
            phases.append(handover.phase)
            #expect(!handover.showsSheet)
        }
        #expect(phases == [.wormhole, .landed, .reframe, .focusing, .revealing, .releasing, .presenting])
        #expect(handover.phase == .presenting && handover.showsSheet)
        handover.finish()
        #expect(handover.phase == .done && !handover.showsSheet)
    }

    @Test func reduceMotionRevealsWithoutCameraFlightBeforeTheAlbum() async {
        let handover = transition()
        var phases: [WormholeHandover.Phase] = []
        await handover.run(reduceMotion: true) { _ in
            phases.append(handover.phase)
            #expect(handover.revealIsVisible && !handover.showsSheet)
        }
        #expect(phases == [.revealing])
        #expect(handover.showsSheet)
    }

    @Test func interruptedSequenceCannotPresentAnAlbum() async {
        let handover = transition()
        await handover.run { _ in throw CancellationError() }
        #expect(handover.phase == .done && !handover.showsSheet)
        let replay = transition(itemID: nil)
        await replay.run { _ in }
        #expect(replay.phase == .done && !replay.showsSheet)
    }

    @Test func focusFitsNeighborsAndReturnsToTheLatestLivePose() throws {
        let handover = transition()
        let a = simd_normalize(SIMD3<Double>(-0.2, 1, 0.5))
        let b = simd_normalize(SIMD3<Double>(0.2, 1, 0.5))
        handover.configureFocus(directions: [a, b])
        let focused = handover.camera(handover.revealAt)
        let size = handover.freeze.size
        for point in [a, b] {
            let projected = try #require(focused.project(point, in: size))
            #expect(projected.x > size.width * 0.1 && projected.x < size.width * 0.9)
            #expect(projected.y > size.height * 0.1 && projected.y < size.height * 0.9)
        }
        let middle = try #require(focused.project(simd_normalize(a + b), in: size))
        #expect(abs(middle.x - size.width / 2) < 0.01)
        #expect(abs(middle.y - size.height / 2) < 0.01)
        // Return endpoints are live, not the phone pose recorded at capture time.
        var target = NightSeaCamera(); target.azimuth = 0.2; target.altitude = 0.4
        handover.target = target; handover.beginRelease()
        target.azimuth = 1.4; target.zoom = 2
        handover.target = target
        let returned = handover.camera(handover.returnAt + WormholeHandover.returnDuration + 10000)
        #expect(simd_distance(returned.forward, target.forward) < 1e-6)
        #expect(abs(returned.focalLength(in: size) - target.focalLength(in: size)) < 1e-6)
    }
}
