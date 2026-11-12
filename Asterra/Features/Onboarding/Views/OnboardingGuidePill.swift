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

#Preview {
    OnboardingGuidePill(text: "Write what you see, then tap Done.")
        .padding().background(CelyxColor.night)
}
