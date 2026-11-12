import SwiftUI
import simd

/// The first-run run-through, drawn over the live Night Sea. Practice stars are projected through the
/// garden's own camera, so they move with the gyro exactly like collected stars do. Uses the real
/// crosshair (motion, sound, haptics), the real capture flash and the garden's constellation threads.
struct OnboardingOverlay: View {
    let flow: OnboardingFlow
    let camera: NightSeaCamera

    /// More forgiving than the real camera (28 / 56 pt): this is the first thing anyone does.
    private let captureRadius: CGFloat = 38
    private let holdRadius: CGFloat = 64

    @State private var isLocking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let positions = project(in: size)
            // The aim point is the garden camera's optical centre (slightly high in touch mode).
            let center = camera.center(in: size)
            let hunting = flow.step == .first || flow.step == .more
            let candidate = hunting ? candidate(positions: positions, center: center) : nil

            ZStack {
                // A quiet veil while the wordmark speaks, lifting as the sky comes alive.
                LinearGradient(colors: [CelyxColor.night.opacity(0.85), CelyxColor.night.opacity(0.35)],
                               startPoint: .top, endPoint: .bottom)
                    .opacity(flow.step == .intro ? 1 : 0)
                    .allowsHitTesting(false)

                GardenConstellationLines(connections: flow.connections, positions: positions)
                    .opacity(flow.step >= .finale ? 0 : 1)

                ForEach(Array(flow.visibleStars.enumerated()), id: \.element.id) { index, star in
                    if let point = positions[star.id] {
                        PracticeStarView(star: star, isTarget: hunting && !star.isCollected,
                                         isLocked: flow.lockedID == star.id)
                            .position(point)
                            // Practice stars rise and dissolve one after another when the run-through ends.
                            .opacity(flow.step >= .finale ? 0 : 1)
                            .blur(radius: flow.step >= .finale ? 6 : 0)
                            .offset(y: flow.step >= .finale && !reduceMotion ? -18 : 0)
                            .animation(reduceMotion ? .easeOut(duration: 0.3)
                                : .smooth(duration: 1.4).delay(Double(index) * 0.18), value: flow.step >= .finale)
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    }
                }

                if hunting, flow.lockedID == nil, let target = guideTarget(positions: positions, size: size) {
                    OnboardingEdgeHint(angle: target.angle).position(target.point)
                        .transition(.opacity)
                }

                if hunting {
                    let lock = flow.lockedID.flatMap { positions[$0] }
                        .map { CGSize(width: $0.x - center.x, height: $0.y - center.y) } ?? .zero
                    // CrosshairView's reticle sits 10pt above its own centre (see crosshair README).
                    CrosshairView(state: crosshairState, label: flow.lockedID == nil ? "" : "Practice star")
                        .shadow(color: .black.opacity(0.35), radius: 1.5, x: 0, y: 0.5)
                        .position(x: center.x + lock.width, y: center.y + 10 + lock.height)
                        .animation(.spring(duration: 0.45, bounce: 0.12), value: flow.lockedID)
                        .allowsHitTesting(false)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }

                OnboardingFlash(shutterAt: flow.shutterAt)

                if flow.step == .intro {
                    OnboardingWordmark().transition(.blurReplace)
                }

                // Tap anywhere to collect, only while a star is locked so drags still reach the sky.
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { flow.collect() }
                    .allowsHitTesting(flow.lockedID != nil && !flow.isValidating)
                    .accessibilityHidden(true)
            }
            .frame(width: size.width, height: size.height)
            .onChange(of: candidate) { _, id in
                if id == nil || id != flow.lockedID { flow.lockedID = nil }
            }
            .task(id: candidate) {
                guard let id = candidate else { isLocking = false; return }
                if flow.lockedID == id { return }
                isLocking = true
                do { try await Task.sleep(for: .seconds(reduceMotion ? 0.25 : 0.6)) } catch { return }
                isLocking = false
                withAnimation(.smooth(duration: 0.35)) { flow.lockedID = id }
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottom) { prompt }
        .overlay(alignment: .topTrailing) {
            if flow.step < .reveal {
                Button("Skip") { flow.finish() }
                    .font(.body.weight(.medium))
                    .buttonStyle(.glass)
                    .tint(.white)
                    .padding(.trailing, 20).padding(.top, 6)
                    .transition(.opacity)
                    .accessibilityHint("Skips the introduction")
            }
        }
        .onChange(of: camera, initial: true) { _, value in flow.cameraChanged(value) }
        .onAppear { flow.reduceMotion = reduceMotion }
        .preferredColorScheme(.dark)
    }

    // MARK: Prompt

    @ViewBuilder private var prompt: some View {
        if let prompt = flow.prompt {
            Group {
                if flow.step == .lift {
                    OnboardingLiftPrompt(text: prompt.text)
                } else {
                    CameraCollectionPrompt(text: prompt.text, ready: prompt.ready)
                }
            }
            .id(prompt.text)
            .transition(reduceMotion ? AnyTransition.opacity
                : AnyTransition(BlurReplaceTransition(configuration: .downUp)).combined(with: .offset(y: 6)))
            .padding(.bottom, flow.step == .finale ? 120 : 70)
            .animation(.smooth(duration: 0.45), value: prompt.text)
        }
    }

    // MARK: Aiming

    private var crosshairState: CrosshairState {
        if flow.isValidating { return .validating }
        if flow.lockedID != nil { return .enable }
        if isLocking { return .locking }
        return .default
    }

    private func project(in size: CGSize) -> [Int: CGPoint] {
        var positions: [Int: CGPoint] = [:]
        for star in flow.stars {
            if let point = camera.project(star.direction, in: size) { positions[star.id] = point }
        }
        return positions
    }

    /// The uncollected star in the circle; a locked star keeps the lock while it stays within the hold radius.
    private func candidate(positions: [Int: CGPoint], center: CGPoint) -> Int? {
        func distance(_ id: Int) -> CGFloat {
            guard let point = positions[id] else { return .infinity }
            return hypot(point.x - center.x, point.y - center.y)
        }
        if let locked = flow.lockedID, distance(locked) <= holdRadius { return locked }
        return flow.visibleStars.filter { !$0.isCollected }.map(\.id)
            .filter { distance($0) <= captureRadius }
            .min { distance($0) < distance($1) }
    }

    /// Where to point when the nearest uncollected star is off screen: a spot on the screen edge and its bearing.
    private func guideTarget(positions: [Int: CGPoint], size: CGSize) -> (point: CGPoint, angle: Angle)? {
        let inset: CGFloat = 44
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset + 40)
        let uncollected = flow.visibleStars.filter { !$0.isCollected }
        if uncollected.contains(where: { positions[$0.id].map(bounds.contains) == true }) { return nil }
        guard let star = uncollected.first else { return nil }
        // Bearing of the star in the camera's own frame (works even when it is behind the viewer).
        let x = simd_dot(star.direction, camera.right), y = simd_dot(star.direction, camera.up)
        let angle = atan2(-y, x)
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let dx = cos(angle), dy = sin(angle)
        let sx = dx == 0 ? .infinity : (bounds.width / 2) / abs(dx)
        let sy = dy == 0 ? .infinity : (bounds.height / 2) / abs(dy)
        let s = min(sx, sy)
        return (CGPoint(x: c.x + dx * s, y: c.y + dy * s), .radians(angle))
    }
}

