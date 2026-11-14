import SwiftUI
import simd

/// First-run tour: try a visible real sky object before offering a virtual practice star.
@MainActor @Observable
final class OnboardingFlow {
    enum Step: Int, Comparable, CaseIterable {
        case welcome
        /// Move the phone (or swipe) to look around the Night Sea.
        case look
        /// Tap the toolbar's camera button (camera permission is asked here, in context).
        case camera
        /// Ask whether the suggested real sky object is visible.
        case visibility
        /// Collect a real object, or a virtual star only after choosing the fallback.
        case find
        /// Shutter → wormhole → landing → note sheet (Home's real handover runs it).
        case wormhole
        case done
        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
        /// Steps counted in the progress dots.
        static let counted: [Step] = [.look, .camera, .find]
    }

    /// What the tour asks Home to do (Home owns the real state).
    struct Actions {
        var setCamera: (Bool) -> Void = { _ in }
        /// Start the real capture + wormhole for the practice star at this screen point.
        var collect: (_ star: PracticeStar, _ point: CGPoint) -> Void = { _, _ in }
        var findRealObject: () -> Void = {}
        var cancel: () -> Void = {}
        var finish: () -> Void = {}
    }

    struct PracticeStar: Identifiable, Equatable {
        /// Well outside the catalogue's IDs (and the Sun/Moon's negative ones).
        let id = 990_001
        /// Horizon direction [east, north, up].
        let direction: SIMD3<Double>
        let color = SIMD3(0.80, 0.88, 1.0)
        var catalogStar: CatalogStar {
            CatalogStar(id: id, ra_deg: 0, dec_deg: 0, mag: -0.5, bv: 0.0, name: OnboardingCopy.practiceStarName,
                        designation: OnboardingCopy.practiceStarName, distance_ly: nil, con: nil, collectible_candidate: true)
        }
    }

    private(set) var step: Step = .welcome
    private(set) var star: PracticeStar?
    private(set) var isDaytime = true
    var isFindingRealObject: Bool { step == .find && star == nil }

    /// Prefer local solar altitude; use the local clock until location is available.
    func updateSky(sunAltitude: Double?, date: Date = Date(), calendar: Calendar = .current) {
        guard step <= .visibility else { return }
        if let sunAltitude, sunAltitude.isFinite {
            isDaytime = sunAltitude >= 0
        } else {
            isDaytime = (6..<18).contains(calendar.component(.hour, from: date))
        }
    }

    func answerVisibility(canSeeObject: Bool) {
        guard step == .visibility else { return }
        if canSeeObject {
            star = nil
            advance(to: .find)
            actions.findRealObject()
        } else {
            useVirtualStar()
        }
    }

    func useVirtualStar() {
        guard step == .visibility || isFindingRealObject else { return }
        isLocked = false
        placeStarAhead(of: lastCamera)
        advance(to: .find)
    }

    func realCameraClosed() {
        guard isFindingRealObject else { return }
        // Closing before collection returns to the visibility choice so the tour cannot get stuck.
        step = .visibility
    }

    func realObjectCollected() {
        guard isFindingRealObject else { return }
        advance(to: .wormhole)
    }
    /// How much of the "look around" goal is done, 0…1.
    private(set) var lookProgress: Double = 0
    /// The step's task is done: the card shows a check and waits for Continue.
    private(set) var succeeded = false
    /// The crosshair has settled on the star (Enable state).
    var isLocked = false
    var isValidating = false
    /// Camera permission or tracking failed: the find step happens in the Night Sea.
    private(set) var cameraUnavailable = false
    enum CameraFailure: Equatable {
        case permissionDenied
        case timedOut
        case capture(String)
    }
    private(set) var cameraFailure: CameraFailure?
    /// The camera button was tapped; waiting for permission and the first tracked frame.
    private(set) var cameraStarting = false

