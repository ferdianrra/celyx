import Testing
import Foundation
import simd
@testable import Asterra

@MainActor
struct GardenCaptureSequenceTests {
    #if DEBUG
    @Test func conjunctionLandsBothBodiesAndKeepsOneObservation() throws {
        let suite = "ConjunctionLanding.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let location = AppPreviewData.location
        let model = HomeViewModel(location: location, defaults: defaults)
        let date = Date()
        let event = SkyEvent.demoConjunction(at: date)
        let record = try model.saveEventObservation(event, image: AppPreviewData.albumPhoto,
            date: date, location: location)
        defer { model.deleteCollected(id: record.id) }

        let scene = GardenViewModel.wormholeScene(model: model, newID: record.id)
        let garden = GardenViewModel(model: model, camera: NightSeaCamera())
        garden.place(using: scene)
        let sky = SkyEventCatalog.guidance(of: event.target, at: date, location: location)
        #expect(model.collectionItems.count == 1)
        #expect(scene.newObjects.map(\.kind) == [.moon, .planet])
        #expect(garden.placed.map(\.title) == ["Moon", "Jupiter"])
        #expect(garden.placed.map(\.titleIsAbove) == [true, false])
        let profiles = garden.placed.map(\.selectionItem)
        #expect(profiles.map(\.star.title) == ["Moon", "Jupiter"])
        #expect(profiles.allSatisfy { $0.isEventMember && $0.displayedEvent == nil })
        let captureID = try #require(record.captureID)
        model.updateObservationNote(captureID: captureID, note: "Both in the frame.")
        model.updateObservationPlace(captureID: captureID, name: "Jakarta Pusat")
        for profile in profiles {
            let observation = try #require(model.observationHistory(for: profile).first)
            #expect(observation.captureID == captureID)
            #expect(observation.note == "Both in the frame.")
            #expect(observation.placeName == "Jakarta Pusat")
            #expect(observation.photoFilename == record.photoFilename)
        }
        #expect(Set(garden.placed.map(\.id)).count == 2)
        #expect(garden.placed.allSatisfy { $0.item.record.captureID == record.captureID })
        #expect(garden.placed.map(\.object.direction) == sky.members.map(\.position.direction))
        garden.place()
        #expect(garden.placed.map(\.id) == scene.newObjects.map(\.id))
        let freeze = WormholeFreeze.placeholder(size: CGSize(width: 402, height: 874))
        let handover = WormholeHandover(freeze: freeze, star: CGPoint(x: 201, y: 437), itemID: record.id, scene: scene)
        #expect(simd_distance(handover.starDirection, sky.position.direction) < 1e-9)

        let jupiter = try #require(profiles.last)
        garden.select(jupiter)
        #expect(garden.selected?.isEventMember == true)
        let ownCapture = try model.saveCameraObservation(.init(star: jupiter.star, image: AppPreviewData.albumPhoto,
            date: date, location: location, identificationNote: nil), note: "Separate Jupiter capture.")
        defer { model.deleteCollected(id: ownCapture.id) }
        garden.select(jupiter)
        let selected = try #require(garden.selected)
        #expect(selected.record.captureID == ownCapture.captureID)
        #expect(!selected.isEventMember)
        #expect(Set(model.observationHistory(for: selected).compactMap(\.captureID)) == Set([ownCapture.captureID, captureID].compactMap { $0 }))
        let moon = try #require(profiles.first)
        #expect(model.observationHistory(for: moon).map(\.captureID) == [captureID])
    }
    #endif

    @Test func gardenPlacementPreservesTheSunAndMoonCaptureIdentity() {
        let items = [CatalogStar.sun, CatalogStar.moon].map { star in
            GardenCollectionItem(star: star, record: CollectedStar(id: star.id, date: AppPreviewData.date,
                latitude: AppPreviewData.location.latitude, longitude: AppPreviewData.location.longitude))
        }
        let scene = GardenViewModel.placement(items: items, location: AppPreviewData.location,
            date: AppPreviewData.date)
        let objects = scene.placed.map(\.object)
        #expect(objects.map(\.id) == [CatalogStar.sun.id, CatalogStar.moon.id])
        #expect(objects.first { $0.id == CatalogStar.sun.id }?.kind == .sun)
        #expect(objects.first { $0.id == CatalogStar.moon.id }?.kind == .moon)
    }

    @Test func onboardingKeepsTheOriginalLandingFramedUntilTheGardenLessonContinues() async throws {
        let handover = transition()
        handover.holdForOnboarding()
        var phases: [WormholeHandover.Phase] = []
        await handover.run { _ in phases.append(handover.phase) }
        #expect(handover.phase == .presenting && handover.showsSheet)
        #expect(!phases.contains(.releasing))
        let settled = handover.camera(handover.revealAt)
        let held = handover.camera(handover.revealAt + 10000)
        #expect(simd_distance(settled.forward, held.forward) < 1e-9)
        #expect(abs(settled.focalLength(in: handover.freeze.size) - held.focalLength(in: handover.freeze.size)) < 1e-6)
        let point = try #require(held.project(handover.starDirection, in: handover.freeze.size))
        #expect(abs(point.y - handover.freeze.size.height * 0.36) < 1e-6)
    }

    @Test func reduceMotionAlsoHoldsTheFirstLandingForTheGardenLesson() async {
        let handover = transition()
        handover.holdForOnboarding()
        await handover.run(reduceMotion: true) { _ in }
        #expect(handover.holdsForOnboarding && handover.showsSheet && handover.phase == .presenting)
    }

    private func transition(itemID: Int? = 42) -> WormholeHandover {
        let freeze = WormholeFreeze.placeholder(size: CGSize(width: 402, height: 874))
        return WormholeHandover(freeze: freeze, star: CGPoint(x: 201, y: 437), itemID: itemID,
            scene: WormholeScene(objects: [], newID: nil, moon: nil, equatorial: nil))
    }

    @Test func revealsThenReturnsToGyroBeforeRequestingTheAlbum() async {
        let handover = transition()
        handover.configureFocus(directions: [], revealsConstellation: true)
        var phases: [WormholeHandover.Phase] = []
        await handover.run { deadline in
            if handover.phase == .revealing { #expect(deadline == handover.revealAt + 2700) }
            phases.append(handover.phase)
            #expect(!handover.showsSheet)
        }
        #expect(phases == [.wormhole, .landed, .reframe, .focusing, .revealing, .releasing, .presenting])
        #expect(handover.phase == .presenting && handover.showsSheet)
        handover.finish()
        #expect(handover.phase == .done && !handover.showsSheet)
    }

    @Test func isolatedStarPausesBrieflyAfterFocus() async {
        let handover = transition()
        var returnDeadline: Double?
        await handover.run { deadline in
            if handover.phase == .revealing { returnDeadline = deadline }
        }
        #expect(returnDeadline == handover.revealAt + 700)
        #expect(handover.showsSheet)
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
        handover.configureFocus(directions: [a, b], revealsConstellation: true)
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
