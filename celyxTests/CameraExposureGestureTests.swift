import Testing
@testable import celyx

struct CameraExposureGestureTests {
    @Test func upwardDragBrightensAndDownwardDragDarkensFromTheGestureStart() {
        let up = CameraExposureGesture.value(start:0,translation:-140,viewportHeight:800,minimum:-3,maximum:3)
        let down = CameraExposureGesture.value(start:0,translation:140,viewportHeight:800,minimum:-3,maximum:3)
        #expect(up == 3)
        #expect(down == -3)
        #expect(CameraExposureGesture.value(start:1,translation:0,viewportHeight:800,minimum:-3,maximum:3) == 1)
    }
    @Test func railTopAndBottomRespectTheActualDeviceRange() {
        #expect(CameraExposureGesture.value(at:0,height:100,minimum:-2,maximum:2) == 2)
        #expect(CameraExposureGesture.value(at:50,height:100,minimum:-2,maximum:2) == 0)
        #expect(CameraExposureGesture.value(at:100,height:100,minimum:-2,maximum:2) == -2)
        #expect(CameraExposureGesture.value(at:200,height:100,minimum:-2,maximum:2) == -2)
    }
    @Test func draggingClampsAtDeviceLimitsAndIgnoresAnUnavailableRange() {
        #expect(CameraExposureGesture.value(start:1,translation:-10000,viewportHeight:800,minimum:-2,maximum:2) == 2)
        #expect(CameraExposureGesture.value(start:1,translation:10000,viewportHeight:800,minimum:-2,maximum:2) == -2)
        #expect(CameraExposureGesture.value(start:0,translation:-100,viewportHeight:800,minimum:0,maximum:0) == 0)
    }
    @Test func exposureRailOnlyAppearsDuringAdjustmentAndBrieflyAfterIt() {
        var presentation = CameraExposurePresentation()
        #expect(!presentation.isVisible(at:100))
        presentation.begin()
        #expect(presentation.isVisible(at:100))
        #expect(presentation.isVisible(at:200),"Do not hide while a finger is still adjusting")
        presentation.end(at:200)
        #expect(presentation.isVisible(at:201))
        #expect(!presentation.isVisible(at:201.4))
    }
    @Test func anotherExposureGestureKeepsTheRailVisiblePastAnOldDeadline() {
        var presentation = CameraExposurePresentation()
        presentation.begin(); presentation.end(at:100)
        presentation.begin()
        #expect(presentation.isVisible(at:110))
        presentation.end(at:110)
        #expect(presentation.isVisible(at:111))
        presentation.reset()
        #expect(!presentation.isVisible(at:111))
    }

}
