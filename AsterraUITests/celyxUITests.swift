//
//  celyxUITests.swift
//  celyx
//
//  Created by Ferdiansyah Annora on 02/11/26.
//

import XCTest

final class celyxUITests: XCTestCase {
    @MainActor
    func testDirectionMenuOmitsManualCalibrationAndReset() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-hasCompletedTour", "YES", "-gardenUsesCamera", "NO"]
        app.launch()
        let directionOptions = app.buttons["Direction options"]
        XCTAssertTrue(directionOptions.waitForExistence(timeout: 15))
        directionOptions.tap()
        XCTAssertTrue(app.buttons["Gyro"].exists)
        XCTAssertTrue(app.buttons["Touch"].exists)
        XCTAssertTrue(app.buttons["Replay tour"].exists)
        XCTAssertFalse(app.buttons["Calibrate direction"].exists)
        XCTAssertFalse(app.buttons["Reset view"].exists)
    }

    @MainActor
    func testCollectionObjectSheetOpensAtFullHeight() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-collection-observation-log"]
        app.launch()
        let star = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Rigel")).firstMatch
        XCTAssertTrue(star.waitForExistence(timeout: 15))
        star.tap()

        let log = app.staticTexts["Observation log"]
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        let guide = app.buttons["guide-to-collected-object"]
        XCTAssertTrue(guide.isHittable)

        let title = app.staticTexts["Rigel"].firstMatch
        let sheetTop = (title.frame.minY - 25) / app.frame.height
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: sheetTop))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: sheetTop + 0.2)))
        XCTAssertTrue(log.exists)
        XCTAssertTrue(guide.isHittable)
    }

    @MainActor
    func testGardenObjectSheetExpandsIntoObservationLog() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-observation-log"]
        app.launch()
        let star = app.buttons["preview-collected-star"]
        XCTAssertTrue(star.waitForExistence(timeout: 15))
        star.tap()
        let fact = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "blue supergiant")).firstMatch
        XCTAssertTrue(fact.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Observation log"].exists)
        let collapsed = XCTAttachment(screenshot: app.screenshot())
        collapsed.name = "Compact observation sheet"
        collapsed.lifetime = .keepAlways
        add(collapsed)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.76))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.16)))
        XCTAssertTrue(app.staticTexts["Observation log"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "2/9")).firstMatch.exists)
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Mount Bromo")).firstMatch.exists)
        XCTAssertFalse(app.buttons["guide-to-collected-object"].exists)
        let expanded = XCTAttachment(screenshot: app.screenshot())
        expanded.name = "Expanded observation log"
        expanded.lifetime = .keepAlways
        add(expanded)
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Tebet")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Observation 2 of 2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["collected-star-photo"].exists)
        let detail = XCTAttachment(screenshot: app.screenshot())
        detail.name = "Capture detail"
        detail.lifetime = .keepAlways
        add(detail)
    }

    @MainActor
    func testSkipExitsTheTourAndStaysFinishedAfterRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-onboarding"]
        app.launch()
        let skip = app.buttons["Skip Tour"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        skip.tap()
        XCTAssertTrue(app.buttons["Your Collection"].waitForExistence(timeout: 5))
        XCTAssertFalse(skip.exists)
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["Your Collection"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Skip Tour"].exists)
        XCTAssertFalse(app.staticTexts["Welcome to Asterra"].exists)
    }

    @MainActor
    func testDiscoveryTooltipsPointToTheRealControls() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset-discovery", "-hasCompletedTour", "YES", "-gardenUsesCamera", "NO"]
        app.launch()
        let collection = app.buttons["Your Collection"]
        XCTAssertTrue(collection.waitForExistence(timeout: 15))
        collection.tap()
        let collectionToast = app.descendants(matching: .any)["collection-discovery-tip"].firstMatch
        XCTAssertTrue(collectionToast.waitForExistence(timeout: 5))
        XCTAssertLessThan(collectionToast.frame.height, app.frame.height * 0.2)
        let collectionShot = XCTAttachment(screenshot: app.screenshot())
        collectionShot.name = "Popover pointing at Stars"
        collectionShot.lifetime = .keepAlways
        add(collectionShot)
        XCTAssertFalse(app.buttons["View stars"].exists)
        app.buttons["Dismiss tip"].tap()
        app.buttons["collection-stars-tile"].tap()
        XCTAssertTrue(app.navigationBars["Stars"].waitForExistence(timeout: 5))
        app.buttons["Back"].firstMatch.tap()
        collection.tap()
        XCTAssertFalse(collectionToast.exists)
        app.buttons["Close"].tap()
        app.buttons["Sky Calendar"].tap()
        let calendarToast = app.descendants(matching: .any)["calendar-discovery-tip"].firstMatch
        XCTAssertTrue(calendarToast.waitForExistence(timeout: 5))
        XCTAssertLessThan(calendarToast.frame.height, app.frame.height * 0.2)
        XCTAssertLessThan(calendarToast.frame.maxY, app.frame.midY)
        let calendarShot = XCTAttachment(screenshot: app.screenshot())
        calendarShot.name = "Popover pointing at Calendar"
        calendarShot.lifetime = .keepAlways
        add(calendarShot)
        XCTAssertFalse(app.buttons["Try Calendar"].exists)
        app.buttons["Dismiss tip"].tap()
        XCTAssertTrue(app.navigationBars["Sky Events"].exists)
        XCTAssertFalse(app.buttons["About sky events"].exists)
        let displayMode = app.segmentedControls["sky-events-display-mode"]
        XCTAssertTrue(displayMode.exists)
        XCTAssertTrue(displayMode.buttons["List"].isSelected)
        displayMode.buttons["Calendar"].tap()
        XCTAssertTrue(app.staticTexts["Tap a marked date to view its events."].waitForExistence(timeout: 5))
        displayMode.buttons["List"].tap()
        XCTAssertTrue(displayMode.buttons["List"].isSelected)
        app.buttons["Back"].firstMatch.tap()
        app.buttons["Sky Calendar"].tap()
        XCTAssertFalse(calendarToast.exists)
        XCTAssertFalse(app.buttons["About sky events"].exists)
        let firstCard = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "sky-event-card-")).firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5))
        XCTAssertLessThan(firstCard.frame.height, app.frame.height * 0.3)
        let events = XCTAttachment(screenshot: app.screenshot())
        events.name = "Event cards — separate artwork, title, date and time"
        events.lifetime = .keepAlways
        add(events)
    }

    @MainActor
    func testTourExplainsFirstLandingBeforeTheNoteWithoutASecondFlight() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-onboarding", "-onboarding-step=visibility",
            "-onboarding-aimed", "-ui-testing-reset-discovery"]
        app.launch()
        XCTAssertTrue(app.buttons["Try a virtual star"].waitForExistence(timeout: 10))
        app.buttons["Try a virtual star"].tap()
        XCTAssertTrue(app.staticTexts["There you go! Target locked."].waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        let editor = app.descendants(matching: .any)["collection-note-editor"]
        XCTAssertTrue(app.staticTexts["This is your virtual garden"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["You're all set!"].exists)
        XCTAssertFalse(editor.exists)
        XCTAssertTrue(app.staticTexts["Your practice star"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["tour-garden-star-highlight"].exists)
        let garden = XCTAttachment(screenshot: app.screenshot())
        garden.name = "First landing — garden explained before the note"
        garden.lifetime = .keepAlways
        add(garden)
        app.buttons["Continue"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("My first sky memory.\n")
        XCTAssertTrue(app.staticTexts["You're all set!"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["This is your virtual garden"].exists)
        XCTAssertFalse(app.staticTexts["Your practice star"].exists)
        let achievement = XCTAttachment(screenshot: app.screenshot())
        achievement.name = "Tour finished — personal completion message"
        achievement.lifetime = .keepAlways
        add(achievement)
        app.buttons["finish-tour-celebration"].tap()
        let collection = app.buttons["Your Collection"]
        XCTAssertTrue(collection.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Practice Star, collected")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Back in your Night Sea"].exists)
        XCTAssertFalse(app.buttons["Skip Tour"].exists)
        XCTAssertFalse(app.staticTexts["Your practice star"].exists)
    }

    @MainActor
    func testDaytimeGuideCollectsSunAndKeepsItAfterTheTour() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-daytime", "-onboarding",
            "-onboarding-step=visibility", "-onboarding-aimed"]
        app.launch()
        let guide = app.buttons["Find the Sun with a guide"]
        XCTAssertTrue(guide.waitForExistence(timeout: 10))
        guide.tap()
        XCTAssertTrue(app.staticTexts["There you go! Target locked."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Practice Star"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        XCTAssertTrue(app.staticTexts["This is your virtual garden"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Your Sun"].exists)
        XCTAssertFalse(app.staticTexts["Collected! Watch it fly into your Night Sea."].exists)
        let garden = XCTAttachment(screenshot: app.screenshot())
        garden.name = "Guided Sun in the garden"
        garden.lifetime = .keepAlways
        add(garden)
        app.buttons["Continue"].tap()
        let editor = app.descendants(matching: .any)["collection-note-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        editor.typeText("My Sun from the tour.")
        app.keyboards.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["You're all set!"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["This practice star will leave when you tap Done. The real stars you collect will stay in your garden."].exists)
        app.buttons["finish-tour-celebration"].tap()
        XCTAssertTrue(app.buttons["Your Collection"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments = ["-ui-testing", "-ui-testing-daytime"]
        app.launch()
        XCTAssertTrue(app.buttons["Your Collection"].waitForExistence(timeout: 10))
        app.buttons["Your Collection"].tap()
        let dismissTip = app.buttons["Dismiss tip"]
        if dismissTip.waitForExistence(timeout: 3) { dismissTip.tap() }
        app.buttons["collection-stars-tile"].tap()
        XCTAssertTrue(app.navigationBars["Stars"].waitForExistence(timeout: 10))
        let sun = app.staticTexts["Sun"].firstMatch
        XCTAssertTrue(sun.waitForExistence(timeout: 10))
        sun.tap()
        let note = app.staticTexts["collected-star-note"]
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        XCTAssertTrue(note.label.contains("My Sun from the tour."))
    }

    @MainActor
    func testRealCameraGuideStaysCompact() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-onboarding", "-onboarding-step=visibility", "-onboarding-aimed"]
        app.launch()
        let camera = app.buttons["Yes, try the camera"]
        XCTAssertTrue(camera.waitForExistence(timeout: 10))
        camera.tap()
        let practice = app.buttons["tour-camera-try-virtual-star"]
        XCTAssertTrue(practice.waitForExistence(timeout: 15))
        XCTAssertTrue(practice.isHittable)
        XCTAssertGreaterThanOrEqual(practice.frame.height, 44)
        let guide = app.descendants(matching: .any)["tour-camera-guide"].firstMatch
        XCTAssertLessThan(guide.frame.height, 140)
        XCTAssertGreaterThan(guide.frame.minY, app.frame.height * 0.7)
        XCTAssertLessThan(guide.frame.maxY, app.frame.height)
        let panel = XCTAttachment(screenshot: app.screenshot())
        panel.name = "Camera guide — bottom hint with consistent typography"
        panel.lifetime = .keepAlways
        add(panel)
        practice.tap()
        XCTAssertTrue(app.staticTexts["There you go! Target locked."].waitForExistence(timeout: 10))
    }

    @MainActor
    func testMenuTipsAppearOnlyOnFirstVisit() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset-discovery"]
        app.launch()
        let collection = app.buttons["Your Collection"]
        XCTAssertTrue(collection.waitForExistence(timeout: 10))
        collection.tap()
        let collectionTip = app.descendants(matching: .any)["collection-discovery-tip"].firstMatch
        XCTAssertTrue(collectionTip.waitForExistence(timeout: 5))
        let collectionShot = XCTAttachment(screenshot: app.screenshot())
        collectionShot.name = "First collection visit — contextual tip"
        collectionShot.lifetime = .keepAlways
        add(collectionShot)
        XCTAssertLessThan(collectionTip.frame.height, app.frame.height * 0.2)
        XCTAssertFalse(app.buttons["View stars"].exists)
        app.buttons["Dismiss tip"].tap()
        app.buttons["collection-stars-tile"].tap()
        XCTAssertTrue(app.navigationBars["Stars"].waitForExistence(timeout: 5))
        app.buttons["Back"].firstMatch.tap()
        collection.tap()
        XCTAssertFalse(collectionTip.exists)
        app.buttons["Close"].tap()
        app.buttons["Sky Calendar"].tap()
        let calendarTip = app.descendants(matching: .any)["calendar-discovery-tip"].firstMatch
        XCTAssertTrue(calendarTip.waitForExistence(timeout: 5))
        let calendarShot = XCTAttachment(screenshot: app.screenshot())
        calendarShot.name = "First calendar visit — contextual tip"
        calendarShot.lifetime = .keepAlways
        add(calendarShot)
        XCTAssertLessThan(calendarTip.frame.height, app.frame.height * 0.2)
        XCTAssertLessThan(calendarTip.frame.maxY, app.frame.midY)
        XCTAssertFalse(app.buttons["Try Calendar"].exists)
        app.buttons["Dismiss tip"].tap()
        let eventTip = app.descendants(matching: .any)["event-card-discovery-tip"].firstMatch
        XCTAssertTrue(eventTip.waitForExistence(timeout: 5))
        app.buttons["Dismiss tip"].tap()
        app.buttons["Calendar"].tap()
        XCTAssertTrue(app.staticTexts["Tap a marked date to view its events."].waitForExistence(timeout: 5))
        app.buttons["Back"].firstMatch.tap()
        app.buttons["Sky Calendar"].tap()
        XCTAssertFalse(calendarTip.exists)
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["Your Collection"].waitForExistence(timeout: 10))
        app.buttons["Your Collection"].tap()
        XCTAssertFalse(collectionTip.exists)
        app.buttons["Close"].tap()
        app.buttons["Sky Calendar"].tap()
        XCTAssertFalse(calendarTip.exists)
    }

    @MainActor
    func testOnboardingReceivesReadinessFromTheRealGardenCamera() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This regression needs the physical camera and motion sensors.")
        #else
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-onboarding", "-onboarding-step=camera"]
        app.launch()
        let camera = app.buttons["Show real sky through the camera"]
        XCTAssertTrue(camera.waitForExistence(timeout: 20))
        camera.tap()
        XCTAssertTrue(app.staticTexts["That's the real sky"].waitForExistence(timeout: 15),
            "Home → GardenSkyView → GardenCameraLayer must forward readiness to the tour")
        XCTAssertFalse(app.staticTexts["Let’s retry the camera"].exists)
        let ready = XCTAttachment(screenshot: app.screenshot())
        ready.name = "Onboarding recognizes the real camera"
        ready.lifetime = .keepAlways
        add(ready)
        app.buttons["start-collecting"].tap()
        XCTAssertTrue(app.buttons["Yes, try the camera"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Try a virtual star"].exists)
        #endif
    }

    @MainActor
    func testCollectedStarOpensSharePageAndSwitchesLayouts() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-share-flow"]
        app.launch()
        let star = app.buttons["share-flow-star"]
        XCTAssertTrue(star.waitForExistence(timeout: 20))
        star.tap()
        let share = app.buttons["share-collected-star"]
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["open-star-album"].exists)
        share.tap()
        let close = app.buttons["close-star-share"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["share-layout-polaroid"].exists)
        XCTAssertFalse(app.buttons["share-layout-fullPhoto"].exists)
        for destination in ["instagram", "copy", "save", "more"] {
            let button = app.buttons["share-destination-\(destination)"]
            XCTAssertTrue(button.exists)
            XCTAssertTrue(button.isEnabled)
        }
        try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/private/tmp/celyx-share-polaroid.png"))
        let pager = app.descendants(matching: .any).matching(identifier: "share-layout-pager").firstMatch
        pager.swipeLeft()
        let fullPhoto = app.descendants(matching: .any).matching(identifier: "share-card-fullPhoto").firstMatch
        XCTAssertTrue(fullPhoto.waitForExistence(timeout: 5))
        XCTAssertTrue(fullPhoto.label.contains("Light Pollution Unavailable"))
        try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/private/tmp/celyx-share-full-photo.png"))
        pager.swipeRight()
        let card = app.descendants(matching: .any).matching(identifier: "share-card-polaroid").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.value as? String, "Star 3")
        let cardFrameBeforeCopy = card.frame
        app.buttons["share-destination-copy"].tap()
        XCTAssertTrue(app.staticTexts["Card copied"].waitForExistence(timeout: 10))
        XCTAssertEqual(card.frame.minY, cardFrameBeforeCopy.minY, accuracy: 0.5)
        XCTAssertEqual(card.frame.width, cardFrameBeforeCopy.width, accuracy: 0.5)
        XCTAssertEqual(card.frame.height, cardFrameBeforeCopy.height, accuracy: 0.5)
        close.tap()
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(share.waitForExistence(timeout: 5))
    }

    @MainActor
    func testCaptureNoteKeyboardSubmissionPersistenceAndSharing() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-note-flow"]
        app.launch()
        let capture = app.buttons["preview-finish-capture"]
        XCTAssertTrue(capture.waitForExistence(timeout: 15)); capture.tap()
        let editor = app.descendants(matching: .any).matching(identifier: "collection-note-editor").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/private/tmp/asterra-note-entry.png"))
        editor.tap()
        editor.typeText("A clear night above Jakarta.")
        editor.typeText("\n")
        let note = app.staticTexts["collected-star-note"]
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        XCTAssertTrue(note.label.contains("A clear night above Jakarta."))
        XCTAssertTrue(app.descendants(matching: .any)["collected-star-photo"].exists)
        try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/private/tmp/asterra-collected-details.png"))
        app.buttons["close-collected-star"].tap()
        app.buttons["preview-collected-star"].tap()
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertTrue(note.label.contains("A clear night above Jakarta."))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "collection-note-editor").firstMatch.exists)
        note.tap()
        XCTAssertFalse(editor.exists)
        let edit = app.buttons["edit-collected-star-note"]
        XCTAssertTrue(edit.isHittable)
        edit.tap()
        let reopenedEditor = app.descendants(matching: .any)["collection-note-editor"].firstMatch
        XCTAssertTrue(reopenedEditor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["collected-star-photo"].exists)
        reopenedEditor.typeText(" Clear skies.")
        app.staticTexts["Rigel"].firstMatch.tap()
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertTrue(note.label.contains("Clear skies."))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        let share = app.buttons["share-collected-star"]
        for _ in 0..<5 {
            if share.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(share.isHittable)
        XCTAssertLessThanOrEqual(share.frame.height, 56)
        try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/private/tmp/asterra-detail-actions.png"))
        share.tap()
        let card = app.descendants(matching: .any)["share-card-polaroid"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(card.label.contains("A clear night above Jakarta."))
        app.buttons["close-star-share"].tap()
        app.buttons["close-collected-star"].tap()
    }

    @MainActor
    func testCollectedDetailsDeletionRequiresConfirmation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-note-flow"]
        app.launch()
        let star = app.buttons["preview-collected-star"]
        XCTAssertTrue(star.waitForExistence(timeout: 15)); star.tap()
        let remove = app.buttons["delete-collected-star"]
        for _ in 0..<5 {
            if remove.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        remove.tap()
        try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/private/tmp/asterra-delete-confirm.png"))
        let confirmation = app.sheets["Delete Rigel?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        } else {
            // Native compact popovers cancel by tapping outside rather than adding a Cancel row.
            let point = CGPoint(x: confirmation.frame.midX, y: confirmation.frame.minY - 24)
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).tap()
        }
        XCTAssertTrue(app.buttons["close-collected-star"].exists)
        remove.tap()
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Delete"].tap()
        let deleted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: star)
        XCTAssertEqual(XCTWaiter.wait(for: [deleted], timeout: 5), .completed)
    }

    @MainActor
    func testSocialSharingCancelLeavesFooterUsable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-share-flow"]
        app.launch()
        let star = app.buttons["share-flow-star"]
        XCTAssertTrue(star.waitForExistence(timeout: 20))
        star.tap()
        let share = app.buttons["share-collected-star"]
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        share.tap()
        XCTAssertTrue(app.buttons["close-star-share"].waitForExistence(timeout: 10))
        app.buttons["share-destination-instagram"].tap()
        let alert = app.alerts["Couldn’t share card"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["OK"].tap()

        // Exercise the real sheet lifecycle using the More button.
        for _ in 0..<2 {
            app.buttons["share-destination-more"].tap()
            let cancel = app.buttons["header.closeButton"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 10))
            cancel.tap()
            let copy = app.buttons["share-destination-copy"]
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                copy.exists && copy.isEnabled && copy.isHittable
            }, object: copy)
            XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
            copy.tap()
            XCTAssertTrue(app.staticTexts["Card copied"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["share-destination-more"].isEnabled)
        }

    }

    @MainActor
    func testCalendarListAndMonthControls() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        let calendar = app.buttons["Sky Calendar"]
        XCTAssertTrue(calendar.waitForExistence(timeout:30))
        calendar.tap()
        XCTAssertTrue(app.navigationBars["Sky Calendar"].waitForExistence(timeout:10))
        app.buttons["Calendar"].tap()
        let next = app.buttons["Next month"]
        XCTAssertTrue(next.waitForExistence(timeout:5))
        next.tap()
        app.buttons["Previous month"].tap()
        XCTAssertTrue(app.staticTexts["Tap a marked date to view its events."].exists)
        app.buttons["List"].tap()
        XCTAssertTrue(app.buttons["Moon"].exists)
        let screenshot = XCTAttachment(screenshot:app.screenshot())
        screenshot.name = "Calendar after MVVM refactor"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testAlbumShowsCityAndSavesStoryPNGToPhotos() throws {
        continueAfterFailure = false
        let permissions = addUIInterruptionMonitor(withDescription:"Allow adding album photos") { alert in
            let allow = alert.buttons.matching(identifier:"Allow").firstMatch
            guard allow.exists else { return false }
            allow.tap(); return true
        }
        defer { removeUIInterruptionMonitor(permissions) }
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing","-ui-testing-album"]
        app.launch()
        let export = app.buttons["export-star-story"]
        XCTAssertTrue(export.waitForExistence(timeout:20))
        XCTAssertTrue(app.staticTexts["Jakarta Pusat, Jakarta"].exists)
        let album = XCTAttachment(screenshot:app.screenshot())
        album.name = "Star album — framed photo and native toolbar"; album.lifetime = .keepAlways; add(album)
        export.tap()
        let save = app.buttons["save-story-png"]
        XCTAssertTrue(save.waitForExistence(timeout:10))
        let story = XCTAttachment(screenshot:app.screenshot())
        story.name = "Story template — PNG preview"; story.lifetime = .keepAlways; add(story)
        save.tap()
        let allow = XCUIApplication(bundleIdentifier:"com.apple.springboard").buttons.matching(identifier:"kTCCServicePhotosAdd-allow-button").firstMatch
        if allow.waitForExistence(timeout:5) { allow.tap() }
        else if !app.alerts["Saved to Photos"].exists { app.tap() }
        XCTAssertTrue(app.alerts["Saved to Photos"].waitForExistence(timeout:20))
    }
    @MainActor
    func testCameraExposureIsHiddenAtRestInCollectAndFilteredAR() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        let collect = app.buttons["start-collecting"]
        XCTAssertTrue(collect.waitForExistence(timeout:30))
        collect.tap()
        XCTAssertTrue(app.buttons["Back"].firstMatch.waitForExistence(timeout:10))
        let brightness = app.descendants(matching:.any)["camera-brightness-control"]
        XCTAssertFalse(brightness.exists)
        XCTAssertFalse(app.buttons["Brightness"].exists)
        let screenshot = XCTAttachment(screenshot:app.screenshot())
        screenshot.name = "Collect camera — exposure hidden at rest"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Back"].firstMatch.tap()
        app.buttons["open-filtered-stars"].tap()
        app.buttons["View filtered stars in AR"].tap()
        XCTAssertTrue(app.staticTexts["Filtered Stars AR"].waitForExistence(timeout:10))
        XCTAssertFalse(brightness.exists)
        XCTAssertFalse(app.buttons["Brightness"].exists)
    }

    @MainActor
    func testFilteredStarsCanBeOpenedFromHome() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        let list = app.buttons["open-filtered-stars"]
        XCTAssertTrue(list.waitForExistence(timeout:30))
        list.tap()
        XCTAssertTrue(app.staticTexts["Visible Now"].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["View filtered stars in AR"].exists)
        let screenshot = XCTAttachment(screenshot:app.screenshot())
        screenshot.name = "Filtered Stars — list and controls"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let daylight = app.switches["Daylight"]
        XCTAssertTrue(daylight.exists)
        let before = daylight.value as? String
        daylight.tap()
        XCTAssertNotEqual(daylight.value as? String,before)
        app.buttons["Back"].tap()
        XCTAssertTrue(list.waitForExistence(timeout:5))
    }

    @MainActor
    func testHomePanoramaAndControls() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        let search = app.buttons["Cari bintang"]
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        let topBar = app.navigationBars["Langit"]
        XCTAssertTrue(topBar.exists)
        XCTAssertTrue(topBar.buttons["Cari bintang"].exists)
        XCTAssertTrue(topBar.buttons["Atur lapisan langit"].exists)
        XCTAssertTrue(topBar.buttons["Bintang di sekitar"].exists)
        XCTAssertTrue(topBar.buttons["reset-sky"].exists)
        XCTAssertFalse(app.staticTexts["panorama-error"].exists)
        let initial = XCTAttachment(screenshot: app.screenshot())
        initial.name = "Home — initial panorama"; initial.lifetime = .keepAlways; add(initial)

        let compass = app.buttons["reset-sky"]
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.45))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.45))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertFalse(compass.label.hasSuffix(". 0 derajat"))
        compass.tap()
        XCTAssertTrue(compass.label.hasSuffix(". 0 derajat"))

        let lowerSky = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.38))
        let upperSky = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        lowerSky.press(forDuration: 0.1, thenDragTo: upperSky)
        let zenith = XCTAttachment(screenshot: app.screenshot())
        zenith.name = "Home — looking upward"; zenith.lifetime = .keepAlways; add(zenith)
        XCTAssertFalse(app.staticTexts["panorama-error"].exists)
        compass.tap()

        app.buttons["Atur lapisan langit"].tap()
        let grid = app.switches["Grid koordinat"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        grid.tap()
        app.buttons["Selesai"].tap()
        search.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Sirius")
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Sirius'")).firstMatch.tap()
        let collect = app.buttons["collect-star"]
        XCTAssertTrue(collect.waitForExistence(timeout:5))
        let detail = XCTAttachment(screenshot:app.screenshot())
        detail.name = "Star detail"; detail.lifetime = .keepAlways; add(detail)
        app.buttons["Tutup detail"].tap()
        let restoredZoom = XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@", "Zoom 1.0×"),object:app.otherElements["sky-panorama"])
        XCTAssertEqual(XCTWaiter.wait(for:[restoredZoom],timeout:5),.completed)
        app.buttons["Bintang di sekitar"].tap()
        XCTAssertTrue(app.navigationBars["Langit sekitar"].waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts["panorama-error"].exists)
    }
    @MainActor
    func testDaytimeSunCanBeFoundAndCollected() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-daytime"]
        app.launch()
        let search = app.buttons["Cari bintang"]
        XCTAssertTrue(search.waitForExistence(timeout:30))
        search.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout:5))
        field.tap(); field.typeText("Matahari")
        app.buttons.matching(NSPredicate(format:"label CONTAINS 'Matahari'")).firstMatch.tap()
        let collect = app.buttons["collect-star"]
        XCTAssertTrue(collect.waitForExistence(timeout:5))
        if collect.isEnabled { collect.tap() }
        XCTAssertTrue(collect.label.contains("Collected"))
        XCTAssertFalse(collect.isEnabled)
        app.buttons["Tutup detail"].tap()
        let restoredZoom = XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@", "Zoom 1.0×"),object:app.otherElements["sky-panorama"])
        XCTAssertEqual(XCTWaiter.wait(for:[restoredZoom],timeout:5),.completed)
        let screenshot = XCTAttachment(screenshot:app.screenshot())
        screenshot.name = "Daytime Sun and zoomable star map"
        screenshot.lifetime = .keepAlways; add(screenshot)
    }

    @MainActor
    func testFindInSkyOpensCameraAvailabilityAndCloses() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-daytime"]
        app.launch()
        let search = app.buttons["Cari bintang"]
        XCTAssertTrue(search.waitForExistence(timeout:30))
        search.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout:5))
        field.tap(); field.typeText("Matahari")
        app.buttons.matching(NSPredicate(format:"label CONTAINS 'Matahari'")).firstMatch.tap()
        let find = app.buttons["find-in-sky"]
        app.swipeUp()
        XCTAssertTrue(find.waitForExistence(timeout:5))
        let detail = XCTAttachment(screenshot:app.screenshot())
        detail.name = "Temukan di Langit — detail action"
        detail.lifetime = .keepAlways; add(detail)
        find.tap()
        XCTAssertTrue(app.navigationBars["Temukan Matahari"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["Mode kamera tidak tersedia"].waitForExistence(timeout:10))
        let screenshot = XCTAttachment(screenshot:app.screenshot())
        screenshot.name = "Camera finder — unavailable on Simulator"
        screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["Tutup kamera langit"].tap()
        XCTAssertTrue(search.waitForExistence(timeout:5))
    }

    @MainActor
    func testDeepZoomTransitionsToSpaceAndResetReturnsToAtmosphere() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-daytime"]
        app.launch()
        XCTAssertTrue(app.buttons["Cari bintang"].waitForExistence(timeout:30))
        let before = XCTAttachment(screenshot:app.screenshot())
        before.name = "Daytime islands — clean silhouette"; before.lifetime = .keepAlways; add(before)
        let panorama = app.otherElements["sky-panorama"]
        XCTAssertTrue(panorama.exists)
        panorama.pinch(withScale:4,velocity:2)
        panorama.pinch(withScale:4,velocity:2)
        let zoom = try XCTUnwrap(panorama.value as? String)
        XCTAssertNotEqual(zoom,"Zoom 1.0×")
        XCTAssertFalse(app.staticTexts["panorama-error"].exists)
        let after = XCTAttachment(screenshot:app.screenshot())
        after.name = "Deep zoom — space transition"; after.lifetime = .keepAlways; add(after)
        app.buttons["reset-sky"].tap()
        XCTAssertEqual(panorama.value as? String,"Zoom 1.0×")
    }

    @MainActor
    func testStarTapZoomsInAndCloseRestoresPreviousZoom() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["Cari bintang"].waitForExistence(timeout:30))
        let panorama = app.otherElements["sky-panorama"]
        let originalZoom = try XCTUnwrap(panorama.value as? String)
        let star = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'star-label-'")).firstMatch
        XCTAssertTrue(star.waitForExistence(timeout:5))
        star.tap()
        XCTAssertTrue(app.buttons["collect-star"].waitForExistence(timeout:5))
        XCTAssertNotEqual(panorama.value as? String,originalZoom)
        let detail = XCTAttachment(screenshot:app.screenshot())
        detail.name = "Animated detail — zoomed into selected star"; detail.lifetime = .keepAlways; add(detail)
        app.buttons["Tutup detail"].tap()
        let restored = XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@",originalZoom),object:panorama)
        XCTAssertEqual(XCTWaiter.wait(for:[restored],timeout:5),.completed)
        XCTAssertTrue(star.waitForExistence(timeout:5))
        let wide = XCTAttachment(screenshot:app.screenshot())
        wide.name = "Animated detail — previous view restored"; wide.lifetime = .keepAlways; add(wide)
    }

    @MainActor
    func testGardenShowsCollectedSunAndSearchableCollection() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-daytime"]
        app.launch()
        let search = app.buttons["Cari bintang"]
        XCTAssertTrue(search.waitForExistence(timeout:30))
        search.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout:5))
        field.tap(); field.typeText("Matahari")
        app.buttons.matching(NSPredicate(format:"label CONTAINS 'Matahari'")).firstMatch.tap()
        let collect = app.buttons["collect-star"]
        XCTAssertTrue(collect.waitForExistence(timeout:5))
        if collect.isEnabled { collect.tap() }
        app.buttons["Tutup detail"].tap()
        let restored = XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@","Zoom 1.0×"),object:app.otherElements["sky-panorama"])
        XCTAssertEqual(XCTWaiter.wait(for:[restored],timeout:5),.completed)
        let garden = app.buttons["Buka Garden"]
        XCTAssertTrue(garden.waitForExistence(timeout:5)); garden.tap()
        XCTAssertTrue(app.navigationBars["Your Galaxy"].waitForExistence(timeout:10))
        let ready = XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:app.buttons["Lihat Collection"])
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:5),.completed)
        let rotation = app.buttons["garden-rotation-toggle"]
        XCTAssertTrue(rotation.exists)
        rotation.tap()
        XCTAssertEqual(rotation.label,"Putar galaksi")
        rotation.tap()
        XCTAssertEqual(rotation.label,"Jeda putaran galaksi")
        let galaxy = XCTAttachment(screenshot:app.screenshot())
        galaxy.name = "Your Galaxy — rotating collection garden"; galaxy.lifetime = .keepAlways; add(galaxy)
        app.buttons["Lihat Collection"].tap()
        XCTAssertTrue(app.navigationBars["Collection"].waitForExistence(timeout:5))
        let fullList = XCTAttachment(screenshot:app.screenshot())
        fullList.name = "Collection — unlocked and locked cards"; fullList.lifetime = .keepAlways; add(fullList)
        let collectionSearch = app.searchFields.firstMatch
        XCTAssertTrue(collectionSearch.waitForExistence(timeout:5))
        collectionSearch.tap(); collectionSearch.typeText("Matahari")
        let sun = app.buttons["collection-item--1"]
        XCTAssertTrue(sun.waitForExistence(timeout:5))
        let list = XCTAttachment(screenshot:app.screenshot())
        list.name = "Collection — real saved Sun record"; list.lifetime = .keepAlways; add(list)
        sun.tap()
        XCTAssertTrue(app.navigationBars["Your Galaxy"].waitForExistence(timeout:5))
        let card = app.buttons["garden-selected-card"]
        XCTAssertTrue(card.waitForExistence(timeout:5))
        let selected = XCTAttachment(screenshot:app.screenshot())
        selected.name = "Your Galaxy — selected Sun and collection card"; selected.lifetime = .keepAlways; add(selected)
        card.tap()
        XCTAssertTrue(app.navigationBars["Matahari"].waitForExistence(timeout:5))
        app.buttons["Selesai"].tap()
        app.buttons["Kembali ke Langit"].tap()
        XCTAssertTrue(search.waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts["panorama-error"].exists)
    }

    @MainActor
    func testConstellationIllustrationNearCenteredStar() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        let search = app.buttons["Cari bintang"]
        XCTAssertTrue(search.waitForExistence(timeout:30))
        search.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout:5))
        field.tap(); field.typeText("Mirach")
        app.buttons.matching(NSPredicate(format:"label CONTAINS 'Mirach'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Tutup detail"].waitForExistence(timeout:5))
        app.buttons["Tutup detail"].tap()
        let restoredZoom = XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@", "Zoom 1.0×"),object:app.otherElements["sky-panorama"])
        XCTAssertEqual(XCTWaiter.wait(for:[restoredZoom],timeout:5),.completed)
        let screenshot = XCTAttachment(screenshot:app.screenshot())
        screenshot.name = "Panorama restored after Mirach detail"
        screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["Atur lapisan langit"].tap()
        let figures = app.switches["Ilustrasi rasi bintang"]
        XCTAssertTrue(figures.waitForExistence(timeout:5))
        XCTAssertEqual(figures.value as? String,"1")
        figures.coordinate(withNormalizedOffset:CGVector(dx:0.92,dy:0.5)).tap()
        let disabled = XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == '0'"),object:figures)
        XCTAssertEqual(XCTWaiter.wait(for:[disabled],timeout:3),.completed)
    }

    /// Seeds Moon, planets and two stars, hides their names from the compass menu, and pinches the
    /// garden through a telescope-like zoom (screenshots for review; rendering is checked by unit tests).
    @MainActor
    func testStarNamesToggleAndGardenZoom() throws {
        continueAfterFailure = false
        let records = [-2, -4, -5, -6, -7, 0, 8].map {
            "{\"id\":\($0),\"date\":815000000,\"latitude\":-6.1754,\"longitude\":106.8272}"
        }
        let json = Data("[\(records.joined(separator: ","))]".utf8)
        let seeded = "<" + json.map { String(format: "%02x", $0) }.joined() + ">"
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-hasCompletedTour", "YES", "-gardenUsesCamera", "NO",
                               "-collectedStars", seeded]
        app.launch()
        let compass = app.buttons["Direction options"]
        XCTAssertTrue(compass.waitForExistence(timeout: 15))
        compass.tap()
        // A Toggle inside a Menu is exposed as a selectable button. (Not set through launch
        // arguments: the argument domain would override what the toggle stores.)
        let names = app.buttons["Star Names"].firstMatch
        XCTAssertTrue(names.waitForExistence(timeout: 5))
        if !names.isSelected {
            names.tap()
            compass.tap()
            XCTAssertTrue(names.waitForExistence(timeout: 5))
        }
        XCTAssertTrue(names.isSelected)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        let named = XCTAttachment(screenshot: app.screenshot())
        named.name = "Garden — star names on"; named.lifetime = .keepAlways; add(named)

        compass.tap()
        XCTAssertTrue(names.waitForExistence(timeout: 5))
        names.tap()
        compass.tap()
        XCTAssertTrue(names.waitForExistence(timeout: 5))
        XCTAssertFalse(names.isSelected)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()   // close the menu
        let hidden = XCTAttachment(screenshot: app.screenshot())
        hidden.name = "Garden — star names off"; hidden.lifetime = .keepAlways; add(hidden)

        // Through the zoom range; the app must keep running and accept taps.
        for step in 1...3 {
            app.pinch(withScale: 4, velocity: 3)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Garden — pinch zoom step \(step)"; shot.lifetime = .keepAlways; add(shot)
        }
        XCTAssertTrue(compass.isHittable)
        app.pinch(withScale: 0.05, velocity: -6)

        // The choice persists across launches.
        app.terminate()
        app.launchArguments = ["-ui-testing", "-hasCompletedTour", "YES", "-gardenUsesCamera", "NO", "-collectedStars", seeded]
        app.launch()
        XCTAssertTrue(compass.waitForExistence(timeout: 15))
        compass.tap()
        XCTAssertTrue(names.waitForExistence(timeout: 5))
        XCTAssertFalse(names.isSelected)
        names.tap()   // leave names on for the next run
    }
}
