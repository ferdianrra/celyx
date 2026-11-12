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

                if let pointer = flow.pointer, chromeVisible {
                    // Spotlight on the real toolbar control the card asks for.
                    let target = pointerTarget(pointer, size: size)
                    OnboardingSpotlight().position(target.center).transition(.opacity)
                    OnboardingToolbarPointer(up: target.below)
                        .position(x: target.center.x, y: target.center.y + (target.below ? 44 : -46))
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
                    .padding(.bottom, chromeVisible ? 66 : 12)
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

    /// Where Home's toolbar controls sit (native toolbar layout, from the window's safe area).
    private func pointerTarget(_ pointer: OnboardingFlow.Pointer, size: CGSize) -> (center: CGPoint, below: Bool) {
        let insets = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets ?? .zero
        switch pointer {
        case .cameraButton: return (CGPoint(x: size.width - 48, y: size.height - insets.bottom - 19), false)
        case .collectionButton: return (CGPoint(x: size.width - 100, y: insets.top + 22), true)
        case .calendarButton: return (CGPoint(x: size.width - 45, y: insets.top + 22), true)
        }
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

/// One step of the tour: native Liquid Glass, a title with its symbol, one sentence and the action,
/// with the same tinted-glass primary button as Start Collecting.
private struct OnboardingCard: View {
    let card: OnboardingFlow.Card
    let flow: OnboardingFlow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let index = flow.progressIndex {
                OnboardingProgressDots(index: index, count: OnboardingFlow.Step.counted.count)
                    .padding(.bottom, 18)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: flow.succeeded ? "checkmark.circle.fill" : card.symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(flow.succeeded ? CelyxColor.ready : Color(red: 0.72, green: 0.82, blue: 1))
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: flow.succeeded)
                        .frame(width: 26)
                    Text(card.title).font(.title3.weight(.semibold))
                }
                Text(card.body).font(.body).foregroundStyle(CelyxColor.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(card.title)
            .transition(.blurReplace)
            if flow.step == .look && !flow.succeeded {
                ProgressView(value: flow.lookProgress)
                    .tint(.white)
                    .animation(.smooth(duration: 0.3), value: flow.lookProgress)
                    .padding(.top, 18)
            }
            if let primary = card.primary {
                Button { flow.primary() } label: {
                    Text(primary).font(.system(size: 17, weight: .semibold)).tracking(-0.43)
                        .foregroundStyle(CelyxColor.primaryLabel)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .contentShape(Capsule())
                }
                .buttonStyle(CelyxTintedGlassButtonStyle())
                .padding(.top, 20)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .foregroundStyle(CelyxColor.primaryLabel)
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, card.primary == nil ? 22 : 16)
        .glassEffect(.regular.tint(CelyxColor.night.opacity(0.35)), in: RoundedRectangle(cornerRadius: 34, style: .continuous))
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
    var up = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Image(systemName: up ? "arrow.up" : "arrow.down")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: Color(red: 0.62, green: 0.77, blue: 1).opacity(0.9), radius: 8)
            .phaseAnimator([0.0, 1.0]) { view, t in view.offset(y: reduceMotion ? 0 : (up ? -t : t) * 6) }
                animation: { _ in .easeInOut(duration: 0.75) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A soft ring breathing around the control to press.
private struct OnboardingSpotlight: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Circle().stroke(Color(red: 0.72, green: 0.82, blue: 1), lineWidth: 2)
            .frame(width: 60, height: 60)
            .shadow(color: Color(red: 0.62, green: 0.77, blue: 1), radius: 8)
            .phaseAnimator([false, true]) { ring, out in
                ring.scaleEffect(reduceMotion ? 1 : (out ? 1.18 : 0.98)).opacity(out ? 0.35 : 0.95)
            } animation: { _ in .easeInOut(duration: 1.0) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#Preview("Onboarding") {
    @Previewable @State var flow = OnboardingFlow()
    ZStack {
        CelyxColor.night.ignoresSafeArea()
        OnboardingOverlay(flow: flow, camera: NightSeaCamera())
    }
}
