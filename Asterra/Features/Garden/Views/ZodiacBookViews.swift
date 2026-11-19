import SwiftUI

// Constellation book (Figma "PAI - Asterra", section CONSTELLATION 1355:7098).

extension Color {
    private static let baseDark = UITraitCollection(traitsFrom: [
        UITraitCollection(userInterfaceStyle: .dark), UITraitCollection(userInterfaceLevel: .base)])
    /// System primary / secondary background in their dark, base-level variants (the app is dark-only).
    static let bookPrimary = Color(uiColor: .systemBackground.resolvedColor(with: baseDark))
    static let bookSecondary = Color(uiColor: .secondarySystemBackground.resolvedColor(with: baseDark))
}

/// Rafi's artwork with the pattern stars on top, cropped to the drawing and centred in its frame.
/// On the detail page the drawing lights up around collected stars.
struct ZodiacBookArt: View {
    let entry: ZodiacBookEntry
    let collected: Set<Int>
    var revealsAroundStars = false
    var inset: CGFloat = 0
    
    // Preloaded artwork for rendering a static share card.
    var preparedArtwork: GardenZodiacArtwork? = nil
    var preparedBounds: CGRect? = nil
    var isStatic = false

    @State private var artwork: GardenZodiacArtwork?
    @State private var bounds: CGRect?
    @State private var formed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            if let artwork = preparedArtwork ?? artwork,
               let bounds = preparedBounds ?? bounds {
                content(artwork, rect: Self.imageRect(bounds: bounds, in: geometry.size, inset: inset))
            }
        }
        .accessibilityHidden(true)
        .task(id: entry.assetName) {
            guard preparedArtwork == nil else { return }
            guard let loaded = await GardenZodiacArtworkStore.shared.load(assetNamed: entry.assetName) else { return }
            let points = entry.members.map(\.point)
            let found = await Task.detached(priority: .userInitiated) {
                ZodiacArtBounds.bounds(of: loaded.image, including: points)
            }.value
            bounds = found
            artwork = loaded
        }
        .onAppear {
            guard !formed else { return }
            if reduceMotion { formed = true; return }
            withAnimation(.smooth(duration: 1.2).delay(0.25)) { formed = true }
        }
    }

    /// Where the whole square image goes so that `bounds` (0...1) fills `size` minus `inset`, centred.
    private static func imageRect(bounds: CGRect, in size: CGSize, inset: CGFloat) -> CGRect {
        let box = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
        guard bounds.width > 0, bounds.height > 0, box.width > 0, box.height > 0 else { return .zero }
        let side = min(box.width / bounds.width, box.height / bounds.height)
        let fitted = CGSize(width: bounds.width * side, height: bounds.height * side)
        return CGRect(x: box.midX - fitted.width / 2 - bounds.minX * side,
                      y: box.midY - fitted.height / 2 - bounds.minY * side, width: side, height: side)
    }

    @ViewBuilder private func content(_ artwork: GardenZodiacArtwork, rect: CGRect) -> some View {
        let done = entry.collectedCount(collected) == entry.members.count
        let place = { (p: CGPoint) in CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height) }
        let image = Image(decorative: artwork.image, scale: 1).resizable()
            .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
        // Figma stacks the drawing three times so the translucent art reads near-white.
        let bright = ZStack { image; image; image }
        ZStack {
            if revealsAroundStars {
                image.opacity(0.22)
                bright.mask { revealMask(rect: rect, done: done, place: place) }
            } else if collected.isDisjoint(with: entry.members.map(\.id)) {
                image.opacity(0.3)
            } else {
                bright
            }
            ZodiacBookLines(lines: entry.lines(collected).map { (place($0.0), place($0.1)) })
                .trim(from: 0, to: isStatic || formed || !revealsAroundStars ? 1 : 0)
                .stroke(.white.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .shadow(color: Color(hex: 0x7459DF), radius: 4)
            ForEach(entry.members) { member in
                if collected.contains(member.id) {
                    star(member.star).position(place(member.point))
                } else if revealsAroundStars {
                    Circle().strokeBorder(.white.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .frame(width: 12, height: 12).position(place(member.point))
                }
            }
        }
    }

    private func revealMask(rect: CGRect, done: Bool, place: @escaping (CGPoint) -> CGPoint) -> some View {
        ZStack {
            if done {
                Color.white.opacity(isStatic || formed ? 1 : 0)
            } else {
                // Each collected star lights a patch of the drawing; the patches grow with progress.
                let diameter = rect.width * (0.4 + 0.4 * entry.progress(collected))
                ForEach(entry.members.filter { collected.contains($0.id) }) { member in
                    Circle()
                        .fill(RadialGradient(colors: [.white, .white.opacity(0.5), .clear], center: .center,
                                             startRadius: 0, endRadius: diameter / 2))
                        .frame(width: diameter, height: diameter)
                        .scaleEffect(isStatic || formed ? 1 : 0.2)
                        .position(place(member.point))
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

/// The visible part of an artwork (non-transparent pixels plus its stars), 0...1.
nonisolated enum ZodiacArtBounds {
    static func bounds(of image: CGImage, including points: [CGPoint]) -> CGRect {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        if drawn {
            var minX = width, minY = height, maxX = -1, maxY = -1
            for y in 0..<height {
                for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 24 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            if maxX >= minX {
                // Bitmap rows run top to bottom in memory, matching the image's pixel order.
                rect = CGRect(x: Double(minX) / Double(width), y: Double(minY) / Double(height),
                              width: Double(maxX - minX + 1) / Double(width), height: Double(maxY - minY + 1) / Double(height))
            }
        }
        for point in points where point.x.isFinite && point.y.isFinite {
            rect = rect.union(CGRect(x: point.x - 0.02, y: point.y - 0.02, width: 0.04, height: 0.04))
        }
        return rect
    }
}

private struct ZodiacBookLines: Shape {
    /// Already in view coordinates.
    let lines: [(CGPoint, CGPoint)]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (a, b) in lines {
            path.move(to: a)
            path.addLine(to: b)
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
        // Figma card 177 × 244: artwork centred above the name and progress, on the exported card glow.
        VStack(alignment: .leading, spacing: 0) {
            ZodiacBookArt(entry: entry, collected: collected, revealsAroundStars: true, inset: 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.name).font(.title3.weight(.semibold)).foregroundStyle(.white)
                ZodiacBookProgress(entry: entry, collected: collected)
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
        }
        .aspectRatio(177 / 244, contentMode: .fit)
        .background { Image("background/background-constellation-card").resizable() }
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
    var onObjectSheetDismissed: () -> Void = {}
    @ViewBuilder let objectSheet: (GardenCollectionItem) -> ObjectSheet

    @State private var selected: GardenCollectionItem?
    @State private var showsShare = false

    var body: some View {
        let collected = Set(model.collected.keys)
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    header(collected, topInset: proxy.safeAreaInsets.top, width: proxy.size.width)
                    stars(collected)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
        }
        // One base colour under everything: the exported glow fades into it, and so does the star panel.
        .background(Color.bookPrimary.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Share constellation", systemImage: "square.and.arrow.up") {
                    showsShare = true
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $selected) { objectSheet($0) }
        .fullScreenCover(isPresented: $showsShare) {
            ConstellationShareView(
                entry: entry,
                collected: Set(model.collected.keys)
            )
        }
    }

    private func header(_ collected: Set<Int>, topInset: CGFloat, width: CGFloat) -> some View {
        VStack(spacing: 8) {
            ZodiacBookArt(entry: entry, collected: collected, revealsAroundStars: true, inset: 8)
                .frame(height: 230)
            Text(entry.name).font(.title.weight(.bold)).foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            ZodiacBookProgress(entry: entry, collected: collected).frame(width: 214)
        }
        .padding(.horizontal, 16).padding(.top, topInset + 8).padding(.bottom, 56)
        .frame(maxWidth: .infinity)
        // Figma 402 × 474 glow, pinned to the top of the screen and scrolling with the page.
        .background(alignment: .top) {
            Image("background/background-constellation-detail").resizable()
                .frame(width: width, height: width * 474 / 402)
        }
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
                .fill(Color.bookPrimary)
                .padding(.bottom, -600)
        }
        .padding(.top, -32)
    }

    private func row(_ star: CatalogStar, collected: Bool) -> some View {
        HStack(spacing: 16) {
            StarPortraitView(star: star).frame(width: 48, height: 48)
            Text(star.title).font(.headline).foregroundStyle(.white)
            Spacer(minLength: 8)
            // A status label, not a control: flat capsule, no glass.
            Text(collected ? "Collected" : "Not collected")
                .font(.footnote.weight(.medium))
                .foregroundStyle(collected ? .white : .white.opacity(0.7))
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Capsule().fill(collected ? CelyxColor.accent : .white.opacity(0.08)))
                .overlay(Capsule().strokeBorder(.white.opacity(collected ? 0.25 : 0.12), lineWidth: 0.5))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.bookSecondary))
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
