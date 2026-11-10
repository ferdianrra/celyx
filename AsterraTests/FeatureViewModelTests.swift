import Foundation
import CoreGraphics
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

    private func attitude(altitude: Double, yaw: Double = 0) -> simd_double3x3 {
        simd_double3x3(
            simd_quatd(angle: yaw, axis: SIMD3(0, 0, 1))
            * simd_quatd(angle: (90 + altitude) * .pi / 180, axis: SIMD3(1, 0, 0)))
    }

    @Test func swipingSwitchesToTouchAndSensorUpdatesCannotMoveTheView() {
        let viewModel = GardenViewModel(model: AppPreviewData.model)
        viewModel.receiveAttitude(attitude(altitude: 10), at: 0)
        let direction = viewModel.camera.forward
        let size = CGSize(width: 402, height: 874)
        let focal = viewModel.camera.focalLength(in: size)
        viewModel.drag(.zero, in: CGSize(width: 402, height: 874))
        #expect(!viewModel.usesGyro)
        #expect(viewModel.camera.orientation == nil)
        #expect(simd_distance(direction, viewModel.camera.forward) < 0.000001)
        #expect(abs(viewModel.camera.focalLength(in: size) - focal) < 0.000001)
        viewModel.drag(CGSize(width: 80, height: 30), in: CGSize(width: 402, height: 874))
        let dragged = viewModel.camera.forward
        viewModel.receiveAttitude(attitude(altitude: 40, yaw: 1), at: 1)
        #expect(simd_distance(dragged, viewModel.camera.forward) < 0.000001)
        viewModel.dragStart = nil
        viewModel.receiveAttitude(attitude(altitude: 40, yaw: 1), at: 2)
        viewModel.receiveAttitude(attitude(altitude: 40, yaw: 1), at: 3)
        #expect(!viewModel.usesGyro)
        #expect(simd_distance(dragged, viewModel.camera.forward) < 0.000001)
    }

    @Test func loweringThenRaisingReactivatesGyroAfterABriefStableThreshold() {
        let viewModel = GardenViewModel(model: AppPreviewData.model)
        viewModel.setGyroMode(false)
        viewModel.receiveAttitude(attitude(altitude: -35), at: 0)
        viewModel.receiveAttitude(attitude(altitude: -5), at: 1)
        viewModel.receiveAttitude(attitude(altitude: -5), at: 1.1)
        #expect(!viewModel.usesGyro)
        viewModel.receiveAttitude(attitude(altitude: -12), at: 1.3)
        viewModel.receiveAttitude(attitude(altitude: 15), at: 2)
        #expect(!viewModel.usesGyro)
        viewModel.receiveAttitude(attitude(altitude: 15), at: 2.4)
        #expect(viewModel.usesGyro && viewModel.gyroLive)
        #expect(viewModel.camera.orientation != nil)
        #expect(abs(asin(viewModel.camera.forward.z) * 180 / .pi - 15) < 0.000001)
    }

    @Test func raisingDuringADragCannotStealTouchControl() {
        let viewModel = GardenViewModel(model: AppPreviewData.model)
        viewModel.receiveAttitude(attitude(altitude: -35), at: 0)
        viewModel.drag(CGSize(width: 50, height: 0), in: CGSize(width: 402, height: 874))
        viewModel.receiveAttitude(attitude(altitude: 10), at: 1)
        viewModel.receiveAttitude(attitude(altitude: 10), at: 2)
        #expect(!viewModel.usesGyro)
        viewModel.dragStart = nil
        viewModel.receiveAttitude(attitude(altitude: 10), at: 3)
        #expect(!viewModel.usesGyro)
        viewModel.receiveAttitude(attitude(altitude: 10), at: 3.4)
        #expect(!viewModel.usesGyro)
        viewModel.receiveAttitude(attitude(altitude: 20), at: 4)
        viewModel.receiveAttitude(attitude(altitude: 20), at: 4.2)
        #expect(viewModel.usesGyro)
    }

    @Test func movingThePhoneNearTheHorizonRestoresGyroWithoutLoweringIt() {
        let viewModel = GardenViewModel(model: AppPreviewData.model)
        viewModel.receiveAttitude(attitude(altitude: -5), at: 0)
        viewModel.drag(CGSize(width: 80, height: 0), in: CGSize(width: 402, height: 874))
        viewModel.dragStart = nil
        viewModel.receiveAttitude(attitude(altitude: -5, yaw: 0.15), at: 1)
        #expect(!viewModel.usesGyro)
        viewModel.receiveAttitude(attitude(altitude: -5, yaw: 0.15), at: 1.2)
        #expect(viewModel.usesGyro && viewModel.gyroLive)
        #expect(viewModel.camera.orientation != nil)
    }

    @Test func smallHandMovementsKeepTouchModeActive() {
        let viewModel = GardenViewModel(model: AppPreviewData.model)
        viewModel.receiveAttitude(attitude(altitude: 20), at: 0)
        viewModel.setGyroMode(false)
        for index in 1...30 {
            viewModel.receiveAttitude(attitude(altitude: 21, yaw: index.isMultiple(of: 2) ? 0.02 : -0.02), at: Double(index))
        }
        #expect(!viewModel.usesGyro)
        #expect(viewModel.camera.orientation == nil)
    }

    @Test func movingBelowTheHorizonDoesNotRestoreGyro() {
        let viewModel = GardenViewModel(model: AppPreviewData.model)
        viewModel.receiveAttitude(attitude(altitude: -30), at: 0)
        viewModel.setGyroMode(false)
        viewModel.receiveAttitude(attitude(altitude: -25, yaw: 0.5), at: 1)
        viewModel.receiveAttitude(attitude(altitude: -25, yaw: 0.5), at: 2)
        #expect(!viewModel.usesGyro)
    }

    @Test func pinchingResetsTheAutomaticGyroMovementReference() {
        let viewModel = GardenViewModel(model: AppPreviewData.model)
        viewModel.receiveAttitude(attitude(altitude: 20), at: 0)
        viewModel.setGyroMode(false)
        viewModel.zoomStart = 1
        viewModel.receiveAttitude(attitude(altitude: 40), at: 1)
        viewModel.zoomStart = nil
        viewModel.receiveAttitude(attitude(altitude: 40), at: 2)
        viewModel.receiveAttitude(attitude(altitude: 40), at: 3)
        #expect(!viewModel.usesGyro)
        viewModel.receiveAttitude(attitude(altitude: 50), at: 4)
        viewModel.receiveAttitude(attitude(altitude: 50), at: 4.2)
        #expect(viewModel.usesGyro)
    }

    @Test func manuallySelectingGyroReturnsToThePhoneDirection() {
        let viewModel = GardenViewModel(model: AppPreviewData.model)
        viewModel.setGyroMode(false)
        viewModel.drag(CGSize(width: 100, height: 20), in: CGSize(width: 402, height: 874))
        viewModel.dragStart = nil
        viewModel.setGyroMode(true)
        viewModel.receiveAttitude(attitude(altitude: 25), at: 0)
        #expect(viewModel.usesGyro && viewModel.gyroLive)
        #expect(abs(asin(viewModel.camera.forward.z) * 180 / .pi - 25) < 0.000001)
    }

    @Test func touchCanExploreBelowTheHorizon() {
        let viewModel = GardenViewModel(model: AppPreviewData.model)
        viewModel.drag(CGSize(width: 0, height: -1000), in: CGSize(width: 402, height: 874))
        #expect(viewModel.camera.altitude < -80 * .pi / 180)
        #expect(!viewModel.usesGyro)
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
