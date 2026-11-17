import SwiftUI

// Constellation book (Figma "PAI - Asterra", section CONSTELLATION 1355:7098).

extension [CelyxInnerShadow] {
    /// Book card (1354:6770): the glow rises from the bottom edge.
    static let celyxBookCard: Self = [
        .init(color: Color(hex: 0x062277, opacity: 0.6), y: -24, blur: 64, spread: 20),
        .init(color: Color(hex: 0x0066E2, opacity: 0.8), y: -12, blur: 48, spread: 8),
        .init(color: Color(hex: 0x7459DF), y: -8, blur: 24, spread: 4),
        .init(color: .white, y: -2, blur: 12, spread: 2)
    ]
}

/// Rafi's artwork with the pattern stars on top. On the detail page the drawing lights up around collected stars.
struct ZodiacBookArt: View {
    let entry: ZodiacBookEntry
    let collected: Set<Int>
    var revealsAroundStars = false

    @State private var artwork: GardenZodiacArtwork?
    @State private var formed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let done = entry.collectedCount(collected) == entry.members.count
            ZStack {
                if let artwork {
                    let image = Image(decorative: artwork.image, scale: 1).resizable()
                    // Figma stacks the drawing three times so the translucent art reads near-white.
                    let bright = ZStack { image; image; image }
                    if revealsAroundStars {
                        image.opacity(0.22)
                        bright.mask { revealMask(size: size, done: done) }
                    } else if collected.isDisjoint(with: entry.members.map(\.id)) {
                        image.opacity(0.3)
                    } else {
                        bright
                    }
                }
                ZodiacBookLines(lines: entry.lines(collected))
                    .trim(from: 0, to: formed || !revealsAroundStars ? 1 : 0)
                    .stroke(.white.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .shadow(color: Color(hex: 0x7459DF), radius: 4)
                ForEach(entry.members) { member in
                    let point = CGPoint(x: member.point.x * size.width, y: member.point.y * size.height)
                    if collected.contains(member.id) {
                        star(member.star).position(point)
                    } else if revealsAroundStars {
                        Circle().strokeBorder(.white.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                            .frame(width: 12, height: 12).position(point)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
        .task(id: entry.assetName) {
            artwork = await GardenZodiacArtworkStore.shared.load(assetNamed: entry.assetName)
        }
        .onAppear {
            guard !formed else { return }
            if reduceMotion { formed = true; return }
            withAnimation(.smooth(duration: 1.2).delay(0.25)) { formed = true }
        }
    }

    private func revealMask(size: CGSize, done: Bool) -> some View {
        ZStack {
            if done {
                Color.white.opacity(formed ? 1 : 0)
            } else {
                // Each collected star lights a patch of the drawing; the patches grow with progress.
                let diameter = size.width * (0.4 + 0.4 * entry.progress(collected))
                ForEach(entry.members.filter { collected.contains($0.id) }) { member in
                    Circle()
                        .fill(RadialGradient(colors: [.white, .white.opacity(0.5), .clear], center: .center,
                                             startRadius: 0, endRadius: diameter / 2))
                        .frame(width: diameter, height: diameter)
                        .scaleEffect(formed ? 1 : 0.2)
                        .position(x: member.point.x * size.width, y: member.point.y * size.height)
                }
            }
        }
    }

    private func star(_ star: CatalogStar) -> some View {
        let color = Color(red: star.rgb.x, green: star.rgb.y, blue: star.rgb.z)
        return Circle().fill(.white).frame(width: 5, height: 5)
            .shadow(color: color, radius: 4).shadow(color: color, radius: 10)
    }
}

private struct ZodiacBookLines: Shape {
    let lines: [(CGPoint, CGPoint)]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (a, b) in lines {
            path.move(to: CGPoint(x: a.x * rect.width, y: a.y * rect.height))
            path.addLine(to: CGPoint(x: b.x * rect.width, y: b.y * rect.height))
        }
        return path
    }
}

/// Native linear progress with the Figma gradient (1354:6785).
struct ZodiacBookProgress: View {
    let entry: ZodiacBookEntry
    let collected: Set<Int>
    var body: some View {
        HStack(spacing: 8) {
            ProgressView(value: entry.progress(collected))
                .tint(LinearGradient(colors: [Color(hex: 0xDBD4F7), Color(hex: 0x7459DF)],
                                     startPoint: .leading, endPoint: .trailing))
            Text("\(entry.collectedCount(collected))/\(entry.members.count)")
                .font(.footnote.weight(.semibold)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.8))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.collectedCount(collected)) of \(entry.members.count) stars collected")
    }
}

/// Grid card (1354:6770).
struct ZodiacBookCard: View {
    let entry: ZodiacBookEntry
    let collected: Set<Int>
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            ZodiacBookArt(entry: entry, collected: collected)
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.name).font(.title3.weight(.semibold)).foregroundStyle(.white)
                ZodiacBookProgress(entry: entry, collected: collected)
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
        }
        // Glass sits behind the card so the artwork keeps its own colours.
        .background { Color.clear.celyxGlass(.celyxBookCard, in: shape) }
        .clipShape(shape)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the stars in this constellation")
    }
}

