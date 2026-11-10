import SwiftUI

/// Shared native sheet for post-capture notes and collected-object details.
struct CollectedObjectSheet: View {
    let item: GardenCollectionItem
    let direction: SIMD3<Double>?
    var collection: HomeViewModel? = nil
    var capturedPhoto: UIImage? = nil
    var startsWithNoteEntry = false
    var onSaveNote: ((String) -> Void)? = nil
    var onSavePlace: ((String) -> Void)? = nil
    let onDelete: () -> Void

    @FocusState private var noteFocused: Bool
    @State private var confirmsDelete = false
    @State private var showsShare = false
    @State private var placeName: String?
    @State private var photo: UIImage?
    @State private var note = ""
    @State private var editingNote = false
    @State private var initialized = false
    @State private var noteContentHeight: CGFloat = 300
    @State private var containerBottomInset: CGFloat = 0
    @State private var detent: PresentationDetent = .large
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(item: GardenCollectionItem, direction: SIMD3<Double>?, collection: HomeViewModel? = nil,
         capturedPhoto: UIImage? = nil, startsWithNoteEntry: Bool = false,
         onSaveNote: ((String) -> Void)? = nil, onSavePlace: ((String) -> Void)? = nil,
         onDelete: @escaping () -> Void) {
        self.item = item; self.direction = direction; self.collection = collection
        self.capturedPhoto = capturedPhoto; self.startsWithNoteEntry = startsWithNoteEntry
        self.onSaveNote = onSaveNote; self.onSavePlace = onSavePlace; self.onDelete = onDelete
        _note = State(initialValue: (collection?.collected[item.id] ?? item.record).note ?? "")
        _editingNote = State(initialValue: startsWithNoteEntry)
        _detent = State(initialValue: startsWithNoteEntry ? .height(300) : .large)
        _photo = State(initialValue: capturedPhoto)
    }

    private var noteSheetHeight: CGFloat { max(1, noteContentHeight - containerBottomInset) }