// MARK: - Pieces

/// A practice star: the demo star's look, beckoning with a slow ring until collected, then a bloom.
private struct PracticeStarView: View {
    let star: OnboardingFlow.PracticeStar
    let isTarget: Bool
    let isLocked: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if isTarget && !isLocked && !reduceMotion {
                // Sonar-like invitation: expands and fades on an ease-out, twice a cycle's breath.
                Circle().stroke(.white.opacity(0.55), lineWidth: 1)
                    .frame(width: 22, height: 22)
                    .phaseAnimator([false, true]) { ring, grown in
                        ring.scaleEffect(grown ? 2.6 : 0.8).opacity(grown ? 0 : 0.9)
                    } animation: { grown in grown ? .easeOut(duration: 1.6) : .linear(duration: 0.01).delay(0.5) }
            }
            DemoStarView(color: star.color)
                .scaleEffect(isTarget ? 1.15 : 0.85)
                .keyframeAnimator(initialValue: 1.0, trigger: reduceMotion ? nil : star.collectedAt) { view, bloom in
                    view.scaleEffect(bloom).brightness((bloom - 1) * 0.5)
                } keyframes: { _ in
                    KeyframeTrack {
                        SpringKeyframe(1.9, duration: 0.22, spring: .snappy)
                        SpringKeyframe(1.0, duration: 0.7, spring: .bouncy(duration: 0.7, extraBounce: 0.05))
                    }
                }
            // The collect ripple: one clean ring that leaves the star.
            if star.collectedAt != nil && !reduceMotion {
                Circle().stroke(.white, lineWidth: 1.2).frame(width: 20, height: 20)
                    .keyframeAnimator(initialValue: 0.0, trigger: star.collectedAt) { ring, t in
                        ring.scaleEffect(1 + t * 3.2).opacity(t >= 1 ? 0 : (1 - t) * 0.8)
                    } keyframes: { _ in
                        KeyframeTrack {
                            CubicKeyframe(1, duration: 0.9)
                        }
                    }
            }
        }
        .animation(.spring(duration: 0.5, bounce: 0.2), value: isTarget)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A soft chevron on the screen edge, nudging toward an off-screen star.
