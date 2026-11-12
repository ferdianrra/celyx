import SwiftUI
import simd

/// The guided tour drawn over Home. Native Liquid Glass coach cards set the pace; the practice star is
/// projected through whichever camera the user is looking through (the Night Sea's or the live AR camera),
/// so it moves exactly like collected stars do. The real crosshair (motion, sound, haptics) does the aiming.
struct OnboardingOverlay: View {
    let flow: OnboardingFlow
    /// The camera the user is looking through right now.
    let camera: NightSeaCamera
    /// Home's toolbars are showing (keep the card above the bottom bar).
    var chromeVisible = false

    /// More forgiving than the real camera (28 / 56 pt): this is the first thing anyone collects.
    private let captureRadius: CGFloat = 40
    private let holdRadius: CGFloat = 66

    @State private var isLocking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let center = camera.center(in: size)
            let point = flow.star.flatMap { camera.project($0.direction, in: size) }
            let hunting = flow.step == .find
            let distance = point.map { hypot($0.x - center.x, $0.y - center.y) } ?? .infinity
            let inCircle = hunting && distance <= (flow.isLocked ? holdRadius : captureRadius)

            ZStack {
                // A gentle veil behind the welcome, so the words sit on a calm sky.
                LinearGradient(colors: [CelyxColor.night.opacity(0.75), CelyxColor.night.opacity(0.15),
                                        CelyxColor.night.opacity(0.7)],
                               startPoint: .top, endPoint: .bottom)
                    .opacity(flow.step == .welcome ? 1 : 0)
                    .allowsHitTesting(false)

                if hunting, let star = flow.star {
                    if let point {
                        PracticeStarView(star: star, isLocked: flow.isLocked).position(point)
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    }
                    if !flow.isLocked, let hint = edgeHint(for: star, point: point, size: size) {
                        OnboardingEdgeHint(angle: hint.angle).position(hint.point).transition(.opacity)
                    }
                    let lock = flow.isLocked
                        ? point.map { CGSize(width: $0.x - center.x, height: $0.y - center.y) } ?? .zero : .zero
                    // CrosshairView's reticle sits 10pt above its own centre (see crosshair README).
                    CrosshairView(state: crosshairState, label: flow.isLocked ? star.catalogStar.title : "")
                        .shadow(color: .black.opacity(0.35), radius: 1.5, x: 0, y: 0.5)
                        .position(x: center.x + lock.width, y: center.y + 10 + lock.height)
                        .animation(.spring(duration: 0.45, bounce: 0.12), value: flow.isLocked)
                        .allowsHitTesting(false)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }

                if flow.step == .welcome {
                    OnboardingWordmark().offset(y: -size.height * 0.12)
                        .transition(.blurReplace)
                }

                if flow.step == .collection || flow.step == .calendar {
                    // Where the feature lives in the toolbar, so the user can find it again later.
                    OnboardingToolbarPointer()
                        .position(x: size.width - (flow.step == .collection ? 78 : 36),
                                  y: geometry.safeAreaInsets.top + 64)
                        .transition(.opacity)
                }

                // Tap anywhere to collect, only while the star is locked so swipes still reach the sky.
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { flow.collect(at: point ?? center) }
                    .allowsHitTesting(flow.isLocked && !flow.isValidating)
                    .accessibilityHidden(true)
            }
            .frame(width: size.width, height: size.height)
            .onChange(of: point) { _, value in if let value { flow.aimPoint = value } }
            .onChange(of: inCircle) { _, inside in if !inside { flow.isLocked = false } }
            .task(id: inCircle) {
                guard inCircle, !flow.isLocked else { isLocking = false; return }
                isLocking = true
                do { try await Task.sleep(for: .seconds(reduceMotion ? 0.25 : 0.6)) } catch { return }
                isLocking = false
                withAnimation(.smooth(duration: 0.35)) { flow.isLocked = true }
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            if let card = flow.card {
                OnboardingCard(card: card, flow: flow)
                    .padding(.horizontal, 16)
                    .padding(.bottom, chromeVisible ? 76 : 12)
                    .transition(reduceMotion ? .opacity
                        : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                      removal: .opacity.combined(with: .scale(scale: 0.96))))
            }
        }
        .overlay(alignment: .topTrailing) {
            if flow.step < .ready && flow.step != .wormhole && !chromeVisible {
                Button("Skip Tour") { flow.finish() }
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.glass)
                    .tint(.white)
                    .padding(.trailing, 16).padding(.top, 4)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(duration: 0.5, bounce: 0.12), value: flow.step)
        .onAppear { flow.reduceMotion = reduceMotion }
        .preferredColorScheme(.dark)
    }

    private var crosshairState: CrosshairState {
        if flow.isValidating { return .validating }
        if flow.isLocked { return .enable }
        if isLocking { return .locking }
        return .default
    }

    /// When the star is off screen: a spot on the screen edge and the bearing toward it.
    private func edgeHint(for star: OnboardingFlow.PracticeStar, point: CGPoint?, size: CGSize)
        -> (point: CGPoint, angle: Angle)?
    {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 40, dy: 120)
        if let point, bounds.contains(point) { return nil }
        // Bearing in the camera's own frame (works even when the star is behind the viewer).
        let x = simd_dot(star.direction, camera.right), y = simd_dot(star.direction, camera.up)
        let angle = atan2(-y, x)
        let dx = cos(angle), dy = sin(angle)
        let s = min(dx == 0 ? .infinity : (bounds.width / 2) / abs(dx),
                    dy == 0 ? .infinity : (bounds.height / 2) / abs(dy))
        return (CGPoint(x: bounds.midX + dx * s, y: bounds.midY + dy * s), .radians(angle))
    }
}

