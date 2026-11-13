import SwiftUI

/// The tour's voice wherever the coach card can't be (over the wormhole, inside sheets, on pushed
/// screens): one calm Liquid Glass line with the same sparkle, so the user always knows what to do next.
struct OnboardingGuidePill: View {
    let text: String
    var symbol = "sparkles"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(hex: 0x9AA2FF))
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

/// The tour's one way of saying "press this" (Figma "Frame 2695", 1244:3728): rings leave the control
/// and, as they grow, their gradient stroke thins (2 → 0.5pt), their soft radial fill and violet glow widen
/// and fade. Each ring rides an ease-out curve so it bursts out and settles, never a linear pulse. A soft
/// haptic heartbeat taps in sync with every ring (iPhone haptics can't be placed at a point on screen).
struct OnboardingHighlight: View {
    /// The control's size; a circle when width == height, otherwise a capsule.
    var size: CGSize = CGSize(width: 48, height: 48)
    var haptics = true
    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Figma: violet #7459DF, periwinkle #99AFE9, lavender centre #CBC9F5.
    private static let violet = Color(hex: 0x7459DF)
    private static let periwinkle = Color(hex: 0x99AFE9)
    private static let lavender = Color(hex: 0xCBC9F5)
    /// A wave: three rings leave one after another, travel out, then a short rest before the next wave.
    private let rings = 3
    private let stagger = 0.22
    private let travel = 1.7
    private let rest = 0.032
    private var cycle: Double { Double(rings - 1) * stagger + travel + rest }
    /// Figma's first ring sits 9pt outside a 46pt control (64pt); the last is 116/64 of it.
    private var inset: CGFloat { 9 }
    private var growth: CGFloat {
        // Figma's 64 → 116 spread, tempered to about half so the rings stay close to the control.
        let spread = (min(size.width, size.height) + inset * 2) * (116.0 / 64.0 - 1) * 0.5
        // A wide control (Start Collecting) keeps its rings tight so they don't wash over the card above.
        return size.width > size.height * 1.5 ? min(spread, 16) : spread
    }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(start))
            let local = elapsed.truncatingRemainder(dividingBy: cycle)
            ZStack {
                if reduceMotion {
                    ring(progress: 0.3, presence: 1)
                } else {
                    // Every ring is always moving: born at the control's edge, it bursts out on an
                    // ease-out curve, thinning and fading until it's gone. Nothing sits still.
                    ForEach(0..<rings, id: \.self) { i in
                        let t = (local - Double(i) * stagger) / travel
                        if t > 0 && t < 1 {
                            let eased = 1 - pow(1 - t, 3)
                            let presence = min(1, t / 0.12) * pow(1 - t, 1.3)
                            ring(progress: eased, presence: presence)
                        }
                    }
                }
            }
        }
        .frame(width: size.width + inset * 2 + growth + 80, height: size.height + inset * 2 + growth + 80)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            start = Date()
            guard haptics, !reduceMotion else { return }
            let tap = UIImpactFeedbackGenerator(style: .soft)
            tap.prepare()
            while !Task.isCancelled {
                // A soft heartbeat as each wave leaves: tap, then a lighter echo with the second ring.
                tap.impactOccurred(intensity: 0.7)
                try? await Task.sleep(for: .seconds(stagger))
                tap.impactOccurred(intensity: 0.3)
                try? await Task.sleep(for: .seconds(cycle - stagger))
            }
        }
    }

    /// One ring at `progress` 0 (Figma inner ellipse) … 1 (outer ellipse).
    private func ring(progress p: Double, presence: Double) -> some View {
        let grow = (growth + inset * 2) * p
        let width = size.width + 4 + grow, height = size.height + 4 + grow
        let line = 2 - 1.5 * p                 // 2 → 1 → 0.5 pt
        let fill = 1 - 0.6 * p                 // fill opacity 1 → 0.6 → 0.4
        let glow = 1 - 0.6 * p                 // shadow alpha 1 → 0.8 → 0.4
        let blur = (12 + 68 * p) / 2           // Figma blur 12 → 24 → 80 (SwiftUI radius ≈ half)
        return ZStack {
            Capsule()
                .fill(RadialGradient(colors: [Self.lavender.opacity(0), Self.violet.opacity(0.32)],
                                     center: .center, startRadius: 0, endRadius: max(width, height) / 2))
                .opacity(fill)
            Capsule()
                .strokeBorder(LinearGradient(colors: [Self.violet, Self.periwinkle, Self.violet],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: line)
                .shadow(color: Self.violet.opacity(glow), radius: blur)
        }
        .frame(width: width, height: height)
        .opacity(presence)
    }
}

#Preview {
    OnboardingGuidePill(text: "Write what you see, then tap Done.")
        .padding().background(CelyxColor.night)
}
