import SwiftUI

struct StarAlbumView: View {
    let item: GardenCollectionItem
    var onSaveNote: ((String) -> Void)? = nil
    var onSavePlace: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var note: String
    @State private var placeName: String?
    @State private var showsExport = false
    @State private var showsInfo = false
    @State private var showsNote = false
    private let capturedPhoto: UIImage?
    private var photo: UIImage? { capturedPhoto ?? StarPhotoStore.load(item.record.photoFilename) }
    private var displayedItem: GardenCollectionItem {
        var record = item.record; record.note = note; record.placeName = placeName
        return GardenCollectionItem(star:item.star,record:record)
    }
    init(item: GardenCollectionItem,photo: UIImage? = nil,onSaveNote: ((String) -> Void)? = nil,
         onSavePlace: ((String) -> Void)? = nil) {
        self.item = item; self.onSaveNote = onSaveNote
        self.onSavePlace = onSavePlace
        capturedPhoto = photo
        _note = State(initialValue:item.record.note ?? "")
        _placeName = State(initialValue:item.record.placeName)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    HStack(spacing:12) {
                        StarPortraitView(star:item.star).frame(width:48,height:48)
                        VStack(alignment:.leading,spacing:3) {
                            Text(item.star.title).font(.title2.bold())
                            Text(item.albumSubtitle).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    StarAlbumPaper(item:displayedItem,photo:photo)
                    if onSaveNote != nil {
                        Button("Add or edit your note",systemImage:"square.and.pencil") { showsNote = true }
                            .font(.subheadline).tint(.white)
                    }
                }
                .padding(22).frame(maxWidth:430)
                .background { StarAlbumSurface() }
                .padding(.horizontal,16).padding(.vertical,20)
                .frame(maxWidth:.infinity)
            }
            .background(CelyxColor.night)
            .navigationTitle("Your sky album").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button("Close",systemImage:"xmark") { dismiss() }.labelStyle(.iconOnly)
                }
                ToolbarItemGroup(placement:.primaryAction) {
                    Button("Observation info",systemImage:"info.circle") { showsInfo = true }
                    Button("Export story",systemImage:"square.and.arrow.up") { showsExport = true }
                        .accessibilityIdentifier("export-star-story")
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            guard placeName == nil else { return }
            if let name = await ObservationPlaceName.shared.resolve(latitude:item.record.latitude,longitude:item.record.longitude) {
                placeName = name; onSavePlace?(name)
            }
        }
        .sheet(isPresented:$showsExport) { StarStoryExportView(item:displayedItem,photo:photo) }
        .sheet(isPresented:$showsInfo) {
            NavigationStack {
                Form {
                    LabeledContent("Captured",value:item.albumDate)
                    LabeledContent("Location",value:displayedItem.albumLocation)
                    LabeledContent("Coordinates",value:item.coordinates)
                    if let identification = item.record.identificationNote {
                        Section("Identification") { Text(identification).font(.callout) }
                    }
                }
                .navigationTitle("Observation").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { showsInfo = false } } }
            }.presentationDetents([.medium,.large])
        }
        .sheet(isPresented:$showsNote) {
            NavigationStack {
                Form { TextField("What made this moment special?",text:$note,axis:.vertical).lineLimit(4...10) }
                    .navigationTitle("About this moment").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement:.confirmationAction) {
                        Button("Done") { onSaveNote?(note); showsNote = false }
                    } }
            }.presentationDetents([.medium])
        }
    }
}

#Preview("Sky album") { StarAlbumView(item:AppPreviewData.item,onSaveNote:{ _ in }) }
