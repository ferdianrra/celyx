import SwiftUI

struct ShareCollectionBadge: View {
    let number: Int
    private var tier: ShareBadgeTier { ShareBadgeTier(number: number) }
    private var labelColor: Color {
        switch tier {
        case .silver: Color(hex: 0x5F5F5F)
        case .gold: Color(hex: 0x4D2C05)
        case .astungkara: .black
        }
    }
    private var numberColors: [Color] {
        switch tier {
        case .silver: [Color(hex: 0xB6B6B6), Color(hex: 0x424242)]
        case .gold: [Color(hex: 0xFFAD40), Color(hex: 0xE8B154), Color(hex: 0x954F00)]
        case .astungkara: [Color(hex: 0xE8E7FF), Color(hex: 0x5057CF), Color(hex: 0x14377A), Color(hex: 0x0A1C3D)]
        }
    }

    var body: some View {
        ZStack {
            Image(tier.asset).resizable().scaledToFit()
                .frame(width: 55.7443, height: 64.368)
            VStack(spacing: 0) {
                Text("STAR").font(.system(size: 7.33, weight: .bold)).tracking(0.27).foregroundStyle(labelColor)
                Text(String(format: "%02d", number))
                    .font(.system(size: 25.67, weight: .heavy)).tracking(-0.94)
                    .foregroundStyle(LinearGradient(colors: numberColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: labelColor.opacity(0.8), radius: 0, y: 1)
                    .lineLimit(1).minimumScaleFactor(0.55)
                    .frame(width: 44, height: 25)
            }.offset(y: -0.4)
        }
        .frame(width: 61.111, height: 61.111)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Star \(number), \(tier.rawValue) badge")
        .accessibilityIdentifier("share-collection-badge")
        .accessibilityValue(String(number))
    }
}
