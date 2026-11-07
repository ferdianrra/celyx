import SwiftUI

/// Details of one collected object in the garden, with Delete.
struct CollectedObjectSheet: View {
    let item: GardenCollectionItem
    /// Where it is in the sky right now (horizon frame), if it could be placed.
    let direction: SIMD3<Double>?
    var onSaveNote: ((String) -> Void)? = nil
    var onSavePlace: ((String) -> Void)? = nil
    let onDelete: () -> Void
    @State private var confirmsDelete = false
    @State private var showsAlbum = false
    @State private var editedNote: String?
    @State private var placeName: String?
    @Environment(\.dismiss) private var dismiss

    private var star: CatalogStar { item.star }
    private var photo: UIImage? { StarPhotoStore.load(item.record.photoFilename) }
    private var albumItem: GardenCollectionItem {
        var record = item.record
        if let editedNote { record.note = editedNote }
        record.placeName = placeName ?? record.placeName
        return GardenCollectionItem(star:item.star,record:record)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    HStack(spacing:16) {
                        StarPortraitView(star:star)
                            .frame(width:64,height:64)
                            .shadow(color:Color(red:star.rgb.x,green:star.rgb.y,blue:star.rgb.z).opacity(0.7),radius:10)
                            .accessibilityHidden(true)
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                        Spacer(minLength:0)
                    }

                    if let photo {
                        Image(uiImage:photo).resizable().scaledToFill()
                            .frame(maxWidth:.infinity).frame(height:200)
                            .clipShape(RoundedRectangle(cornerRadius:16,style:.continuous))
                            .accessibilityLabel("Your photo of \(star.title)")
                    }
                    Button("Open sky album",systemImage:"photo.on.rectangle.angled") { showsAlbum = true }
                        .buttonStyle(.bordered).tint(.white)
                        .accessibilityIdentifier("open-star-album")

                    infoRow(symbol:"calendar",label:"Collected",value:item.record.date.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(Locale(identifier:"en_US"))))
                    infoRow(symbol:"location",label:"Where you were",value:albumItem.albumLocation)
                    infoRow(symbol:"safari",label:"In the sky right now",value:skyPosition)
                    if let note = editedNote ?? item.record.note, !note.isEmpty {
                        infoRow(symbol:"note.text",label:"Your note",value:note)
                    }
                    if let identification = item.record.identificationNote {
                        Text(identification).font(.system(size:12)).foregroundStyle(.white.opacity(0.5))
                    }

                    Button(role:.destructive) { confirmsDelete = true } label: {
                        Label("Delete from garden",systemImage:"trash")
                            .font(.system(size:17,weight:.semibold))
                            .frame(maxWidth:.infinity).frame(height:48)
                            .background(Capsule().fill(Color.red.opacity(0.18)))
                            .foregroundStyle(.red)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top,4)
                    .confirmationDialog("Delete \(star.title)?",isPresented:$confirmsDelete,titleVisibility:.visible) {
                        Button("Delete",role:.destructive,action:onDelete)
                        Button("Cancel",role:.cancel) {}
                    } message: {
                        Text("It will leave your garden, along with its photo and note.")
                    }
                }
                .padding(.horizontal,20).padding(.top,12).padding(.bottom,20)
            }
            .scrollIndicators(.hidden)
            .navigationTitle(star.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) {
                    Button("Close",systemImage:"xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
            }
        }
        .presentationDetents([.medium,.large])
        .presentationDragIndicator(.visible)
        .presentationBackground { CelyxBluePanel() }
        .preferredColorScheme(.dark)
        .task {
            guard item.record.placeName == nil else { return }
            if let name = await ObservationPlaceName.shared.resolve(latitude:item.record.latitude,longitude:item.record.longitude) {
                placeName = name; onSavePlace?(name)
            }
        }
        .fullScreenCover(isPresented:$showsAlbum) {
            StarAlbumView(item:albumItem,onSaveNote:onSaveNote == nil ? nil : { note in
                editedNote = note; onSaveNote?(note)
            },onSavePlace:onSavePlace)
        }
    }

    private var subtitle: String {
        if star.isSolarSystemBody { return star.kind }
        if let code = star.con, let name = ConstellationNames.name(for:code) { return "Star in \(name)" }
        return "Star"
    }
    private var skyPosition: String {
        guard let direction else { return "Not available" }
        let altitude = asin(min(1,max(-1,direction.z)))*180 / .pi
        guard altitude > 0 else { return "Below the horizon" }
        let azimuth = (atan2(direction.x,direction.y)*180 / .pi+360).truncatingRemainder(dividingBy:360)
        let points = ["north","northeast","east","southeast","south","southwest","west","northwest"]
        return String(format:"%.0f° up, toward the %@",altitude,points[Int((azimuth+22.5)/45) % 8])
    }
    private func infoRow(symbol: String,label: String,value: String) -> some View {
        HStack(spacing:12) {
            Image(systemName:symbol).font(.system(size:15)).foregroundStyle(.white).frame(width:30)
            VStack(alignment:.leading,spacing:6) {
                Text(label).font(.system(size:12)).foregroundStyle(.white.opacity(0.5))
                Text(value).font(.system(size:15,weight:.semibold)).foregroundStyle(.white)
                    .fixedSize(horizontal:false,vertical:true)
            }
            Spacer(minLength:0)
        }
        .padding(16)
        .background(CelyxInfoBox())
        .accessibilityElement(children:.combine)
    }
}

#Preview("Collected object") {
    CollectedObjectSheet(item:AppPreviewData.item,direction:SIMD3(0,0.8,0.6),onDelete:{})
        .preferredColorScheme(.dark)
}