// MARK: - Coach card

/// One step of the tour: native Liquid Glass, an SF Symbol, a title, one sentence and the action.
private struct OnboardingCard: View {
    let card: OnboardingFlow.Card
    let flow: OnboardingFlow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let index = flow.progressIndex {
                OnboardingProgressDots(index: index, count: OnboardingFlow.Step.counted.count)
            }
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: flow.succeeded ? "checkmark.circle.fill" : card.symbol)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(flow.succeeded ? CelyxColor.ready : CelyxColor.primaryLabel)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: flow.succeeded)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.title).font(.headline)
                    Text(card.body).font(.subheadline).foregroundStyle(CelyxColor.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(card.title)
                .transition(.blurReplace)
            }
            if flow.step == .look {
                ProgressView(value: flow.lookProgress)
                    .tint(flow.succeeded ? CelyxColor.ready : .white)
                    .animation(.smooth(duration: 0.3), value: flow.lookProgress)
            }
            if card.primary != nil || card.secondary != nil {
                HStack(spacing: 10) {
                    if let secondary = card.secondary {
                        Button(secondary) { flow.secondary() }
                            .buttonStyle(.glass)
                            .controlSize(.large)
                    }
                    if let primary = card.primary {
                        Button { flow.primary() } label: {
                            Text(primary).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(CelyxColor.primary)
                        .controlSize(.large)
                    }
                }
                .font(.body.weight(.semibold))
            }
        }
        .foregroundStyle(CelyxColor.primaryLabel)
        .padding(20)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .animation(.spring(duration: 0.45, bounce: 0.1), value: card)
        .sensoryFeedback(.success, trigger: flow.succeeded) { _, new in new }
    }
}

private struct OnboardingProgressDots: View {
    let index: Int
    let count: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(i <= index ? 0.95 : 0.25))
                    .frame(width: i == index ? 18 : 6, height: 6)
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.2), value: index)
        .accessibilityElement()
        .accessibilityLabel("Step \(index + 1) of \(count)")
    }
}

// MARK: - Pieces

/// The practice star: the demo star's look, with a slow sonar ring inviting the user until it locks.
private struct PracticeStarView: View {
    let star: OnboardingFlow.PracticeStar
    let isLocked: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !isLocked && !reduceMotion {
                Circle().stroke(.white.opacity(0.6), lineWidth: 1)
                    .frame(width: 22, height: 22)
                    .phaseAnimator([false, true]) { ring, grown in
                        ring.scaleEffect(grown ? 2.8 : 0.8).opacity(grown ? 0 : 0.9)
                    } animation: { grown in grown ? .easeOut(duration: 1.6) : .linear(duration: 0.01).delay(0.5) }
            }
            DemoStarView(color: star.color).scaleEffect(isLocked ? 1.3 : 1.15)
        }
        .animation(.spring(duration: 0.5, bounce: 0.25), value: isLocked)
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
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.white.opacity(0.95))
            .shadow(color: Color(red: 0.62, green: 0.77, blue: 1).opacity(0.9), radius: 8)
            .phaseAnimator([0.0, 1.0]) { view, t in
                view.offset(x: reduceMotion ? 0 : t * 7)
            } animation: { t in t == 1 ? .easeInOut(duration: 0.7) : .easeInOut(duration: 0.9) }
            .rotationEffect(angle)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Bobbing arrow toward a toolbar button.
private struct OnboardingToolbarPointer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Image(systemName: "arrow.up")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: Color(red: 0.62, green: 0.77, blue: 1).opacity(0.9), radius: 8)
            .phaseAnimator([0.0, 1.0]) { view, t in view.offset(y: reduceMotion ? 0 : -t * 6) }
                animation: { _ in .easeInOut(duration: 0.75) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Wordmark that opens the tour.
private struct OnboardingWordmark: View {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            Text("Asterra").font(.system(size: 48, weight: .semibold)).tracking(0.5)
            Text("Collect the stars above you").font(.title3).foregroundStyle(CelyxColor.secondaryLabel)
        }
        .foregroundStyle(CelyxColor.primaryLabel)
        .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown || reduceMotion ? 1 : 0.94)
        .blur(radius: shown || reduceMotion ? 0 : 8)
        .onAppear { withAnimation(.smooth(duration: 1.2).delay(0.2)) { shown = true } }
        .allowsHitTesting(false)
    }
}

#Preview("Onboarding") {
    @Previewable @State var flow = OnboardingFlow()
    ZStack {
        CelyxColor.night.ignoresSafeArea()
        OnboardingOverlay(flow: flow, camera: NightSeaCamera())
    }
}