    @ObservationIgnored var actions = Actions()
    @ObservationIgnored var reduceMotion = false
    /// Where the locked star sits on screen (kept by the overlay).
    @ObservationIgnored var aimPoint: CGPoint = .zero
    @ObservationIgnored private var validationTask: Task<Void, Never>?
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
        case .camera where cameraUnavailable:
            if cameraFailure == .permissionDenied { findInNightSea() }
            else {
                cameraUnavailable = false
                cameraFailure = nil
                cameraStarting = true
                actions.setCamera(true)
            }
        case .visibility: answerVisibility(canSeeObject: true)
        default: break
        }
    }

    func secondary() {
        if step == .camera, cameraUnavailable { findInNightSea() }
        else { answerVisibility(canSeeObject: false) }
    }

    /// No camera: practise in the Night Sea instead.
    private func findInNightSea() {
        actions.setCamera(false)
        placeStarAhead(of: lastCamera)
        advance(to: .find)
    }

    func finish() {
        guard step != .done else { return }
        validationTask?.cancel()
        validationTask = nil
        pendingNext = nil
        succeeded = false
        isValidating = false
        isLocked = false
        cameraStarting = false
        star = nil
        step = .done
        actions.finish()
    }

    func skip() {
        guard step != .done else { return }
        finish()
        actions.cancel()
    }

    #if DEBUG
    /// Simulator walkthrough (`-onboarding-autoplay`): does each step's action and presses Continue.
    func autoplay() async {
        while step != .done && !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(2.2)) } catch { return }
            guard step != .done, !Task.isCancelled else { return }
            if startsFindWithStartCollecting { _ = startCollectingPressed(); continue }
            if succeeded { primary(); continue }
            switch step {
            case .welcome: primary()
            case .look: succeed(then: .camera)
            case .camera: if cameraUnavailable { primary() } else if !cameraStarting { actions.setCamera(true) }
            case .visibility: answerVisibility(canSeeObject: false)
            case .find: if isLocked { collect(at: aimPoint) }
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
        lookProgress = min(1, turned / 240)
        if lookProgress >= 1 { succeed(then: .camera) }
    }

    /// The garden's camera view was switched on or off (by the user's toolbar button).
    func cameraModeChanged(_ on: Bool) {
        switch step {
        case .camera where on && !cameraUnavailable:
            withAnimation(.smooth(duration: 0.35)) { cameraStarting = true }
        default: break
        }
    }

    /// The live camera started delivering poses.
    func liveCameraReady(_ camera: NightSeaCamera?) {
        guard step == .camera, !succeeded, !cameraUnavailable else { return }
        if let camera { lastCamera = camera }
        cameraStarting = false
        succeed(then: .visibility)
    }

    /// Only a confirmed denial should direct the user to camera permissions in Settings.
    func cameraFailed(_ reason: CameraFailure = .permissionDenied) {
        guard step == .camera else { return }
        withAnimation(.smooth(duration: 0.4)) {
            succeeded = false
            pendingNext = nil
            cameraFailure = reason
            cameraUnavailable = true
            cameraStarting = false
        }
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
        validationTask = Task { @MainActor in
            // The crosshair's validate beat, shorter than a real optical check.
            do { try await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 450)) } catch { return }
            guard !Task.isCancelled, step == .find, isValidating else { return }
            isValidating = false
            isLocked = false
            advance(to: .wormhole)
            actions.collect(star, point)
        }
    }

    /// Finishing the note is the end of the tour; closing its album also exits cleanly.
    func noteCompleted() {
        guard step == .wormhole else { return }
        star = nil
        finish()
    }

    func wormholeEnded() { noteCompleted() }

    private func succeed(then next: Step) {
        guard step != .done, !succeeded else { return }
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
        var secondary: String? = nil
    }

    /// Where the card points: a real control on Home the user should press.
    enum Pointer: Hashable { case cameraButton, startCollecting }
    var pointer: Pointer? {
        if startsFindWithStartCollecting { return .startCollecting }
        guard !succeeded else { return nil }
        switch step {
        case .camera where !cameraUnavailable && !cameraStarting: return .cameraButton
        default: return nil
        }
    }

    /// The camera is ready; Start Collecting opens the visibility choice.
    var startsFindWithStartCollecting: Bool { step == .camera && succeeded }

    /// During the camera step, Start Collecting opens the real-sky visibility choice.
    /// Returns true when the tour handled the press.
    func startCollectingPressed() -> Bool {
        switch step {
        case .camera where succeeded:
            advance(to: .visibility); return true
        default:
            return step != .done
        }
    }

    #if DEBUG
    /// Screenshot aid (`-onboarding-step=<name>`).
    func jump(to name: String) {
        guard let target = Step.allCases.first(where: { "\($0)" == name }) else { return }
        step = target
    }
    #endif

    var card: Card? {
        if succeeded { return successCard }
        switch step {
        case .welcome:
            return Card(symbol: "sparkles", title: OnboardingCopy.welcomeTitle, body: OnboardingCopy.welcomeBody,
                primary: OnboardingCopy.startTour)
        case .look:
            return Card(symbol: "move.3d", title: OnboardingCopy.lookTitle, body: OnboardingCopy.lookBody)
        case .camera:
            if cameraUnavailable {
                if cameraFailure == .permissionDenied {
                    return Card(symbol: "video.slash", title: OnboardingCopy.cameraUnavailableTitle,
                        body: OnboardingCopy.cameraUnavailableBody, primary: OnboardingCopy.continueTour)
                }
                let body: String
                if case .capture(let message) = cameraFailure {
                    body = message + " " + OnboardingCopy.cameraRetryBody
                } else { body = OnboardingCopy.cameraTimeoutBody }
                return Card(symbol: "camera.badge.ellipsis", title: OnboardingCopy.cameraRetryTitle,
                    body: body, primary: OnboardingCopy.retryCamera, secondary: OnboardingCopy.practiceWithoutCamera)
            }
            if cameraStarting {
                return Card(symbol: "camera.viewfinder", title: OnboardingCopy.cameraStartingTitle, body: OnboardingCopy.cameraStartingBody)
            }
            return Card(symbol: "arkit", title: OnboardingCopy.cameraTitle, body: OnboardingCopy.cameraBody)
        case .visibility:
            return Card(symbol: isDaytime ? "sun.max" : "moon.stars",
                title: isDaytime ? OnboardingCopy.dayVisibilityTitle : OnboardingCopy.nightVisibilityTitle,
                body: isDaytime ? OnboardingCopy.dayVisibilityBody : OnboardingCopy.nightVisibilityBody,
                primary: OnboardingCopy.canSeeObject, secondary: OnboardingCopy.cannotSeeObject)
        case .find:
            if isValidating { return Card(symbol: "hand.tap", title: OnboardingCopy.collectingTitle, body: OnboardingCopy.collectingBody) }
            if isLocked {
                return Card(symbol: "hand.tap", title: OnboardingCopy.starLockedTitle, body: OnboardingCopy.starLockedBody)
            }
            return Card(symbol: "scope", title: OnboardingCopy.findStarTitle, body: OnboardingCopy.findStarBody)
        case .wormhole: return nil
        case .done: return nil
        }
    }

    private var successCard: Card {
        switch step {
        case .look:
            return Card(symbol: "checkmark", title: OnboardingCopy.lookSuccessTitle, body: OnboardingCopy.lookSuccessBody, primary: OnboardingCopy.continueTour)
        case .camera:
            return Card(symbol: "checkmark", title: OnboardingCopy.cameraSuccessTitle, body: OnboardingCopy.cameraSuccessBody)
        default:
            return Card(symbol: "checkmark", title: OnboardingCopy.doneTitle, body: OnboardingCopy.doneBody, primary: OnboardingCopy.continueTour)
        }
    }

    var progressIndex: Int? {
        if step == .wormhole || step == .visibility { return Step.counted.firstIndex(of: .find) }
        return Step.counted.firstIndex(of: step)
    }
}
