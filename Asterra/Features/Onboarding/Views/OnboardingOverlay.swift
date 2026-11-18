import SwiftUI
import simd

/// The guided tour drawn over Home. Native Liquid Glass coach cards set the pace; the practice star is
/// projected through whichever camera the user is looking through (the Night Sea's or the live AR camera),
/// so it moves exactly like collected stars do. The real crosshair (motion, sound, haptics) does the aiming.
/// Keep high-frequency camera observations inside this small layer, outside Home's body.
struct OnboardingCameraOverlay: View {
    let flow: OnboardingFlow
    let camera: NightSeaCamera
    let liveCamera: LiveCameraLink?
    var chromeVisible = false
    var topBarVisible = false

    var body: some View {
        OnboardingOverlay(flow: flow, camera: shownCamera,
            chromeVisible: chromeVisible, topBarVisible: topBarVisible)
    }
    private var shownCamera: NightSeaCamera {
        if let camera = flow.gardenCamera { return camera }
        #if DEBUG
        // Aim the simulator camera at the calculated Sun, without moving the Sun itself.
        if ProcessInfo.processInfo.arguments.contains("-ui-testing"),
           ProcessInfo.processInfo.arguments.contains("-onboarding-aimed"),
           let star = flow.star, star.isSun {
            var aimed = NightSeaCamera()
            aimed.azimuth = atan2(star.direction.x, star.direction.y)
            aimed.altitude = asin(star.direction.z)
            return aimed
        }
        #endif
        return liveCamera?.pose ?? camera
    }
}

struct OnboardingOverlay: View {
    let flow: OnboardingFlow
    /// The camera the user is looking through right now.
    let camera: NightSeaCamera
    /// Home's bottom bar is showing (keep the card just above it).
    var chromeVisible = false
    /// Home's top bar is showing (the Skip button steps aside).
    var topBarVisible = false

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
                            .transaction { $0.animation = nil }
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

