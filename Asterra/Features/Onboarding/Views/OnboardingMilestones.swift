import SwiftUI

/// Native popover content: the system draws an arrow anchored to the actual component.
struct DiscoveryTooltip: View {
    let title: String
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss tip", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly).font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 285)
        .preferredColorScheme(.dark)
        .presentationCompactAdaptation(.popover)
        .accessibilityElement(children: .contain)
    }
}

/// Celebrates the completed capture-and-note lesson without adding another tour step.
struct OnboardingCompletionCard: View {
    let onExplore: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Color.purple.opacity(0.22)).blur(radius: 15)
                    .frame(width: 125, height: 125)
                Circle().stroke(.white.opacity(0.15), lineWidth: 1).frame(width: 112, height: 112)
                ForEach(0..<8) { index in
                    let angle = Double(index) * .pi / 4
                    Image(systemName: index.isMultiple(of: 2) ? "sparkle" : "circle.fill")
                        .font(.system(size: index.isMultiple(of: 2) ? 13 : 4))
                        .foregroundStyle(Color(red: 0.9, green: 0.82, blue: 1))
                        .offset(x: cos(angle) * 67, y: sin(angle) * 67)
                }
                Image(systemName: "seal.fill")
                    .font(.system(size: 90))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 0.8, green: 0.69, blue: 1),
                        Color(red: 0.38, green: 0.3, blue: 0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "star.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: appeared)
            }
            .frame(height: 150)
            .accessibilityHidden(true)
            VStack(spacing: 9) {
                Text("SKY EXPLORER").font(.caption.weight(.bold)).tracking(3)
                    .foregroundStyle(Color(red: 0.84, green: 0.77, blue: 1))
                Text("Tutorial complete!").font(.title.weight(.bold))
                Text("You know how to collect a sky object and add a note. Now the sky is yours to explore.")
                    .font(.body).foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            Button(action: onExplore) {
                Label("Explore the sky", systemImage: "sparkles")
                    .font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(CelyxTintedGlassButtonStyle())
            .accessibilityIdentifier("finish-tour-celebration")
        }
        .foregroundStyle(.white)
        .padding(26)
        .frame(maxWidth: 390)
        .background {
            RoundedRectangle(cornerRadius: 36)
                .fill(LinearGradient(colors: [Color(red: 0.27, green: 0.2, blue: 0.53), CelyxColor.night],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 36).strokeBorder(.white.opacity(0.3), lineWidth: 1))
                .shadow(color: .purple.opacity(0.25), radius: 30)
        }
        .scaleEffect(appeared ? 1 : (reduceMotion ? 1 : 0.9))
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.6, bounce: 0.2)) { appeared = true } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tour-completion-celebration")
    }
}
