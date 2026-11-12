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

/// The tour's one way of saying "press this": a soft glow with a slow, subtle ripple leaving the control.
/// Used on the toolbar buttons and on controls inside sheets alike.
struct OnboardingHighlight: View {
    var diameter: CGFloat = 48
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let light = Color(red: 0.66, green: 0.78, blue: 1)
    private let period = 2.4

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                // Breathing glow under the control (ease in-out).
                let breath = 0.5 - 0.5 * cos(time * 2 * .pi / period)
                Circle().fill(light)
                    .frame(width: diameter, height: diameter)
                    .blur(radius: 12)
                    .opacity(reduceMotion ? 0.35 : 0.22 + 0.22 * breath)
                // Two staggered ripples, each easing out as it grows and fades.
                if !reduceMotion {
                    ForEach(0..<2, id: \.self) { i in
                        let t = (time / period + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                        let eased = 1 - pow(1 - t, 3)
                        Circle().stroke(light, lineWidth: 1.2)
                            .frame(width: diameter, height: diameter)
                            .scaleEffect(1 + eased * 0.55)
                            .opacity((1 - eased) * 0.55)
                    }
                }
            }
        }
        .frame(width: diameter * 1.6, height: diameter * 1.6)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    OnboardingGuidePill(text: "Write what you see, then tap Done.")
        .padding().background(CelyxColor.night)
}
