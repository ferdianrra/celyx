import SwiftUI

/// The tour's voice wherever the coach card can't be (over the wormhole, inside sheets, on pushed
/// screens): one calm Liquid Glass line with the same sparkle, so the user always knows what to do next.
struct OnboardingGuidePill: View {
    let text: String
    var symbol = "sparkles"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(red: 0.72, green: 0.82, blue: 1))
                .symbolEffect(.pulse, options: .repeat(.periodic(delay: 1.2)))
            Text(text).font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(CelyxColor.primaryLabel)
        .padding(.horizontal, 18).padding(.vertical, 12)
        .glassEffect(.regular.tint(CelyxColor.night.opacity(0.55)), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .environment(\.colorScheme, .dark)
        .id(text)
        .transition(.blurReplace.combined(with: .offset(y: 6)))
        .accessibilityElement(children: .combine)
    }
}

/// The tour's one way of saying "press this": a bright glow under the control and eased ripples leaving
/// its outline, each ripple with a soft haptic tap so the phone itself seems to call from the button.
/// (iPhone haptics can't be placed at a point on the screen; syncing them to the ripple gives that feel.)
struct OnboardingHighlight: View {
    /// The control's size; a circle when width == height, otherwise a capsule.
    var size: CGSize = CGSize(width: 48, height: 48)
    var haptics = true
    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let light = Color(red: 0.55, green: 0.78, blue: 1)
    /// One ripple per beat.
    private let period = 1.6

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(start))
            let t = (elapsed / period).truncatingRemainder(dividingBy: 1)
            let eased = 1 - pow(1 - t, 3)
            let breath = 0.5 - 0.5 * cos(elapsed * 2 * .pi / (period * 2))
            ZStack {
                // A vivid glow under the control, breathing slowly.
                Capsule().fill(light)
                    .frame(width: size.width, height: size.height)
                    .blur(radius: 14)
                    .opacity(reduceMotion ? 0.7 : 0.55 + 0.35 * breath)
                Capsule().stroke(.white.opacity(0.85), lineWidth: 1.5)
                    .frame(width: size.width + 4, height: size.height + 4)
                    .shadow(color: light, radius: 6)
                if !reduceMotion {
                    // The ripple: grows by a fixed margin (same feel on a circle or a long capsule) and fades.
                    Capsule().stroke(light, lineWidth: 2)
                        .frame(width: size.width + 4 + eased * 34, height: size.height + 4 + eased * 34)
                        .shadow(color: light, radius: 4)
                        .opacity((1 - eased) * 0.95)
                }
            }
        }
        .frame(width: size.width + 60, height: size.height + 60)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            guard haptics else { return }
            start = Date()
            let tap = UIImpactFeedbackGenerator(style: .soft)
            tap.prepare()
            while !Task.isCancelled {
                // A soft heartbeat on every ripple: tap, then a lighter echo.
                tap.impactOccurred(intensity: 0.75)
                try? await Task.sleep(for: .milliseconds(110))
                tap.impactOccurred(intensity: 0.35)
                try? await Task.sleep(for: .seconds(period - 0.11))
            }
        }
    }
}

#Preview {
    OnboardingGuidePill(text: "Write what you see, then tap Done.")
        .padding().background(CelyxColor.night)
}