    private var displayedItem: GardenCollectionItem {
        var record = collection?.collected[item.id] ?? item.record
        record.note = note
        record.placeName = placeName ?? record.placeName
        return GardenCollectionItem(star: item.star, record: record)
    }
    private var content: StarShareContent { .init(item: displayedItem, collectionNumber: nil) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.horizontal, 20).padding(.top, 32)
                VStack(spacing: 12) {
                    notes
                    if !editingNote {
                        capturePhoto
                        metadata
                        VStack(spacing: 12) {
                            Button { showsShare = true } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                                    .font(.body).frame(maxWidth: .infinity)
                            }
                                .buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.large)
                                .accessibilityIdentifier("share-collected-star")
                            Button(role: .destructive) { confirmsDelete = true } label: {
                                Label("Delete", systemImage: "trash")
                                    .font(.body).frame(maxWidth: .infinity, minHeight: 50)
                            }
                                .buttonStyle(.borderless).foregroundStyle(.red)
                                .accessibilityIdentifier("delete-collected-star")
                        }.padding(.top, 12)
                    }
                }.padding(16)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                guard editingNote, height > 0 else { return }
                // Size the native detent to its content, including the same 16pt bottom/side inset.
                let fitted = ceil(height)
                if abs(noteContentHeight - fitted) > 0.5 { noteContentHeight = fitted }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { inset in
            // Capture the container inset before keyboard presentation; ignore the keyboard's inset.
            if inset > 0, inset < 100 { containerBottomInset = inset }
        }
        .onChange(of: noteSheetHeight) { _, height in
            if editingNote { detent = .height(height) }
        }
        .overlay(alignment: .topTrailing) { closeButton.padding(.top, 32).padding(.trailing, 20) }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.never)
        .foregroundStyle(.primary)
        .presentationDetents(editingNote ? [.height(noteSheetHeight)] : [.large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackground { CelyxBluePanel() }
        .preferredColorScheme(.dark)
        .task {
            guard !initialized else { return }
            initialized = true
            note = (collection?.collected[item.id] ?? item.record).note ?? ""
            editingNote = startsWithNoteEntry
            detent = startsWithNoteEntry ? .height(noteSheetHeight) : .large
            photo = capturedPhoto ?? StarPhotoStore.load(item.record.photoFilename)
        }
        .task(id: editingNote) {
            guard editingNote else { noteFocused = false; return }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            noteFocused = true
        }
        .task(id: item.id) {
            let record = collection?.collected[item.id] ?? item.record
            guard record.placeName == nil else { return }
            if let name = await ObservationPlaceName.shared.resolve(latitude: record.latitude, longitude: record.longitude) {
                placeName = name
                onSavePlace?(name)
            }
        }
        .onDisappear { if initialized { onSaveNote?(note.trimmingCharacters(in: .whitespacesAndNewlines)) } }
        .confirmationDialog("Delete \(item.star.title)?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { onDelete(); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("It will leave your garden, along with its photo and note.") }
        .fullScreenCover(isPresented: $showsShare) {
            StarShareView(item: displayedItem, collection: collection, capturedPhoto: photo)
        }
    }

    private var closeButton: some View {
        Button("Close", systemImage: "xmark") {
            onSaveNote?(note.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss()
        }
        .labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
        .accessibilityIdentifier("close-collected-star")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                HStack(spacing: 12) {
                    StarPortraitView(star: item.star).frame(width: 56, height: 56)
                        .shadow(color: .white.opacity(0.35), radius: 8).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.star.title).font(.title.bold()).fixedSize(horizontal: false, vertical: true)
                        Text(item.albumSubtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
            }
            Text(content.lightTravel).font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notes").font(.callout).foregroundStyle(.secondary)
            if editingNote {
                TextField("Write a note…", text: $note, axis: .vertical)
                    .font(.body).textFieldStyle(.plain)
                    .lineLimit(4...4)
                    .focused($noteFocused)
                    .submitLabel(.done)
                    .onSubmit(finishNote)
                    .onChange(of: note) { old, new in
                        guard editingNote else { return }
                        // A vertical TextField inserts Return into its binding. Treat a single
                        // newline keystroke as Done, while allowing pasted multiline notes.
                        let changes = Array(new.difference(from: old))
                        if changes.count == 1, case .insert(_, "\n", _) = changes[0] {
                            note = old
                            finishNote()
                        }
                    }
                    .accessibilityLabel("Notes")
                    .accessibilityIdentifier("collection-note-editor")
            } else {
                Button {
                    editingNote = true; detent = .height(noteSheetHeight)
                } label: {
                    Text(note.isEmpty ? "Add a note…" : note)
                        .font(.body).foregroundStyle(note.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }.buttonStyle(.plain)
                    .accessibilityLabel(note.isEmpty ? "Add a note" : "Edit note: \(note)")
                    .accessibilityIdentifier("collected-star-note")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 32))
    }

    private var capturePhoto: some View {
        GeometryReader { geometry in
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    .accessibilityLabel("Your photo of \(item.star.title)")
            } else {
                ContentUnavailableView("Photo unavailable", systemImage: "photo")
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(.tertiary)
            }
        }.frame(height: 236).clipShape(RoundedRectangle(cornerRadius: 32))
            .accessibilityIdentifier("collected-star-photo")
    }

    private var metadata: some View {
        VStack(spacing: 12) {
            information("Location", value: displayedItem.albumLocation, symbol: "location")
            Divider()
            information("Light Pollution", value: content.lightPollution, symbol: "light.max")
            Divider()
            information("Date", value: content.date, symbol: "calendar")
            Divider()
            information("Time", value: content.time, symbol: "clock")
        }
        .padding(20).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 32))
    }
    private func information(_ label: String, value: String, symbol: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.callout).foregroundStyle(.secondary)
                Text(value).font(.body.weight(.semibold)).textSelection(.enabled)
            }
            Spacer(minLength: 12)
            Image(systemName: symbol).font(.body).accessibilityHidden(true)
        }.accessibilityElement(children: .combine)
    }
    private func finishNote() {
        guard editingNote else { return }
        noteFocused = false
        note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        onSaveNote?(note)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            editingNote = false; detent = .large
        }
    }
}

#Preview {
    CollectedObjectSheet(item: AppPreviewData.item, direction: nil, capturedPhoto: AppPreviewData.albumPhoto, onDelete: {})
        .presentationBackground { CelyxBluePanel() }
}
