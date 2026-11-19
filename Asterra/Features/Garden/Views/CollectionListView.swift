import SwiftUI

/// The four collection categories on the "Your Collection" panel.
struct CollectionListView: View {
    let category: CollectionCategory
    let model: HomeViewModel
    let events: SkyEventStore
    var onGuide: ((CatalogStar) -> Void)? = nil
    let onSelectEvent: (SkyEvent) -> Void
    @State private var selected: GardenCollectionItem?
    @State private var pendingGuide: CatalogStar?
    @State private var book: [ZodiacBookEntry] = []
    @State private var openBook: ZodiacBookEntry?
    @State private var openPlanet: SolarSystemEntry?

    var body: some View {
        ScrollView {
            content.padding(.horizontal, category == .constellations ? 16 : 20)
                .padding(.top, category == .constellations ? 32 : 12).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background {
            if category == .constellations {
                Image("background/background-constellation-list").resizable().ignoresSafeArea()
            } else {
                CelyxScreenWash()
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .preferredColorScheme(.dark)
        .sheet(item: $selected, onDismiss: openPendingGuide) { objectSheet($0) }
        .navigationDestination(item: $openBook) { entry in
            ZodiacBookDetailView(entry: entry, model: model, onObjectSheetDismissed: openPendingGuide) { objectSheet($0) }
        }
        .navigationDestination(item: $openPlanet) { entry in
            SolarSystemDetailView(
                entry: entry,
                model: model,
                onGuide: onGuide
            )
        }
        .task(id: category) {
            if category == .constellations, book.isEmpty { book = ZodiacBookEntry.load(catalogue: model.stars) }
        }
    }

    private func objectSheet(_ item: GardenCollectionItem) -> some View {
        ObjectObservationSheet(item: item, model: model, allowsCompact: false, onGuide: onGuide.map { _ in
            { pendingGuide = item.star }
        })
    }

    private func openPendingGuide() {
        guard let star = pendingGuide else { return }
        pendingGuide = nil
        onGuide?(star)
    }

    @ViewBuilder private var content: some View {
        switch category {
        case .stars:
            itemList(
                CollectionCategory.stars(model.collectionItems),
                empty: "No stars yet. Tap Start Collecting and point at a bright one.")
        case .planets:
            LazyVStack(spacing: 12) {
                ForEach(SolarSystemEntry.allCases) { entry in
                    Button {
                        openPlanet = entry
                    } label: {
                        SolarSystemCard(
                            entry: entry,
                            isCollected: entry.item(in: model) != nil
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
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
            let collected = Set(model.collected.keys)
            // The zodiac has artwork, so it gets the book grid; other constellations keep the star list.
            let groups = CollectionCategory.constellations(model.collectionItems)
                .filter { !ZodiacBookEntry.order.contains($0.code) }
            VStack(alignment: .leading, spacing: 24) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], spacing: 16) {
                    ForEach(book) { entry in
                        Button { openBook = entry } label: { ZodiacBookCard(entry: entry, collected: collected) }
                            .buttonStyle(.plain)
                    }
                }
                if !groups.isEmpty {
                    Text("More constellations").font(.headline).foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                }
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

}

#Preview("Collection list") {
    CollectionListView(
        category: .stars, model: AppPreviewData.collectedModel, events: SkyEventStore(),
        onSelectEvent: { _ in }
    )
    .preferredColorScheme(.dark)
}
