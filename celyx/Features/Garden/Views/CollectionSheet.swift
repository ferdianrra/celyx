import SwiftUI

/// Content presented in the native collection sheet.
struct CollectionSheet: View {
    struct Counts { var stars = 0, planets = 0, events = 0, constellations = 0 }
    let counts: Counts
    let onSelect: (CollectionCategory) -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Collection").font(.system(size: 22, weight: .bold)).tracking(-0.26).frame(
                            height: 28)
                        Text("Every star has a story. Start collecting yours!").font(.system(size: 12)).frame(
                            height: 16)
                    }
                    .foregroundStyle(CelyxColor.primaryLabel)
                    .padding(.horizontal, 8)
                    Spacer(minLength: 8)
                    CelyxCloseButton(action: onClose)
                }
                .frame(height: 52)
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        CollectionTile(title: "Stars", count: counts.stars, action: { onSelect(.stars) }) {
                            Image("celyx-tile-stars").resizable().frame(width: 178, height: 109).offset(
                                x: 61, y: -19)
                        }
                        CollectionTile(title: "Planet", count: counts.planets, action: { onSelect(.planets) })
                        {
                            Image("celyx-tile-planet").resizable().frame(width: 148, height: 109).offset(
                                x: 61, y: -8)
                        }
                    }
                    GridRow {
                        CollectionTile(
                            title: "Sky event", count: counts.events, action: { onSelect(.skyEvents) }
                        ) {
                            // Figma: mirrored horizontally and blended with Screen, so the meteors glow out of the dark tile.
                            Image("celyx-event-meteor-card").resizable().frame(width: 214, height: 214)
                                .scaleEffect(x: -1, y: 1)
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)).offset(
                                    x: 50, y: -71
                                )
                                .blendMode(.screen)
                        }
                        CollectionTile(
                            title: "Constellation", count: counts.constellations,
                            action: { onSelect(.constellations) }
                        ) {
                            Image("celyx-tile-constellation").resizable().frame(width: 192, height: 123)
                                .offset(
                                    x: 20, y: -22)
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 24)
        }
    }
}

private struct CollectionTile<Art: View>: View {
    let title: String
    let count: Int
    let action: () -> Void
    @ViewBuilder var art: Art
    var body: some View {
        Button(action: action) { tile }
            .buttonStyle(.plain)
            .accessibilityHint("Shows what you’ve collected")
    }
    private var tile: some View {
        ZStack(alignment: .topLeading) {
            CelyxInfoBox().overlay(alignment: .topLeading) { art.accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12)).foregroundStyle(CelyxColor.secondaryLabel).frame(
                    height: 16)
                Text("\(count)").font(.system(size: 22)).tracking(-0.26).foregroundStyle(.white).frame(
                    height: 28)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity).frame(height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#Preview("Collection sheet") {
    Color.black
        .sheet(isPresented: .constant(true)) {
            CollectionSheet(
                counts: .init(stars: 12, planets: 2, events: 1, constellations: 3), onSelect: { _ in },
                onClose: {}
            )
            .presentationDetents([.height(300), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground { CelyxBluePanel() }
        }
        .preferredColorScheme(.dark)
}

#Preview("Collection tile") {
    CollectionTile(title: "Stars", count: 12, action: {}) {
        Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.white)
    }.frame(width: 180, height: 150).padding().background(.black)
        .preferredColorScheme(.dark)
}
