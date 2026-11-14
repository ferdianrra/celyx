import CoreGraphics
import Foundation
import Testing
@testable import Asterra

@MainActor struct OnboardingFlowTests {
    private func visibilityFlow() -> OnboardingFlow {
        let flow = OnboardingFlow()
        flow.jump(to: "camera")
        flow.liveCameraReady(NightSeaCamera())
        #expect(flow.star == nil)
        #expect(flow.startCollectingPressed())
        #expect(flow.step == .visibility)
        return flow
    }

    @Test func solarAltitudeChoosesThePromptAndClockIsOnlyAFallback() {
        let flow = OnboardingFlow()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let noon = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 12))!
        flow.updateSky(sunAltitude: -30, date: noon, calendar: calendar)
        #expect(!flow.isDaytime)
        flow.updateSky(sunAltitude: 20, date: noon, calendar: calendar)
        #expect(flow.isDaytime)
        flow.updateSky(sunAltitude: nil, date: noon, calendar: calendar)
        #expect(flow.isDaytime)
        flow.updateSky(sunAltitude: .nan, date: noon.addingTimeInterval(12 * 3600), calendar: calendar)
        #expect(!flow.isDaytime)
    }

    @Test func visibleObjectOpensRealCameraWithoutCreatingAVirtualStar() {
        let flow = visibilityFlow()
        var opened = false
        flow.actions.findRealObject = { opened = true }
        flow.answerVisibility(canSeeObject: true)
        #expect(opened)
        #expect(flow.isFindingRealObject)
        #expect(flow.star == nil)
        flow.realObjectCollected()
        #expect(flow.step == .wormhole)
        flow.wormholeEnded()
        #expect(flow.step == .done)
    }

    @Test func completingNoteEndsTheTourOnceWithoutMenuSteps() {
        let flow = visibilityFlow()
        var finishes = 0
        flow.actions.finish = { finishes += 1 }
        flow.answerVisibility(canSeeObject: true)
        flow.realObjectCollected()
        flow.noteCompleted()
        #expect(flow.step == .done)
        #expect(flow.card == nil && flow.pointer == nil)
        #expect(OnboardingFlow.Step.counted.count == 3)
        flow.noteCompleted()
        flow.wormholeEnded()
        #expect(finishes == 1)
    }

    @Test func invisibleObjectAndFailedSearchOfferVirtualPractice() {
        for tryCamera in [false, true] {
            let flow = visibilityFlow()
            flow.answerVisibility(canSeeObject: tryCamera)
            if tryCamera { flow.useVirtualStar() }
            #expect(flow.step == .find)
            #expect(flow.star != nil)
            #expect(!flow.isFindingRealObject)
        }
    }

    @Test func closingCameraReturnsToVisibilityChoice() {
        let flow = visibilityFlow()
        flow.answerVisibility(canSeeObject: true)
        flow.realCameraClosed()
        #expect(flow.step == .visibility)
        #expect(flow.star == nil)
        flow.answerVisibility(canSeeObject: false)
        #expect(flow.star != nil)
    }

    @Test func slowStartupOffersRetryInsteadOfClaimingCameraPermissionIsOff() {
        let flow = OnboardingFlow()
        flow.jump(to: "camera")
        flow.cameraModeChanged(true)
        flow.cameraFailed(.timedOut)
        #expect(flow.card?.title == OnboardingCopy.cameraRetryTitle)
        #expect(flow.card?.primary == OnboardingCopy.retryCamera)
        #expect(flow.card?.body.contains("Settings") == false)
        var retried = false
        flow.actions.setCamera = { retried = $0 }
        flow.primary()
        #expect(retried && flow.cameraStarting && !flow.cameraUnavailable)
        flow.liveCameraReady(nil)
        #expect(flow.succeeded)
        #expect(flow.startCollectingPressed())
        #expect(flow.step == .visibility)
    }

    @Test func captureFailureShowsTheRealReasonAndAllowsExplicitVirtualFallback() {
        let flow = OnboardingFlow()
        flow.jump(to: "camera")
        flow.cameraFailed(.capture("Motion data is unavailable."))
        #expect(flow.card?.body.contains("Motion data is unavailable.") == true)
        #expect(flow.card?.body.contains("Settings") == false)
        flow.secondary()
        #expect(flow.step == .find && flow.star != nil)
    }

    @Test func sensorFailureAfterPreviewStartedStillOffersRetry() {
        let flow = OnboardingFlow()
        flow.jump(to: "camera")
        flow.liveCameraReady(nil)
        #expect(flow.succeeded)
        flow.cameraFailed(.capture("Motion unavailable"))
        #expect(!flow.succeeded && flow.cameraUnavailable)
        #expect(flow.card?.primary == OnboardingCopy.retryCamera)
        flow.primary()
        #expect(flow.step == .camera && flow.cameraStarting)
        flow.liveCameraReady(nil)
        #expect(flow.startCollectingPressed())
        #expect(flow.step == .visibility)
    }

    @Test func skippingDuringValidationCancelsThePendingCaptureAndNeverRestarts() async throws {
        let flow = visibilityFlow()
        flow.answerVisibility(canSeeObject: false)
        var captures = 0
        var cancellations = 0
        var finishes = 0
        flow.actions.collect = { _, _ in captures += 1 }
        flow.actions.cancel = { cancellations += 1 }
        flow.actions.finish = { finishes += 1 }
        flow.isLocked = true
        flow.collect(at: .zero)
        #expect(flow.isValidating)
        flow.skip()
        try await Task.sleep(for: .milliseconds(600))
        flow.liveCameraReady(nil)
        flow.wormholeEnded()
        flow.primary()
        flow.skip()
        #expect(flow.step == .done && flow.card == nil && flow.star == nil)
        #expect(!flow.isLocked && !flow.isValidating)
        #expect(captures == 0 && cancellations == 1 && finishes == 1)
    }

    @Test func cameraUnavailableStillAllowsPractice() {
        let flow = OnboardingFlow()
        flow.jump(to: "camera")
        flow.cameraFailed()
        flow.primary()
        #expect(flow.step == .find)
        #expect(flow.star != nil)
        #expect(flow.cameraUnavailable)
    }
}
