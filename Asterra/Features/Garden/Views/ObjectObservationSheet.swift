import SwiftUI

/// One garden object, with a separate log entry for each saved observation.
struct ObjectObservationSheet: View {
    let item: GardenCollectionItem
    let model: HomeViewModel
    var allowsCompact = true
    var onGuide: (() -> Void)? = nil

    private static let compact: PresentationDetent = .height(220)
    @State private var detent = Self.compact
    @State private var selectedCapture: UUID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    private var history: [CollectedStar] { model.observationHistory(for: item.id) }
    private var supportsCompact: Bool { allowsCompact && !typeSize.isAccessibilitySize }
    private var isExpanded: Bool { !supportsCompact || detent == .large }

    var body: some View {
        CelyxSheetScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    StarPortraitView(star: item.star)
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.star.title).font(.title.bold())
                        Text(item.albumSubtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    CelyxCloseButton { dismiss() }
                }
                Text(fact).foregroundStyle(.secondary)
                if isExpanded {
                    HStack(alignment: .top, spacing: 12) {
                        metric(history.count.formatted(), label: "Observations")
                        metric(history.compactMap { $0.lightPollution?.bortleClass }.min()
                            .map { "\($0)/9" } ?? "Unavailable", label: "Best Bortle")
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text("Observation log").font(.headline)
                        Spacer()
                        if let first = history.last?.date, let last = history.first?.date {
                            Text(Date.IntervalFormatStyle().month(.abbreviated).day().year().format(first..<last))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    LazyVStack(spacing: 12) {
                        ForEach(history, id: \.captureID) { record in
                            Button {
                                selectedCapture = record.captureID
                            } label: {
                                ObservationLogRow(item: GardenCollectionItem(star: item.star, record: record))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            if isExpanded, let onGuide {
                StartCollectingButton(title: "Find in the sky", identifier: "guide-to-collected-object") {
                    dismiss()
                    onGuide()
                }
                .padding(.horizontal, 20).padding(.vertical, 8)
            }
        }
        .presentationDetents(supportsCompact ? [Self.compact, .large] : [.large],
                             selection: supportsCompact ? $detent : .constant(.large))
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: Binding(
            get: { selectedCapture != nil },
            set: { if !$0 { selectedCapture = nil } }
        ), onDismiss: { if history.isEmpty { dismiss() } }) {
            if let selectedCapture, let record = model.observation(captureID: selectedCapture) {
                CaptureDetailView(item: GardenCollectionItem(star: item.star, record: record), model: model) {
                    self.selectedCapture = nil
                }
                .background(CelyxColor.night.ignoresSafeArea())
            }
        }
    }

    private var fact: String {
        if item.star.title == "Rigel" {
            return "Rigel is a blue supergiant star in Orion that shines about 120,000 times brighter than our Sun."
        }
        if item.star.isMoon { return "The same side of the Moon always faces Earth." }
        if item.star.isPlanet { return "Planets change position against the background stars as they orbit the Sun." }
        if item.star.distance_ly == nil {
            return "\(item.star.title) has an apparent magnitude of \(item.star.mag.formatted()). Lower magnitudes mean brighter stars."
        }
        return StarShareContent(item: item, collectionNumber: nil).lightTravel
    }

    private func metric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title2.bold())
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

private struct ObservationLogRow: View {
    let item: GardenCollectionItem
    @State private var photo: UIImage?
    @State private var place: String?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.quaternary)
                }
            }
            .frame(width: 112, height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.record.date, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                    .font(.footnote).foregroundStyle(.secondary)
                Text(place ?? item.record.placeName ?? item.coordinates).font(.body.weight(.semibold))
                if let score = item.record.lightPollution?.bortleClass {
                    HStack(spacing: 4) {
                        ForEach(1...9, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(index <= score ? Color.indigo : Color.secondary.opacity(0.2))
                                .frame(maxWidth: 12).frame(height: 12)
                        }
                    }
                    .accessibilityHidden(true)
                    Text("Bortle \(score)").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Bortle unavailable").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24))
        .task(id: item.record.photoFilename) { photo = StarPhotoStore.load(item.record.photoFilename) }
        .task {
            guard item.record.placeName == nil else { return }
            place = await ObservationPlaceName.shared.resolve(
                latitude: item.record.latitude, longitude: item.record.longitude)
        }
        .accessibilityElement(children: .combine)
    }
}

struct CaptureDetailView: View {
    let item: GardenCollectionItem
    let model: HomeViewModel
    var startsWithNoteEntry = false
    var capturedPhoto: UIImage? = nil
    var tourGuide = false
    var onTourBack: (() -> Void)? = nil
    let onDeleted: () -> Void

    var body: some View {
        let captureID = item.record.captureID
        let history = model.observationHistory(for: item.id).reversed()
        let index = history.enumerated().first { $0.element.captureID == captureID }?.offset
        CollectedObjectSheet(item: item, direction: nil, collection: model,
            capturedPhoto: capturedPhoto, startsWithNoteEntry: startsWithNoteEntry,
            observationNumber: tourGuide ? nil : index.map { "Observation \($0 + 1) of \(history.count)" },
            onSaveNote: { if let captureID { model.updateObservationNote(captureID: captureID, note: $0) } },
            onSavePlace: { if let captureID { model.updateObservationPlace(captureID: captureID, name: $0) } },
            tourGuide: tourGuide, onTourBack: onTourBack,
            onDelete: {
                if let captureID { model.deleteObservation(captureID: captureID) }
                onDeleted()
            })
    }
}
