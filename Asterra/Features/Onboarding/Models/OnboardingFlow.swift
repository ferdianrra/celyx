import SwiftUI
import simd

/// First-run run-through, played inside the real Night Sea: the user learns the app by doing it.
///
/// Raise the phone, aim the real crosshair at a practice star, tap to collect it, collect two more and
/// watch them join into a constellation. Practice stars are placed relative to wherever the user is
/// looking (they are a tutorial, not catalogue stars) and are never saved to the collection.
@MainActor @Observable
final class OnboardingFlow {
    enum Step: Int, Comparable {
        /// Wordmark over the dark sea.
        case intro
        /// "Raise your phone": advances once the view moves up or around.
        case lift
        /// The first star, taught slowly: aim, lock, tap.
        case first
        /// Two more stars, the user knows how now.
        case more
        /// Threads draw between the three stars.
        case reveal
        /// Practice stars dissolve; Home's controls come back.
        case finale
        case done
        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
    }

    struct PracticeStar: Identifiable, Equatable {
        /// Negative so they never collide with catalogue IDs.
        let id: Int
        /// Horizon direction [east, north, up].
        let direction: SIMD3<Double>
        let color: SIMD3<Double>
        var collectedAt: Date?
        var isCollected: Bool { collectedAt != nil }
    }

    private(set) var step: Step = .intro
    private(set) var stars: [PracticeStar] = []
    /// Threads shown between collected stars (fed to the garden's own constellation renderer).
    private(set) var connections: [GardenConstellationConnection] = []
    /// When the last shutter fired (drives the flash).
    private(set) var shutterAt: Date?
    /// The star the crosshair has settled on (Enable state); nil while searching or locking.
    var lockedID: Int?
    var isValidating = false

    @ObservationIgnored private var liftReference: SIMD3<Double>?
    @ObservationIgnored private var stepStart = Date()
    @ObservationIgnored var reduceMotion = false
    @ObservationIgnored var onFinish: () -> Void = {}

    /// The first star is taught alone; the other two appear once it is collected.
    var visibleStars: [PracticeStar] { step <= .first ? Array(stars.prefix(1)) : stars }
    var remaining: Int { stars.filter { !$0.isCollected }.count }
    var target: PracticeStar? { stars.first { !$0.isCollected } }

    // MARK: Script

    func start() async {
        step = .intro
        stepStart = Date()
        do { try await Task.sleep(for: .seconds(reduceMotion ? 1.6 : 3.0)) } catch { return }
        advance(to: .lift)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-onboarding-autoplay") { Task { await autoplay() } }
        #endif
        // A still sky (no gyro, or a phone lying on a table) still gets re-checked.
        while step == .lift && !Task.isCancelled {
            if let lastCamera { cameraChanged(lastCamera) }
            try? await Task.sleep(for: .milliseconds(300))
        }
    }

    @ObservationIgnored private var lastCamera: NightSeaCamera?

