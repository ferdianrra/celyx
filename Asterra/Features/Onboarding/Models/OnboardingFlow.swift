import SwiftUI
import simd

/// First-run guided tour, played inside the real Home screen: every step is the user doing the real thing.
///
/// Welcome → look around the Night Sea → turn on the camera with the real toolbar button → find a practice
/// star through it with the real crosshair → tap → the real wormhole and note sheet → back to the Night Sea
/// with the same button → the collection → the Sky Calendar → ready. Nothing moves on by itself: after each
/// task the card confirms it and waits for Continue. The practice star is placed in front of wherever the
/// user is looking (a tutorial, not a catalogue star) and is never saved to the collection.
@MainActor @Observable
final class OnboardingFlow {
    enum Step: Int, Comparable, CaseIterable {
        case welcome
        /// Move the phone (or swipe) to look around the Night Sea.
        case look
        /// Tap the toolbar's camera button (camera permission is asked here, in context).
        case camera
        /// Find the practice star and tap to collect it.
        case find
        /// Shutter → wormhole → landing → note sheet (Home's real handover runs it).
        case wormhole
        /// What just happened; the same toolbar button switches back to the Night Sea.
        case landed
        /// Open the collection.
        case collection
        /// Open the Sky Calendar.
        case calendar
        /// Start Collecting glows; done.
        case ready
        case done
        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
        /// Steps counted in the progress dots.
        static let counted: [Step] = [.look, .camera, .find, .landed, .collection, .calendar]
    }

    /// What the tour asks Home to do (Home owns the real state).
    struct Actions {
        var setCamera: (Bool) -> Void = { _ in }
        var openCollection: () -> Void = {}
        var openCalendar: () -> Void = {}
        /// Start the real capture + wormhole for the practice star at this screen point.
        var collect: (_ star: PracticeStar, _ point: CGPoint) -> Void = { _, _ in }
        var finish: () -> Void = {}
    }

    struct PracticeStar: Identifiable, Equatable {
        /// Well outside the catalogue's IDs (and the Sun/Moon's negative ones).
        let id = 990_001
        /// Horizon direction [east, north, up].
        let direction: SIMD3<Double>
        let color = SIMD3(0.80, 0.88, 1.0)
        var catalogStar: CatalogStar {
            CatalogStar(id: id, ra_deg: 0, dec_deg: 0, mag: -0.5, bv: 0.0, name: "Practice Star",
                        designation: "Practice Star", distance_ly: nil, con: nil, collectible_candidate: true)
        }
    }

    private(set) var step: Step = .welcome
    private(set) var star: PracticeStar?
    /// How much of the "look around" goal is done, 0…1.
    private(set) var lookProgress: Double = 0
    /// The step's task is done: the card shows a check and waits for Continue.
    private(set) var succeeded = false
    /// The crosshair has settled on the star (Enable state).
    var isLocked = false
    var isValidating = false
    /// Camera permission or tracking failed: the find step happens in the Night Sea.
    private(set) var cameraUnavailable = false
    /// The camera button was tapped; waiting for permission and the first tracked frame.
    private(set) var cameraStarting = false

    @ObservationIgnored var actions = Actions()
    @ObservationIgnored var reduceMotion = false
    /// Where the locked star sits on screen (kept by the overlay).
    @ObservationIgnored var aimPoint: CGPoint = .zero
    @ObservationIgnored private var pendingNext: Step?
    @ObservationIgnored private var lastForward: SIMD3<Double>?
    @ObservationIgnored private var turned: Double = 0
    @ObservationIgnored private var lastCamera: NightSeaCamera?

    // MARK: Pacing

    /// The card's button.
    func primary() {
        if succeeded, let next = pendingNext { advance(to: next); return }
        switch step {
        case .welcome: advance(to: .look)
        case .camera where cameraUnavailable: findInNightSea()
        case .landed where cameraUnavailable: advance(to: .collection)
        case .collection: actions.openCollection()
        case .calendar: actions.openCalendar()
        case .ready: finish()
        default: break
        }
    }

    /// No camera: practise in the Night Sea instead.
    private func findInNightSea() {
        actions.setCamera(false)
        placeStarAhead(of: lastCamera)
        advance(to: .find)
    }

    func finish() {
        guard step != .done else { return }
        step = .done
        actions.finish()
    }