                if flow.step == .garden, let direction = flow.gardenDirection,
                    let point = camera.project(direction, in: size) {
                    VStack(spacing: 10) {
                        Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5)
                            .frame(width: 54, height: 54)
                            .background { OnboardingHighlight(size: CGSize(width: 38, height: 38), haptics: false) }
                        Text(flow.star?.isSun == true ? "Your Sun" : flow.isTemporaryPractice ? "Your practice star" : "Your discovery")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(CelyxColor.night.opacity(0.85), in: Capsule())
                    }
                    // The ring is centered on the actual rendered star, above the coach card.
                    .position(x: point.x, y: point.y + 23)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("tour-garden-star-highlight")
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
                guard flow.step == .find, flow.star != nil, !Task.isCancelled else { return }
                isLocking = false
                withAnimation(.smooth(duration: 0.35)) { flow.isLocked = true }
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            if let card = flow.card {
                OnboardingCard(card: card, flow: flow)
                    .id(flow.step)
                    .padding(.horizontal, 16)
                    .padding(.bottom, chromeVisible ? 67 : 12)
                    .transition(reduceMotion || flow.step == .garden ? .opacity
                        : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                      removal: .opacity.combined(with: .scale(scale: 0.96))))
            }
        }
        .overlay(alignment: .topTrailing) {
            if flow.step < .wormhole && !chromeVisible && !topBarVisible {
                Button(OnboardingCopy.skipTour) { flow.skip() }
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.glass)
                    .tint(.white)
                    .padding(.trailing, 16).padding(.top, 4)
                    .transition(.opacity)
            }
        }
        .overlay {
            if flow.step == .completion {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    OnboardingCompletionCard(isPractice: flow.isTemporaryPractice) { flow.finish() }
                        .padding(20)
                }
                .accessibilityAddTraits(.isModal)
            }
        }
        .overlay(alignment: .topLeading) {
            if flow.canGoBack && flow.step != .note && flow.step != .completion {
                Button("Back", systemImage: "chevron.left") { flow.back() }
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.glass).tint(.white)
                    .padding(.leading, 16).padding(.top, topBarVisible ? 58 : 4)
                    .accessibilityIdentifier("tour-back")
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

    /// Keep the direction cue close to the fixed reticle until the target is near enough to lock.
    /// Once the target is visible, use its projected point for a precise screen-space bearing.
    private func edgeHint(for star: OnboardingFlow.PracticeStar, point: CGPoint?, size: CGSize)
        -> (point: CGPoint, angle: Angle)?
    {
        let center = camera.center(in: size)
        let angle: Double
        if let point {
            let x = point.x - center.x, y = point.y - center.y
            guard hypot(x, y) > holdRadius else { return nil }
            angle = atan2(Double(y), Double(x))
        } else {
            // Camera-frame bearing continues to work when the target is behind the viewer.
            let x = simd_dot(star.direction, camera.right)
            let y = simd_dot(star.direction, camera.up)
            angle = atan2(-y, x)
        }
        let dx = CGFloat(cos(angle)), dy = CGFloat(sin(angle))
        let radius = min(104, max(72, min(size.width, size.height) * 0.16))
        return (CGPoint(x: center.x + dx * radius, y: center.y + dy * radius), .radians(angle))
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
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    if flow.step == .welcome {
                        Image("asterra-app-logo").resizable().scaledToFit()
                            .frame(width: 30, height: 30)
                            .accessibilityHidden(true)
                    } else {
                    Image(systemName: flow.succeeded ? "checkmark.circle.fill" : card.symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(flow.succeeded ? CelyxColor.ready : Color(red: 0.72, green: 0.82, blue: 1))
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: flow.succeeded)
                        .frame(width: 26)
                    }
                    Text(card.title).font(.title3.weight(.semibold))
                    Spacer(minLength: 8)
                    if let index = flow.progressIndex {
                        Text(OnboardingCopy.progress(current: index + 1, total: OnboardingFlow.Step.counted.count))
                            .font(.footnote.weight(.medium)).monospacedDigit()
                            .foregroundStyle(CelyxColor.secondaryLabel)
                            .contentTransition(.numericText())
                            .accessibilityLabel(OnboardingCopy.progressAccessibilityLabel(current: index + 1, total: OnboardingFlow.Step.counted.count))
                    }
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
            if let secondary = card.secondary {
                Button { flow.secondary() } label: {
                    Text(secondary)
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .contentShape(Capsule())
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())
                .padding(.top, 12)
            }
        }
        .foregroundStyle(CelyxColor.primaryLabel)
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, card.primary == nil ? 22 : 16)
        .glassEffect(.regular.tint(CelyxColor.night.opacity(0.35)), in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .animation(.spring(duration: 0.45, bounce: 0.1), value: card)
        .sensoryFeedback(.success, trigger: flow.succeeded) { _, new in new }
    }
}

/// A quiet, clearly bounded alternative inside the glass coach card.
private struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(CelyxColor.primaryLabel)
            .background(.white.opacity(configuration.isPressed ? 0.2 : 0.09), in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1) }
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
            if star.isSun {
                Circle().fill(Color(red: 1, green: 0.82, blue: 0.52).opacity(0.3))
                    .frame(width: 50, height: 50).blur(radius: 9)
                Circle().fill(Color(red: 1, green: 0.92, blue: 0.7))
                    .frame(width: 20, height: 20)
            } else {
                DemoStarView(color: star.color).scaleEffect(isLocked ? 1.3 : 1.15)
            }
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
            .font(.system(size: 30, weight: .black))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.85), radius: 2, y: 1)
            .shadow(color: Color(red: 0.62, green: 0.77, blue: 1), radius: 10)
            .phaseAnimator([0.0, 1.0]) { view, t in
                view.offset(x: reduceMotion ? 0 : t * 7)
            } animation: { t in t == 1 ? .easeInOut(duration: 0.7) : .easeInOut(duration: 0.9) }
            .rotationEffect(angle)
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