    #if DEBUG
    /// Simulator walkthrough: collects each practice star without aiming (`-onboarding-autoplay`).
    private func autoplay() async {
        while step < .reveal && !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1.6))
            if (step == .first || step == .more), !isValidating, let target {
                lockedID = target.id
                try? await Task.sleep(for: .seconds(0.8))
                collect()
            }
        }
    }
    #endif

    /// Fed by the view on every camera change.
    func cameraChanged(_ camera: NightSeaCamera) {
        lastCamera = camera
        guard step == .lift else { return }
        let forward = simd_normalize(camera.forward)
        guard let reference = liftReference else { liftReference = forward; return }
        // Give the prompt a moment to be read, then advance on a clear look up or around.
        guard Date().timeIntervalSince(stepStart) > 1.1 else { return }
        let turned = acos(min(1, max(-1, simd_dot(forward, reference)))) * 180 / .pi
        let altitude = asin(min(1, max(-1, forward.z))) * 180 / .pi
        // Without a gyro (touch mode) a drag of the sky counts, and a patient wait does too.
        let waited = Date().timeIntervalSince(stepStart)
        if turned > 14 || (altitude > 20 && waited > 2.2) || (camera.orientation == nil && waited > 4) {
            placeStars(around: forward)
            advance(to: .first)
        }
    }

    /// Lays out a small three-star pattern up and to the right of the current view.
    private func placeStars(around forward: SIMD3<Double>) {
        let heading = atan2(forward.x, forward.y)
        let altitude = asin(min(1, max(-1, forward.z)))
        let degree = Double.pi / 180
        // Keep the pattern well inside the sky (never on the sea), whatever the phone is doing.
        let base = min(max(altitude + 8 * degree, 22 * degree), 52 * degree)
        func direction(_ az: Double, _ alt: Double) -> SIMD3<Double> {
            let a = heading + az * degree, h = base + alt * degree
            return SIMD3(sin(a) * cos(h), cos(a) * cos(h), sin(h))
        }
        var first = 22.0
        #if DEBUG
        // Screenshot aid: the first star right in the circle.
        if ProcessInfo.processInfo.arguments.contains("-onboarding-aimed") { first = 0 }
        #endif
        stars = [
            PracticeStar(id: -1, direction: first == 0 ? forward : direction(first, 0), color: SIMD3(0.78, 0.86, 1)),
            PracticeStar(id: -2, direction: direction(36, 9), color: SIMD3(1, 0.93, 0.80)),
            PracticeStar(id: -3, direction: direction(27, 21), color: SIMD3(0.86, 0.90, 1)),
        ]
        connections = []
    }

    /// Tap anywhere while a star is locked.
    func collect() {
        guard let id = lockedID, !isValidating, let index = stars.firstIndex(where: { $0.id == id }),
            !stars[index].isCollected
        else { return }
        isValidating = true
        Task { @MainActor in
            // The crosshair's validate beat, shorter than a real optical check.
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 420))
            if !reduceMotion { WormholeFeedback.shared.playShutter() }
            CrosshairFeedback.shared.suppress(.back, for: 0.8)
            CrosshairFeedback.shared.play(CrosshairSound.collect)
            CrosshairFeedback.shared.play(CrosshairHaptic.collect)
            // Thread from the star collected just before this one, in the order the user found them.
            let previous = stars.filter(\.isCollected).max { ($0.collectedAt ?? .distantPast) < ($1.collectedAt ?? .distantPast) }
            shutterAt = Date()
            stars[index].collectedAt = Date()
            lockedID = nil
            isValidating = false
            if let previous {
                pendingThreads.append(GardenConstellationConnection(
                    constellation: "practice", startID: previous.id, endID: stars[index].id))
            }
            if step == .first {
                try? await Task.sleep(for: .seconds(reduceMotion ? 0.4 : 1.1))
                advance(to: .more)
            } else if remaining == 0 {
                try? await Task.sleep(for: .seconds(reduceMotion ? 0.3 : 0.9))
                await reveal()
            }
        }
    }

    /// Threads wait until the last star lands, then draw together, like the real constellation reveal.
    @ObservationIgnored private var pendingThreads: [GardenConstellationConnection] = []

    private func reveal() async {
        advance(to: .reveal)
        for thread in pendingThreads {
            connections.append(thread)
            WormholeFeedback.shared.playSheet()
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.1 : 0.55))
        }
        pendingThreads = []
        try? await Task.sleep(for: .seconds(reduceMotion ? 1.6 : 3.0))
        advance(to: .finale)
        try? await Task.sleep(for: .seconds(reduceMotion ? 1.8 : 3.2))
        finish()
    }

    func finish() {
        guard step != .done else { return }
        advance(to: .done)
        onFinish()
    }

    private func advance(to next: Step) {
        guard next > step else { return }
        stepStart = Date()
        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .smooth(duration: 0.55)) { step = next }
    }

    // MARK: Prompt

    var prompt: (text: String, ready: Bool)? {
        switch step {
        case .intro, .done: return nil
        case .lift: return ("Raise your phone to the sky", false)
        case .first, .more:
            if isValidating { return ("Collecting…", true) }
            if lockedID != nil { return ("Tap anywhere to collect", true) }
            if step == .first { return ("Put the star in your circle", false) }
            return (remaining == 1 ? "One more. Find it" : "Two more are nearby. Collect them", false)
        case .reveal: return ("Your stars connect into constellations", false)
        case .finale: return ("Now find a real one tonight", false)
        }
    }
}
