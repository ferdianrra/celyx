import Foundation
import Testing
import simd

@testable import Asterra

@MainActor
struct GardenFocusFlightTests {
    @Test func pickingAStarFromTheListFliesToItThenOpensItsSheet() async throws {
        let model = AppPreviewData.collectedModel
        let viewModel = GardenViewModel(model: model)
        viewModel.place()
        let entry = try #require(viewModel.placed.first { $0.object.isAboveHorizon } ?? viewModel.placed.first)
        let start = viewModel.camera.fieldOfView
        await viewModel.focus(on: entry.id)
        #expect(viewModel.selected?.id == entry.id)
        #expect(viewModel.camera.orientation == nil)
        #expect(viewModel.camera.fieldOfView <= 42)
        // The camera now faces the star (or the horizon below it).
        let direction = entry.object.direction
        let heading = atan2(direction.x, direction.y)
        let difference = abs(remainder(viewModel.camera.azimuth - heading, 2 * .pi))
        #expect(difference < 0.01)
        if entry.object.isAboveHorizon {
            #expect(simd_dot(viewModel.camera.forward, direction) > cos(7 * Double.pi / 180))
        }
        await viewModel.endFocus()
        #expect(abs(viewModel.camera.fieldOfView - start) < 0.001)
    }
}
