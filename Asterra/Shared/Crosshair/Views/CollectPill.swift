import SwiftUI

/// Plain capture label retained for camera call sites; no glass, rim or filled pill.
struct CollectPill: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 1.5, x: 0, y: 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint("Captures this moment and adds the star to your sky")
        .accessibilityIdentifier("collect-pill")
    }
}

#Preview("Plain collect label") {
    CollectPill(title: "Collect Rigel") {}
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CelyxColor.night)
}
