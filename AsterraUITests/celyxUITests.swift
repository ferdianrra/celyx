//
//  celyxUITests.swift
//  celyx
//
//  Created by Ferdiansyah Annora on 02/11/26.
//

import XCTest

final class celyxUITests: XCTestCase {
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
        for destination in ["instagram", "whatsapp", "copy", "save", "more"] {
            let button = app.buttons["share-destination-\(destination)"]
            XCTAssertTrue(button.exists)
            XCTAssertTrue(button.isEnabled)
        }
        try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/private/tmp/celyx-share-polaroid.png"))
        let pager = app.descendants(matching: .any).matching(identifier: "share-layout-pager").firstMatch
        pager.swipeLeft()
        let fullPhoto = app.descendants(matching: .any).matching(identifier: "share-card-fullPhoto").firstMatch
        XCTAssertTrue(fullPhoto.waitForExistence(timeout: 5))
        XCTAssertTrue(fullPhoto.label.contains("Light Pollution 6.2/9"))
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

        // Exercise the real sheet lifecycle even without WhatsApp installed in the simulator.
        for _ in 0..<2 {
            app.buttons["share-destination-whatsapp"].tap()
            let cancel = app.buttons["header.closeButton"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 10))
            cancel.tap()
            let copy = app.buttons["share-destination-copy"]
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: copy)
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
        app.segmentedControls.buttons["Calendar"].tap()
        let next = app.buttons["Next month"]
        XCTAssertTrue(next.waitForExistence(timeout:5))
        next.tap()
        app.buttons["Previous month"].tap()
        XCTAssertTrue(app.staticTexts["Tap a marked date to view its events."].exists)
        app.segmentedControls.buttons["List"].tap()
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
        XCTAssertTrue(app.buttons["Calibrate direction"].waitForExistence(timeout:10))
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

}
