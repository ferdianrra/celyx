import SwiftUI

/// Shared native sheet for post-capture notes and collected-object details.
struct CollectedObjectSheet: View {
    let item: GardenCollectionItem
    let direction: SIMD3<Double>?
    var collection: HomeViewModel? = nil
    var capturedPhoto: UIImage? = nil
    var startsWithNoteEntry = false
    var observationNumber: String?
    var onSaveNote: ((String) -> Void)? = nil
    var onSavePlace: ((String) -> Void)? = nil
    /// Onboarding tour: guide lines in the sheet, a glowing close button and no Delete.
    var tourGuide = false
    var onNoteCompleted: (() -> Void)? = nil
    var onTourBack: (() -> Void)? = nil
    let onDelete: () -> Void

    @FocusState private var noteFocused: Bool
    @State private var confirmsDelete = false
    @State private var showsShare = false
    @State private var placeName: String?
    @State private var photo: UIImage?
    @State private var note = ""
    @State private var editingNote = false
    @State private var compactNoteEntry = false
    @State private var noteBounds: CGRect = .null
    @State private var initialized = false
    @State private var noteContentHeight: CGFloat = 300
    @State private var containerBottomInset: CGFloat = 0
    @State private var detent: PresentationDetent = .large
    @State private var randomPlaceholder = CollectedObjectSheet.notePlaceholders.randomElement()
        ?? "Write a note…"
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(item: GardenCollectionItem, direction: SIMD3<Double>?, collection: HomeViewModel? = nil,
         capturedPhoto: UIImage? = nil, startsWithNoteEntry: Bool = false,
         observationNumber: String? = nil,
         onSaveNote: ((String) -> Void)? = nil, onSavePlace: ((String) -> Void)? = nil,
         tourGuide: Bool = false, onNoteCompleted: (() -> Void)? = nil,
         onTourBack: (() -> Void)? = nil, onDelete: @escaping () -> Void) {
        self.onTourBack = onTourBack
        self.tourGuide = tourGuide
        self.onNoteCompleted = onNoteCompleted
        self.item = item; self.direction = direction; self.collection = collection
        self.capturedPhoto = capturedPhoto; self.startsWithNoteEntry = startsWithNoteEntry
        self.observationNumber = observationNumber
        self.onSaveNote = onSaveNote; self.onSavePlace = onSavePlace; self.onDelete = onDelete
        _note = State(initialValue: (item.record.captureID.flatMap { collection?.observation(captureID: $0) } ?? item.record).note ?? "")
        _editingNote = State(initialValue: startsWithNoteEntry)
        _compactNoteEntry = State(initialValue: startsWithNoteEntry)
        _detent = State(initialValue: startsWithNoteEntry ? .height(300) : .large)
        _photo = State(initialValue: capturedPhoto)
    }

    private var noteSheetHeight: CGFloat { max(1, noteContentHeight - containerBottomInset) }

    private var displayedItem: GardenCollectionItem {
        var record = item.record.captureID.flatMap { collection?.observation(captureID: $0) } ?? item.record
        record.note = note
        record.placeName = placeName ?? record.placeName
        return GardenCollectionItem(star: item.star, record: record)
    }
    private var content: StarShareContent { .init(item: displayedItem, collectionNumber: nil) }

