import SwiftUI

/// The four collection categories on the "Your Collection" panel.
struct CollectionListView: View {
    let category: CollectionCategory
    let model: HomeViewModel
    let events: SkyEventStore
    let onSelectEvent: (SkyEvent) -> Void
    @State private var selected: GardenCollectionItem?

    var body: some View {
        ScrollView {
            content.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(CelyxScreenWash())
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .preferredColorScheme(.dark)
        .sheet(item: $selected) { item in
            CollectedObjectSheet(
                item: item, direction: currentDirection(of: item),
                onSaveNote: { model.updateObservationNote(id: item.id, note: $0) },
                onSavePlace: { model.updateObservationPlace(id: item.id, name: $0) }
            ) {
                model.deleteCollected(id: item.id)
                selected = nil
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch category {
        case .stars:
            itemList(
                CollectionCategory.stars(model.collectionItems),
                empty: "No stars yet. Tap Start Collecting and point at a bright one.")
        case .planets:
            itemList(
                CollectionCategory.planets(model.collectionItems),
                empty: "No planets or Moon yet. They look like steady, bright stars.")
        case .skyEvents:
            let collected = SkyEvent.catalogue.filter { events.collected.contains($0.id) }
            if collected.isEmpty {
                emptyState("No sky events yet. Open the Sky Calendar to see what’s coming up.")
            } else {
                VStack(spacing: 12) {
                    ForEach(collected) { event in
                        Button {
                            onSelectEvent(event)
                        } label: {
                            eventRow(event)
                        }.buttonStyle(.plain)
                    }
                }
            }
        case .constellations:
            let groups = CollectionCategory.constellations(model.collectionItems)
            if groups.isEmpty {
                emptyState("Collect a star and its constellation shows up here.")
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(groups, id: \.code) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(group.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(
                                    .white)
                                Spacer()
                                Text("\(group.items.count) star\(group.items.count == 1 ? "" : "s")")
                                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                            }
                            ForEach(group.items) { item in
                                Button {
                                    selected = item
                                } label: {
                                    itemRow(item)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func itemList(_ items: [GardenCollectionItem], empty: String) -> some View {
        if items.isEmpty {
            emptyState(empty)
        } else {
            VStack(spacing: 12) {
                ForEach(items) { item in
                    Button {
                        selected = item
                    } label: {
                        itemRow(item)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func itemRow(_ item: GardenCollectionItem) -> some View {
        let star = item.star
        return HStack(spacing: 14) {
            StarPortraitView(star: star)
                .frame(width: 48, height: 48)
                .shadow(
                    color: Color(red: star.rgb.x, green: star.rgb.y, blue: star.rgb.z).opacity(0.6), radius: 8
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(star.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                Text(subtitle(for: star)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(item.collectedDate).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(14)
        .background(CelyxInfoBox())
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows details")
    }

    private func eventRow(_ event: SkyEvent) -> some View {
        HStack(spacing: 14) {
            Image(event.artwork.asset).resizable().scaledToFill().frame(width: 48, height: 48)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                Text(event.detailDate).font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(
                .white.opacity(0.4))
        }
        .padding(14)
        .background(CelyxInfoBox())
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func emptyState(_ text: String) -> some View {
        Text(text).font(.system(size: 15)).foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 80)
    }

    private func subtitle(for star: CatalogStar) -> String {
        if star.isSolarSystemBody { return star.kind }
        if let code = star.con, let name = ConstellationNames.name(for: code) {
            return "Star in \(name)"
        }
        return "Star"
    }

    /// Where it is right now (for the detail sheet).
    private func currentDirection(of item: GardenCollectionItem) -> SIMD3<Double>? {
        let location =
            model.location ?? ObserverLocation(latitude: -6.2, longitude: 106.85, isManual: true)
        let sky = AstronomyService.snapshot(date: Date(), location: location)
        let star = item.star
        let geometric: SIMD3<Double>?
        if star.isSun {
            geometric = sky.sunDirection
        } else if star.isMoon {
            geometric = sky.moonDirection
        } else if star.isPlanet {
            geometric = sky.planets.first(where: { $0.star.id == star.id })?.direction
        } else {
            geometric = sky.direction(ra: star.ra_deg, dec: star.dec_deg)
        }
        return geometric.map { Refraction.apparent($0) }
    }
}

#Preview("Collection list") {
    CollectionListView(
        category: .stars, model: AppPreviewData.collectedModel, events: SkyEventStore(),
        onSelectEvent: { _ in }
    )
    .preferredColorScheme(.dark)
}
