//
//  SolarSystemCard.swift
//  Asterra
//
//  Created by Ahmad Zaki on 19/11/26.
//

import SwiftUI

struct SolarSystemPortrait: View {
    let entry: SolarSystemEntry

    var body: some View {
        Group {
            if let body = entry.catalogBody {
                StarPortraitView(star: body)
            } else {
                PlanetView(look: outerPlanetLook)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Illustration of \(entry.rawValue)")
    }

    private var outerPlanetLook: PlanetLook {
        let isUranus = entry == .uranus

        return PlanetLook(
            texture: isUranus ? "uranus" : "neptune",
            tint: .one,
            atmosphere: isUranus
                ? SIMD3<Float>(0.65, 0.94, 1)
                : SIMD3<Float>(0.40, 0.60, 1),
            atmosphereAmount: 0.35,
            rotationSpeed: 0.08,
            axialTilt: isUranus ? 1.70 : 0.49
        )
    }
}

struct SolarSystemCard: View {
    let entry: SolarSystemEntry
    let isCollected: Bool

    @ScaledMetric(relativeTo: .body)
    private var cardHeight: CGFloat = 144

    var body: some View {
        HStack(spacing: 12) {
            SolarSystemPortrait(entry: entry)
                .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 8) {
                Text(entry.category)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.64))

                Text(entry.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Label(
                    isCollected ? "Collected" : "Not collected",
                    systemImage: isCollected
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(16)
        .frame(minHeight: cardHeight)
        .background {
            Image("celyx-card-bg").resizable()
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows details")
    }
}