/// Constellation page (1354:6298): artwork that fills in as stars are collected, then the star list.
struct ZodiacBookDetailView<ObjectSheet: View>: View {
    let entry: ZodiacBookEntry
    let model: HomeViewModel
    @ViewBuilder let objectSheet: (GardenCollectionItem) -> ObjectSheet

    @State private var selected: GardenCollectionItem?
    @State private var showsInfo = false

    var body: some View {
        let collected = Set(model.collected.keys)
        ScrollView {
            VStack(spacing: 0) {
                header(collected)
                stars(collected)
            }
        }
        .scrollIndicators(.hidden)
        .background(alignment: .top) {
            VStack(spacing: 0) {
                Image("background/background-constellation-detail").resizable().scaledToFill()
                    .frame(height: 474).clipped()
                CelyxColor.screen
            }
            .ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let note = ZodiacBookNotes.note(for: entry.code) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("About \(entry.name)", systemImage: "info") { showsInfo = true }
                        .popover(isPresented: $showsInfo) {
                            info(note).presentationCompactAdaptation(.popover)
                        }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $selected) { objectSheet($0) }
    }

    private func header(_ collected: Set<Int>) -> some View {
        VStack(spacing: 8) {
            ZodiacBookArt(entry: entry, collected: collected, revealsAroundStars: true)
                .frame(maxWidth: 260)
            Text(entry.name).font(.title.weight(.bold)).foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            ZodiacBookProgress(entry: entry, collected: collected).frame(width: 214)
        }
        .padding(.horizontal, 16).padding(.bottom, 56)
    }

    private func stars(_ collected: Set<Int>) -> some View {
        let items = Dictionary(model.collectionItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return VStack(alignment: .leading, spacing: 16) {
            Text("Stars").font(.headline).foregroundStyle(.white).accessibilityAddTraits(.isHeader)
            ForEach(entry.members) { member in
                if let item = items[member.id] {
                    Button { selected = item } label: { row(member.star, collected: true) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows your photo and note")
                } else {
                    row(member.star, collected: false)
                }
            }
        }
        .padding(16).padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 38, topTrailingRadius: 38, style: .continuous)
                .fill(CelyxColor.screen)
                .padding(.bottom, -600)
        }
        .padding(.top, -32)
    }

    private func row(_ star: CatalogStar, collected: Bool) -> some View {
        HStack(spacing: 16) {
            StarPortraitView(star: star).frame(width: 48, height: 48)
            Text(star.title).font(.headline).foregroundStyle(.white)
            Spacer(minLength: 8)
            Text(collected ? "Collected" : "Not collected")
                .font(.subheadline).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .glassEffect(collected ? .regular.tint(CelyxColor.accent) : .regular, in: .capsule)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(CelyxInfoBox(cornerRadius: 20))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func info(_ note: ZodiacBookNotes.Note) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            infoSection("Best time to see it", note.bestTime)
            Divider()
            infoSection("How to spot it", note.howToSpot)
        }
        .padding(16)
        .frame(width: 250)
    }

    private func infoSection(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(text).font(.footnote.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
/// UI-test and canvas flow: the Constellations list with a few zodiac patterns part-way done.
struct ZodiacBookPreviewFlow: View {
    var detailCode: String? = nil
    @State private var model = AppPreviewData.collectedModel

    var body: some View {
        NavigationStack {
            if let entry = ZodiacBookEntry.load(catalogue: model.stars).first(where: { $0.code == detailCode }) {
                ZodiacBookDetailView(entry: entry, model: model) { _ in EmptyView() }
            } else {
                CollectionListView(category: .constellations, model: model, events: SkyEventStore(), onSelectEvent: { _ in })
            }
        }
        .task {
            let ids = [333, 51, 681, 222, 125, 103, 476, 329] + Array(ZodiacBookEntry.load(catalogue: model.stars)
                .first { $0.code == "Leo" }?.members.map(\.id) ?? [])
            try? model.seedDemoObservations(ids.map {
                CollectedStar(id: $0, date: AppPreviewData.date, latitude: AppPreviewData.location.latitude,
                              longitude: AppPreviewData.location.longitude)
            })
        }
    }
}

#Preview("Constellation book") { ZodiacBookPreviewFlow() }
#endif
