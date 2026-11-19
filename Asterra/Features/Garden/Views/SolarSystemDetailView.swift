//
//  SolarSystemDetailView.swift
//  Asterra
//
//  Created by Ahmad Zaki on 19/11/26.
//

import SwiftUI

struct SolarSystemDetailView: View {
    let entry: SolarSystemEntry
    let model: HomeViewModel
    var onGuide: ((CatalogStar) -> Void)? = nil

    @State private var selected: GardenCollectionItem?
    @State private var pendingGuide: CatalogStar?

    private var item: GardenCollectionItem? {
        entry.item(in: model)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                section("About", text: entry.about)
                section("Did you know?", text: entry.funFact)

                if let item {
                    observation(item)
                }

                if let body = entry.catalogBody, onGuide != nil {
                    StartCollectingButton(
                        title: "Find in sky",
                        identifier: "guide-to-solar-system-object"
                    ) {
                        onGuide?(body)
                    }
                } else if entry.catalogBody == nil {
                    Text("Collection support is coming soon.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(CelyxScreenWash())
        .navigationTitle(entry.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .sheet(item: $selected, onDismiss: openPendingGuide) { item in
            ObjectObservationSheet(
                item: item,
                model: model,
                allowsCompact: false,
                onGuide: onGuide.map { _ in
                    { pendingGuide = item.star }
                }
            )
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            SolarSystemPortrait(entry: entry)
                .frame(width: 240, height: 240)

            Text(entry.rawValue)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)

            Text(entry.category)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Label(
                item == nil ? "Not collected" : "Collected",
                systemImage: item == nil
                    ? "circle"
                    : "checkmark.circle.fill"
            )
            .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func section(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            Color.bookSecondary,
            in: RoundedRectangle(cornerRadius: 24)
        )
    }

    private func observation(_ item: GardenCollectionItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your observation")
                .font(.headline)

            Label(item.albumLocation, systemImage: "location")
            Label(item.collectedDate, systemImage: "calendar")
                .foregroundStyle(.secondary)

            Button {
                selected = item
            } label: {
                HStack(spacing: 12) {
                    Label("View photo and notes", systemImage: "photo")
                        .font(.body.weight(.medium))

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(CelyxColor.primaryLabel)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            Color.bookSecondary,
            in: RoundedRectangle(cornerRadius: 24)
        )
    }

    private func openPendingGuide() {
        guard let star = pendingGuide else { return }
        pendingGuide = nil
        onGuide?(star)
    }
}