private struct OnboardingEdgeHint: View {
    let angle: Angle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .shadow(color: Color(red: 0.62, green: 0.77, blue: 1).opacity(0.8), radius: 6)
            .phaseAnimator([0.0, 1.0]) { view, t in
                view.offset(x: reduceMotion ? 0 : t * 6)
            } animation: { t in t == 1 ? .easeInOut(duration: 0.7) : .easeInOut(duration: 0.9) }
            .rotationEffect(angle)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Wordmark that opens the run-through.
private struct OnboardingWordmark: View {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            Text("Asterra")
                .font(.system(size: 44, weight: .semibold, design: .default)).tracking(0.5)
            Text("Collect the stars above you")
                .font(.system(size: 17)).foregroundStyle(CelyxColor.secondaryLabel)
        }
        .foregroundStyle(CelyxColor.primaryLabel)
        .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown || reduceMotion ? 1 : 0.94)
        .blur(radius: shown || reduceMotion ? 0 : 8)
        .onAppear { withAnimation(.smooth(duration: 1.1)) { shown = true } }
        .allowsHitTesting(false)
    }
}

/// "Raise your phone": the phone glyph tips up on a loop, like the gesture it asks for.
private struct OnboardingLiftPrompt: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 34, weight: .light))
                .phaseAnimator([false, true]) { phone, up in
                    phone.rotation3DEffect(.degrees(reduceMotion ? 0 : (up ? 0 : 55)), axis: (x: 1, y: 0, z: 0),
                                           perspective: 0.6)
                        .offset(y: reduceMotion ? 0 : (up ? -6 : 4))
                } animation: { up in up ? .spring(duration: 0.9, bounce: 0.15).delay(0.35) : .smooth(duration: 0.8).delay(0.6) }
            Text(text).font(.system(size: 15))
        }
        .foregroundStyle(CelyxColor.primaryLabel)
        .shadow(color: .black.opacity(0.35), radius: 1.5, x: 0, y: 0.5)
        .allowsHitTesting(false)
    }
}

/// The real capture cue's white flash (no frozen frame: the sky stays live).
private struct OnboardingFlash: View {
    let shutterAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let shutterAt, !reduceMotion {
            TimelineView(.animation(paused: Date().timeIntervalSince(shutterAt) > 0.5)) { timeline in
                let t = timeline.date.timeIntervalSince(shutterAt) * 1000
                // Softer than the camera's (the sky is dark and the user is looking right at it).
                Color.white.opacity(CaptureFlash.white(t) * 0.55)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

#Preview("Onboarding") {
    @Previewable @State var flow = OnboardingFlow()
    ZStack {
        CelyxColor.night.ignoresSafeArea()
        OnboardingOverlay(flow: flow, camera: NightSeaCamera())
    }
    .task { await flow.start() }
}
