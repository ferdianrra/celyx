import Foundation
import Testing
import simd

@testable import celyx

@MainActor
struct FeatureViewModelTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.firstWeekday = 2
        return value
    }

    @Test func calendarFiltersUseTheSameRulesInListAndMonthViews() throws {
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 8)))
        let viewModel = SkyCalendarViewModel(calendar: calendar, now: { date })
        viewModel.filters = [.moon]
        #expect(!viewModel.upcoming.isEmpty)
        #expect(viewModel.upcoming.allSatisfy { $0.kind == .moon })
        let event = try #require(viewModel.upcoming.first)
        let day = calendar.startOfDay(for: event.start)
        #expect(viewModel.events(on: day).contains { $0.id == event.id })
        #expect(viewModel.events(on: day).allSatisfy { $0.kind == .moon })
    }

    @Test func calendarMonthNavigationPreservesACompleteOrderedGrid() throws {
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 8)))
        let viewModel = SkyCalendarViewModel(calendar: calendar, now: { date })
        viewModel.moveMonth(by: 1)
        #expect(calendar.component(.month, from: viewModel.month) == 12)
        let weeks = viewModel.weeksInMonth
        #expect(weeks.allSatisfy { $0.count == 7 })
        let days = weeks.flatMap { $0 }.compactMap { $0 }
        #expect(days.count == 31)
        #expect(Set(days).count == 31)
        #expect(days == days.sorted())
        #expect(days.allSatisfy { calendar.component(.month, from: $0) == 12 })
        viewModel.moveMonth(by: -1)
        #expect(calendar.component(.month, from: viewModel.month) == 11)
    }

    @Test func switchingGardenToTouchPreservesTheCurrentViewingDirection() {
        var camera = NightSeaCamera()
        camera.orientation =
            simd_quatd(angle: 0.4, axis: SIMD3(0, 0, 1))
            * simd_quatd(angle: 1.1, axis: SIMD3(1, 0, 0))
        let viewModel = GardenViewModel(model: AppPreviewData.model, camera: camera)
        let direction = viewModel.camera.forward
        viewModel.stopGyro()
        #expect(viewModel.camera.orientation == nil)
        #expect(simd_distance(direction, viewModel.camera.forward) < 0.000001)
    }

    @Test func choosingAKnownReferenceLeavesPatternModeWithoutSavingAnIdentity() {
        let viewModel = SkyCalibrationViewModel(catalogue: [], preview: .pattern)
        let candidate = CalibrationCandidate(star: AppPreviewData.star, direction: SIMD3(0, 0.5, -0.8660254))
        viewModel.chooseCandidate(candidate)
        #expect(viewModel.mode == .reference)
        #expect(viewModel.selectedID == candidate.id)
        #expect(viewModel.selectedFromCatalog)
        #expect(!viewModel.saved)
        #expect(!viewModel.engine.patternEnabled)
    }

    @Test func movedRenderingAndFeedbackResourcesRemainBundled() {
        #expect(Bundle.main.url(forResource: "NightSeaShader", withExtension: "txt") != nil)
        for sound in CrosshairSound.allCases {
            #expect(Bundle.main.url(forResource: "crosshair_\(sound.rawValue)", withExtension: "wav") != nil)
        }
    }
}
