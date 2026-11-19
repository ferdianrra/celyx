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

    var body: some View {
        HStack(spacing: 12) {
            SolarSystemPortrait(entry: entry)
                .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.category)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.64))

                Text(entry.rawValue)
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            Spacer(minLength: 8)

            Text(isCollected ? "Collected" : "Not collected")
                .font(.footnote.weight(.medium))
                .foregroundStyle(
                    isCollected ? .white : .white.opacity(0.7)
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(
                        isCollected
                            ? CelyxColor.accent
                            : .white.opacity(0.08)
                    )
                )
                .overlay(
                    Capsule().strokeBorder(
                        .white.opacity(isCollected ? 0.25 : 0.12),
                        lineWidth: 0.5
                    )
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            Image("celyx-card-bg").resizable()
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows details")
    }
}
