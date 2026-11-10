import SwiftUI

struct CelyxHintPill: View {
    let text: String
    var isLoading = false
    var body: some View {
        HStack(spacing: 12) {
            if isLoading {
                ProgressView().tint(CelyxColor.primaryLabel)
            } else {
                Image(systemName: "scope")
            }
            Text(text).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        }
        .font(.system(size: 15, weight: .semibold)).tracking(-0.23).foregroundStyle(.white)
        .padding(12)
        .background(Capsule().fill(.white.opacity(0.2)))
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, 24)
    }
}

#Preview("Camera hint") {
    CelyxHintPill(text: "Hold steady while we compare the stars").padding().background(.black)
        .preferredColorScheme(.dark)
}

#Preview("Camera hint · scanning faint light") {
    CelyxHintPill(text: "Scanning faint starlight… Hold steady for a moment", isLoading: true)
        .padding().background(CelyxColor.night).preferredColorScheme(.dark)
}