    var body: some View {
        CelyxSheetScrollView(showsArtwork: startsWithNoteEntry || observationNumber == nil) {
            VStack(alignment: .leading, spacing: 0) {
                if tourGuide, let onTourBack {
                    Button("Back", systemImage: "chevron.left") {
                        onTourBack()
                        dismiss()
                    }
                    .buttonStyle(.glass)
                    .padding(.horizontal, 20).padding(.top, 20)
                }
                header.padding(.horizontal, 20).padding(.top, 32)
                VStack(spacing: 12) {
                    if tourGuide && !editingNote {
                        OnboardingGuidePill(text: OnboardingCopy.starCardGuide,
                            symbol: "info.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                    }
                    notes
                    if !compactNoteEntry {
                        capturePhoto
                        metadata
                        VStack(spacing: 12) {
                            Button { showsShare = true } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                                    .font(.body).frame(maxWidth: .infinity)
                            }
                                .buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.large)
                                .accessibilityIdentifier("share-collected-star")
                            if !tourGuide {
                            Button(role: .destructive) { confirmsDelete = true } label: {
                                Label("Delete", systemImage: "trash")
                                    .font(.body).frame(maxWidth: .infinity, minHeight: 44)
                            }
                                .buttonStyle(.borderless).foregroundStyle(.red)
                                .accessibilityIdentifier("delete-collected-star")
                            }
                        }.padding(.top, 12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, compactNoteEntry ? 16 : 0)
            }
            .contentShape(Rectangle())
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                guard compactNoteEntry, height > 0 else { return }
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
            if compactNoteEntry { detent = .height(height) }
        }
        .coordinateSpace(name: "collected-object-sheet")
        .simultaneousGesture(SpatialTapGesture(coordinateSpace: .named("collected-object-sheet")).onEnded { tap in
            guard editingNote, !compactNoteEntry, !noteBounds.isNull,
                  !noteBounds.contains(tap.location) else { return }
            finishNote()
        })
        .overlay(alignment: .topTrailing) {
            if !showsDetailHeader { closeButton.padding(.top, 32).padding(.trailing, 20) }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.never)
        .foregroundStyle(.primary)
        .presentationDetents(compactNoteEntry ? [.height(noteSheetHeight)] : [.large], selection: $detent)
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .task {
            guard !initialized else { return }
            initialized = true
            note = (item.record.captureID.flatMap { collection?.observation(captureID: $0) } ?? item.record).note ?? ""
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
            let record = item.record.captureID.flatMap { collection?.observation(captureID: $0) } ?? item.record
            guard record.placeName == nil else { return }
            if let name = await ObservationPlaceName.shared.resolve(latitude: record.latitude, longitude: record.longitude) {
                placeName = name
                onSavePlace?(name)
            }
        }
        .onDisappear { if initialized { onSaveNote?(note.trimmingCharacters(in: .whitespacesAndNewlines)) } }
        .confirmationDialog(observationNumber == nil ? "Delete \(item.star.title)?" : "Delete this observation?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { onDelete(); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This deletes the photo and note for this observation.") }
        .fullScreenCover(isPresented: $showsShare) {
            StarShareView(item: displayedItem, collection: collection, capturedPhoto: photo)
        }
    }

    private var closeButton: some View {
        Button(startsWithNoteEntry || observationNumber == nil ? "Close" : "Back",
               systemImage: startsWithNoteEntry || observationNumber == nil ? "xmark" : "chevron.left") {
            onSaveNote?(note.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss()
        }
        .labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
        .background {
            // Tour: once the card is shown, the way back breathes softly.
            if tourGuide && !editingNote {
                OnboardingHighlight(size: CGSize(width: 48, height: 48)).transition(.opacity)
            }
        }
        .accessibilityIdentifier("close-collected-star")
    }

    private var showsDetailHeader: Bool { observationNumber != nil && !startsWithNoteEntry }

    @ViewBuilder private var header: some View {
        if showsDetailHeader {
            HStack(spacing: 12) {
                closeButton
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.star.title).font(.title.bold())
                    Text(observationNumber ?? "").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                StarPortraitView(star: item.star).frame(width: 64, height: 64)
                    .accessibilityHidden(true)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    HStack(spacing: 12) {
                        StarPortraitView(star: item.star).frame(width: 56, height: 56)
                            .shadow(color: .white.opacity(0.35), radius: 8).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.star.title).font(.title.bold()).fixedSize(horizontal: false, vertical: true)
                            Text(observationNumber ?? item.albumSubtitle).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
                }
                if observationNumber == nil {
                    Text(content.lightTravel).font(.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !compactNoteEntry {
                HStack {
                    Text("Note").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        editingNote = true
                    } label: {
                        Image(systemName: "pencil")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                        .buttonStyle(.borderless)
                        .disabled(editingNote)
                        .accessibilityLabel("Edit note")
                        .accessibilityIdentifier("edit-collected-star-note")
                }
                .padding(.bottom, 4)
            }
            if editingNote {
                TextField(notePlaceholder, text: $note, axis: .vertical)
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
                Text(note.isEmpty ? "Add a note…" : note)
                    .font(.body).foregroundStyle(note.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("collected-star-note")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 32))
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named("collected-object-sheet"))
        } action: { noteBounds = $0 }
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
        }
        .frame(height: 236)
        .clipShape(RoundedRectangle(cornerRadius: 32))
        // The scaled photo extends past its crop and must not intercept taps on the note.
        .allowsHitTesting(false)
            .accessibilityIdentifier("collected-star-photo")
    }
    private var notePlaceholder: String {
        if tourGuide {
            return item.star.isSun
                ? "What did the sunlight look like, and how did this moment feel?"
                : "What did you notice, where were you, and how did this moment feel?"
        }
        return randomPlaceholder
    }

    private var metadata: some View {
        VStack(spacing: 12) {
            information("Location", value: displayedItem.albumLocation, symbol: "location")
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                information("Light Pollution", value: displayedItem.record.lightPollution.map { "Bortle \($0.bortleClass)/9" } ?? "Unavailable", symbol: "light.max")

                if content.hasLightPollution {
                    Link("Estimate by DarkSkySites.com", destination: URL(string: "https://darkskysites.com")!)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
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
        if tourGuide {
            dismiss()
            return
        }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            editingNote = false
            compactNoteEntry = false
            detent = .large
        }
        onNoteCompleted?()
    }
}

private extension CollectedObjectSheet {
    static let notePlaceholders = [
        "What caught your eye tonight?",
        "How did this moment feel?",
        "Where were you when you saw this?",
        "Who were you with?",
        "What made this moment special?",
        "What made you look up at the sky?",
        "If you could give this moment a title, what would it be?",
        "What feeling does this discovery leave you with?",
        "What surprised you about this discovery?",
        "What did the sky look like?",
        "How would you describe this experience in three words?",
        "If this discovery had a story, what would it be?",
        "How did you feel when you found it?",
        "Who were you with when you spotted it?",
        "What do you want to remember?"
    ]
}

#Preview {
    CollectedObjectSheet(item: AppPreviewData.item, direction: nil, capturedPhoto: AppPreviewData.albumPhoto, onDelete: {})
}
