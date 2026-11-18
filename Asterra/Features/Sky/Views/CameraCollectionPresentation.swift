import SwiftUI

/// The camera's ready-to-collect card, using the supplied vertical linear palette.
struct CameraCollectionCard: View {
    let star: CatalogStar
    let onCollect: () -> Void
    let onDismiss: () -> Void

    private var subtitle: String {
        if star.isSolarSystemBody { return star.kind }
        if let code = star.con, let name = ConstellationNames.name(for: code) { return "Star in \(name)" }
        return "Star"
    }

    var body: some View {
        Button(action: onCollect) {
            HStack(alignment: .center, spacing: 16) {
                StarPortraitView(star: star)
                    .frame(width: 64, height: 64)
                    .shadow(color: Color(red: star.rgb.x, green: star.rgb.y, blue: star.rgb.z).opacity(0.7), radius: 9)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(star.title).font(.title2.weight(.bold))
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .frame(minHeight: 28, alignment: .leading)
                    Text(subtitle).font(.system(size: 15)).foregroundStyle(Color(hex: 0xAFC7EB))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(minHeight: 20, alignment: .leading)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .foregroundStyle(CelyxColor.primaryLabel)
            .background {
                LinearGradient(stops: [
                    .init(color: Color(hex: 0xA7A4E9), location: 0),
                    .init(color: Color(hex: 0x5057CF), location: 0.18),
                    .init(color: Color(hex: 0x14377A), location: 0.43),
                    .init(color: Color(hex: 0x0A1C3D), location: 1)
                ], startPoint: .top, endPoint: .bottom)
                // Soften the joins between Figma's color stops without blurring content.
                .blur(radius: 10, opaque: true)
                .drawingGroup(opaque: true, colorMode: .linear)
            }
            .clipShape(.rect(cornerRadius: 32))
            .overlay {
                RoundedRectangle(cornerRadius: 32).strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.05), .white.opacity(0.2)],
                                   startPoint: .topTrailing, endPoint: .bottomLeading), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
            .contentShape(.rect(cornerRadius: 32))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Collect \(star.title)")
        .accessibilityHint("\(subtitle). Tap to collect")
        .accessibilityIdentifier("camera-collection-card")
        .overlay(alignment: .trailing) {
            Button("Close", systemImage: "xmark", role: .close, action: onDismiss)
                .labelStyle(.iconOnly).foregroundStyle(.white)
                .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
                .accessibilityLabel("Dismiss \(star.title)")
                .accessibilityIdentifier("camera-dismiss-object")
                .padding(.trailing, 20)
        }
    }
}

/// Plain guidance, without an additional glass pill competing with the card.
struct CameraCollectionPrompt: View {
    let text: String
    var ready = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: ready ? "hand.tap" : "scope")
                .font(.system(size: ready ? 22 : 24, weight: .regular))
                .accessibilityHidden(true)
            Text(text).font(.system(size: 15)).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(CelyxColor.primaryLabel)
        .shadow(color: .black.opacity(0.35), radius: 1.5, x: 0, y: 0.5)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .allowsHitTesting(false)
    }
}

#Preview("Ready to collect") {
    VStack(spacing: 38) {
        Spacer()
        CameraCollectionPrompt(text: "Tap anywhere to collect", ready: true)
        CameraCollectionCard(star: AppPreviewData.star, onCollect: {}, onDismiss: {})
    }.padding(20).background(CelyxColor.night).preferredColorScheme(.dark)
}
