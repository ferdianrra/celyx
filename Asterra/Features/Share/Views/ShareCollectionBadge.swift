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
    private var ordinalSuffix: String {
        if (11...13).contains(number % 100) { return "th" }

        switch number % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
    var body: some View {
        ZStack {
            Image(tier.asset).resizable().scaledToFit()
                .frame(width: 55.7443, height: 64.368)
            VStack(spacing: 0) {
                Text("MY")
                    .font(.system(size: 7, weight: .bold))
                    .tracking(0.27).foregroundStyle(labelColor)
                HStack(alignment: .top, spacing: 0.5) {
                    Text("\(number)")
                        .font(.system(size: 23, weight: .heavy))
                        .tracking(-0.9)
                    Text(ordinalSuffix)
                        .font(.system(size: 7, weight: .bold))
                        .padding(.top, 3)
                }
                .foregroundStyle(
                    LinearGradient(
                        colors: numberColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .fixedSize()
                .frame(width: 44, height: 25)
                .minimumScaleFactor(0.55)
                Text("STAR").font(.system(size: 7, weight: .bold)).tracking(0.27).foregroundStyle(labelColor)
            }.offset(y: -0.4)
        }
        .frame(width: 61.111, height: 61.111)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("My \(number)\(ordinalSuffix) star, \(tier.rawValue) badge")
        .accessibilityIdentifier("share-collection-badge")
        .accessibilityValue(String(number))
    }
}