    #if DEBUG
    /// Simulator walkthrough (`-onboarding-autoplay`): does each step's action and presses Continue.
    func autoplay() async {
        while step != .done && !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2.2))
            if succeeded { primary(); continue }
            switch step {
            case .welcome, .ready: primary()
            case .look: succeed(then: .camera)
            case .camera: if cameraUnavailable { primary() } else if !cameraStarting { actions.setCamera(true) }
            case .find: if isLocked { collect(at: aimPoint) }
            case .landed: cameraUnavailable ? primary() : actions.setCamera(false)
            case .collection, .calendar: succeed(then: step == .collection ? .calendar : .ready)
            default: break
            }
        }
    }
    #endif

    // MARK: Signals from Home

    /// Every pose the user sees in the Night Sea (gyro or touch).
    func cameraChanged(_ camera: NightSeaCamera) {
        lastCamera = camera
        let forward = simd_normalize(camera.forward)
        defer { lastForward = forward }
        guard step == .look, let last = lastForward, !succeeded else { return }
        // Accumulate how far the view has travelled; ignore hand tremor and jumps.
        let delta = acos(min(1, max(-1, simd_dot(forward, last)))) * 180 / .pi
        if delta > 0.12 && delta < 20 { turned += delta }
        lookProgress = min(1, turned / 50)
        if lookProgress >= 1 { succeed(then: .camera) }
    }

    /// The garden's camera view was switched on or off (by the user's toolbar button).
    func cameraModeChanged(_ on: Bool) {
        switch step {
        case .camera where on && !cameraUnavailable:
            withAnimation(.smooth(duration: 0.35)) { cameraStarting = true }
        case .landed where !on:
            succeed(then: .collection)
        default: break
        }
    }

    /// The live camera started delivering poses.
    func liveCameraReady(_ camera: NightSeaCamera) {
        guard step == .camera, !succeeded, !cameraUnavailable else { return }
        placeStarAhead(of: camera)
        cameraStarting = false
        succeed(then: .find)
    }

    /// Camera permission denied or ARKit failed.
    func cameraFailed() {
        guard step == .camera else { return }
        withAnimation(.smooth(duration: 0.4)) { cameraUnavailable = true; cameraStarting = false }
    }

    /// Lays the practice star up and to the right of the current view, always in the sky.
    private func placeStarAhead(of camera: NightSeaCamera?) {
        let forward = simd_normalize(camera?.forward ?? SIMD3(0, 1, 0.3))
        let heading = atan2(forward.x, forward.y)
        let altitude = asin(min(1, max(-1, forward.z)))
        let degree = Double.pi / 180
        var azimuth = 24 * degree
        var h = min(max(altitude + 6 * degree, 20 * degree), 55 * degree)
        #if DEBUG
        // Screenshot aid: the star straight ahead, already in the circle.
        if ProcessInfo.processInfo.arguments.contains("-onboarding-aimed") { azimuth = 0; h = altitude }
        #endif
        let a = heading + azimuth
        star = PracticeStar(direction: SIMD3(sin(a) * cos(h), cos(a) * cos(h), sin(h)))
    }

    /// Tap anywhere while the star is locked.
    func collect(at point: CGPoint) {
        guard step == .find, isLocked, !isValidating, let star else { return }
        isValidating = true
        Task { @MainActor in
            // The crosshair's validate beat, shorter than a real optical check.
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 450))
            isValidating = false
            isLocked = false
            advance(to: .wormhole)
            actions.collect(star, point)
        }
    }

    /// Home's handover finished (album closed).
    func wormholeEnded() {
        guard step == .wormhole else { return }
        star = nil
        advance(to: .landed)
    }

    /// The collection sheet or the calendar was opened and closed again.
    func returnedFromFeature() {
        switch step {
        case .collection: succeed(then: .calendar)
        case .calendar: succeed(then: .ready)
        default: break
        }
    }

    private func succeed(then next: Step) {
        guard !succeeded else { return }
        pendingNext = next
        withAnimation(.spring(duration: 0.4, bounce: 0.3)) { succeeded = true }
    }

    private func advance(to next: Step) {
        guard next > step else { return }
        turned = 0
        pendingNext = nil
        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(duration: 0.55, bounce: 0.12)) {
            succeeded = false
            lookProgress = 0
            step = next
        }
    }

    // MARK: Copy

    struct Card: Equatable {
        var symbol: String
        var title: String
        var body: String
        var primary: String?
    }

    /// Where the card points: a real control on Home the user should press.
    enum Pointer { case cameraButton, collectionButton, calendarButton }
    var pointer: Pointer? {
        guard !succeeded else { return nil }
        switch step {
        case .camera where !cameraUnavailable && !cameraStarting: return .cameraButton
        case .landed where !cameraUnavailable: return .cameraButton
        case .collection: return .collectionButton
        case .calendar: return .calendarButton
        default: return nil
        }
    }

    var card: Card? {
        if succeeded { return successCard }
        switch step {
        case .welcome:
            return Card(symbol: "sparkles", title: "Welcome to Asterra",
                body: "Let's take a one-minute walk through the sky together. You'll try everything yourself.",
                primary: "Start the Tour")
        case .look:
            return Card(symbol: "move.3d", title: "This is your Night Sea",
                body: "Every star you collect will shine here. Move your phone around to look at it.")
        case .camera:
            if cameraUnavailable {
                return Card(symbol: "video.slash", title: "Camera is off",
                    body: "You can allow it later in Settings. Let's practise right here in the Night Sea.",
                    primary: "Continue")
            }
            if cameraStarting {
                return Card(symbol: "camera.viewfinder", title: "Opening your camera…",
                    body: "Hold your phone up toward the sky and keep it steady for a moment.")
            }
            return Card(symbol: "arkit", title: "See the real sky",
                body: "Your stars live in the real sky too. Tap the camera button in the corner to see it.")
        case .find:
            if isValidating { return Card(symbol: "hand.tap", title: "Collecting…", body: "Hold steady.") }
            if isLocked {
                return Card(symbol: "hand.tap", title: "It's in your circle",
                    body: "Now tap anywhere on the screen to collect it.")
            }
            return Card(symbol: "scope", title: "A practice star is up there",
                body: "Follow the glowing arrow, then move your phone until the star sits inside the circle.")
        case .wormhole: return nil
        case .landed:
            if cameraUnavailable {
                return Card(symbol: "checkmark.seal", title: "That's collecting",
                    body: "Every real star you collect stays in your Night Sea, in its true place.",
                    primary: "Continue")
            }
            return Card(symbol: "moon.stars", title: "That's collecting",
                body: "Every real star you collect stays in your Night Sea. Tap the same button to go back there.")
        case .collection:
            return Card(symbol: "text.book.closed", title: "Your collection",
                body: "Everything you find lands here. Tap the book at the top, or the button below.",
                primary: "Open Collection")
        case .calendar:
            return Card(symbol: "calendar", title: "Sky Calendar",
                body: "Meteor showers, eclipses and more. Tap the calendar at the top, or the button below.",
                primary: "Open Calendar")
        case .ready:
            return Card(symbol: "sparkles", title: "You're ready",
                body: "Tonight, step outside and tap Start Collecting to find your first real star.",
                primary: "Done")
        case .done: return nil
        }
    }

    private var successCard: Card {
        switch step {
        case .look:
            return Card(symbol: "checkmark", title: "Nice, you're looking around",
                body: "The Night Sea follows your phone, wherever you point it.", primary: "Continue")
        case .camera:
            return Card(symbol: "checkmark", title: "That's the real sky",
                body: "This is your camera. A practice star is waiting for you up there.", primary: "Find It")
        case .landed:
            return Card(symbol: "checkmark", title: "Back in your Night Sea",
                body: "Switch between the real sky and the Night Sea anytime with that button.", primary: "Continue")
        case .collection:
            return Card(symbol: "checkmark", title: "That's your collection",
                body: "Come back to it anytime from the book at the top.", primary: "Continue")
        case .calendar:
            return Card(symbol: "checkmark", title: "That's the Sky Calendar",
                body: "Set a reminder on any event so you never miss it.", primary: "Continue")
        default:
            return Card(symbol: "checkmark", title: "Done", body: "", primary: "Continue")
        }
    }

    var progressIndex: Int? {
        if step == .wormhole { return Step.counted.firstIndex(of: .find) }
        return Step.counted.firstIndex(of: step)
    }
}
