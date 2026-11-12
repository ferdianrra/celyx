import SwiftUI
import simd

/// First-run guided tour, played inside the real Home screen: every step is the user doing the real thing.
///
/// Welcome → look around the Night Sea → turn on the camera → find a practice star through it with the
/// real crosshair → tap → the real wormhole into the Night Sea and the note sheet → back to the Night Sea
/// → the collection → the Sky Calendar → ready. The user sets the pace: each step waits for them.
/// The practice star is placed in front of wherever the user is looking (a tutorial, not a catalogue star)
/// and is never saved to the collection.
@MainActor @Observable
final class OnboardingFlow {
    enum Step: Int, Comparable, CaseIterable {
        case welcome
        /// Move the phone (or swipe) to look around the Night Sea.
        case look
        /// Turn on the camera view (asks for camera permission here, in context).
        case camera
        /// Find the practice star through the camera and tap to collect it.
        case find
        /// Shutter → wormhole → landing → note sheet (Home's real handover runs it).
        case wormhole
        /// What just happened; switch back to the virtual sky.
        case landed
        /// Open the collection sheet.
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
    /// A step's task just succeeded (checkmark beat before moving on).
    private(set) var succeeded = false
    /// The crosshair has settled on the star (Enable state).
    var isLocked = false
    var isValidating = false
    /// Camera permission or tracking failed: the find step falls back to the virtual sky.
    var cameraUnavailable = false
    /// "Turn On Camera" was tapped; waiting for permission and the first tracked frame.
    private(set) var cameraStarting = false
    /// The find step runs over the live camera (false: over the Night Sea).
    private(set) var findsInCamera = false

    @ObservationIgnored var actions = Actions()
    /// Where the locked star sits on screen (kept by the overlay).
    @ObservationIgnored var aimPoint: CGPoint = .zero
    @ObservationIgnored var reduceMotion = false
    @ObservationIgnored private var lastForward: SIMD3<Double>?
    @ObservationIgnored private var turned: Double = 0
    @ObservationIgnored private var lastCamera: NightSeaCamera?

    // MARK: Pacing

    /// The card's primary button.
    func primary() {
        switch step {
        case .welcome: advance(to: .look)
        case .camera:
            if cameraUnavailable { findInNightSea() } else {
                withAnimation(.smooth(duration: 0.35)) { cameraStarting = true }
                actions.setCamera(true)
            }
        case .landed:
            actions.setCamera(false)
            advance(to: .collection)
        case .collection: actions.openCollection()
        case .calendar: actions.openCalendar()
        case .ready: finish()
        default: break
        }
    }

    /// The card's secondary button.
    func secondary() {
        switch step {
        case .collection: advance(to: .calendar)
        case .calendar: advance(to: .ready)
        default: break
        }
    }

    /// No camera: practise in the Night Sea instead.
    private func findInNightSea() {
        actions.setCamera(false)
        findsInCamera = false
        placeStarAhead(of: lastCamera)
        advance(to: .find)
    }

    func finish() {
        guard step != .done else { return }
        step = .done
        actions.finish()
    }

    #if DEBUG
    /// Simulator walkthrough (`-onboarding-autoplay`): presses each step's button and fakes the look-around.
    func autoplay() async {
        while step != .done && !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2.2))
            switch step {
            case .welcome, .landed: primary()
            case .look: succeed(then: .camera)
            case .camera: cameraUnavailable || !cameraStarting ? primary() : ()
            case .find: if isLocked { collect(at: aimPoint) }
            case .collection, .calendar: secondary()
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

    /// The live camera started delivering poses.
    func liveCameraReady(_ camera: NightSeaCamera) {
        guard step == .camera, !succeeded, !cameraUnavailable else { return }
        findsInCamera = true
        placeStarAhead(of: camera)
        succeed(then: .find, delay: 0.7)
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
        case .collection: succeed(then: .calendar, delay: 0.6)
        case .calendar: succeed(then: .ready, delay: 0.6)
        default: break
        }
    }

    private func succeed(then next: Step, delay: Double = 0.9) {
        guard !succeeded else { return }
        withAnimation(.spring(duration: 0.4, bounce: 0.3)) { succeeded = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.3 : delay))
            advance(to: next)
        }
    }

    private func advance(to next: Step) {
        guard next > step else { return }
        turned = 0
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
        var secondary: String?
    }

    var card: Card? {
        switch step {
        case .welcome:
            return Card(symbol: "sparkles", title: "Welcome to Asterra",
                body: "Let's take a one-minute walk through the sky. You'll try everything yourself.",
                primary: "Start the Tour")
        case .look:
            return Card(symbol: "move.3d", title: "This is your Night Sea",
                body: "Every star you collect will shine here. Move your phone to look around.")
        case .camera:
            if cameraUnavailable {
                return Card(symbol: "video.slash", title: "Camera is off",
                    body: "You can allow it later in Settings. Let's practise in the Night Sea instead.",
                    primary: "Continue")
            }
            if cameraStarting {
                return Card(symbol: "camera.viewfinder", title: "Opening your camera…",
                    body: "Hold your phone up toward the sky and keep it steady for a moment.")
            }
            return Card(symbol: "camera.viewfinder", title: "See the real sky",
                body: "Your stars live in the real sky too. Turn on the camera to see them right where they are.",
                primary: "Turn On Camera")
        case .find:
            if isValidating { return Card(symbol: "hand.tap", title: "Collecting…", body: "Hold steady.") }
            if isLocked {
                return Card(symbol: "hand.tap", title: "Got it in your circle",
                    body: "Tap anywhere on the screen to collect it.")
            }
            return Card(symbol: "scope", title: findsInCamera ? "A practice star is up there" : "A star is hiding nearby",
                body: "Follow the glowing arrow, then move your phone until the star sits inside the circle.")
        case .wormhole: return nil
        case .landed:
            return Card(symbol: "checkmark.seal", title: "That's collecting",
                body: "Every real star you collect stays in your Night Sea, in its true place. This practice one was just for fun.",
                primary: "Back to the Night Sea")
        case .collection:
            return Card(symbol: "text.book.closed", title: "Your collection",
                body: "Everything you find lands here: stars, planets, constellations and sky events. Let's peek inside.",
                primary: "Open Collection")
        case .calendar:
            return Card(symbol: "calendar", title: "Sky Calendar",
                body: "Meteor showers, eclipses and more. Open it to see what's coming up in your sky.",
                primary: "Open Calendar")
        case .ready:
            return Card(symbol: "telescope", title: "You're ready",
                body: "Tonight, step outside and tap Start Collecting to find your first real star.",
                primary: "Done")
        case .done: return nil
        }
    }

    var progressIndex: Int? {
        if step == .wormhole { return Step.counted.firstIndex(of: .find) }
        return Step.counted.firstIndex(of: step)
    }
}
