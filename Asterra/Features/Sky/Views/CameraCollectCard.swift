import SwiftUI

/// Reference-style object information. The green Collect pill is the sole visible
/// primary action; tapping this stationary card is also an easy capture shortcut.
struct CameraCollectCard: View {
    let star: CatalogStar
    let status: String
    var isCollected = false
    var isCollecting = false
    let onCollect: () -> Void
    let onDismiss: () -> Void

    private var subtitle: String {
        if star.isSolarSystemBody { return star.kind }
        if let code = star.con, let name = ConstellationNames.name(for: code) { return "Star in \(name)" }
        return "Star"
    }
    var body: some View {
        ZStack(alignment: .top) {
            CelyxBluePanel(cornerRadius: 34)
            CelyxGrabber()
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 16) {
                    StarPortraitView(star: star).frame(width: 64, height: 64).accessibilityHidden(true)
                        .shadow(color: Color(red: star.rgb.x, green: star.rgb.y, blue: star.rgb.z).opacity(0.6), radius: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(star.title).font(.system(size: 28, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                        Text(subtitle).font(.system(size: 15)).foregroundStyle(CelyxColor.subtitle)
                    }
                    Spacer(minLength: 0)
                    CelyxCloseButton(action: onDismiss).accessibilityLabel("Not this object")
                }
                .padding(.top, 24)
                HStack(spacing: 7) {
                    Circle().fill(CelyxColor.ready).frame(width: 6, height: 6)
                        .shadow(color: CelyxColor.ready, radius: 4)
                    Text(status).font(.system(size: 12)).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }.padding(.top, 18)
                Spacer(minLength: 0)
            }.padding(.horizontal, 16).padding(.bottom, 24)
        }
        .frame(height: 190)
        .foregroundStyle(CelyxColor.primaryLabel)
        .contentShape(Rectangle())
        .onTapGesture { if !isCollected && !isCollecting { onCollect() } }
        .accessibilityIdentifier("detected-object-info")
    }
}

#Preview("Sun · reference card") {
    CameraCollectCard(star: .sun, status: "Visible now · In your view", onCollect: {}, onDismiss: {})
        .padding(6).background(CelyxColor.night).preferredColorScheme(.dark)
}
