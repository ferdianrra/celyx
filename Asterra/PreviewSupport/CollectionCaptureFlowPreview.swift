#if DEBUG
import SwiftUI

/// Exercises the production sheet component with an isolated collection and a saved-photo fixture.
struct CollectionCaptureFlowPreview: View {
    private enum Route: String, Identifiable { case detail; var id: String { rawValue } }
    @State private var route: Route?
    @State private var captureRequest: GardenSheetRequest?
    @State private var camera = NightSeaCamera()
    @State private var collection = StarSharePreviewData.model()
    private var item: GardenCollectionItem? { collection.collectionItems.first { $0.id == StarSharePreviewData.item.id } }
    var body: some View {
        ZStack {
            GardenSkyView(model: collection, camera: $camera, isActive: false, usesGyro: false,
                          sheetRequest: captureRequest).ignoresSafeArea()
            VStack(spacing: 24) {
                Button("Finish capture") {
                    collection.updateObservationNote(id: StarSharePreviewData.item.id, note: "")
                    captureRequest = GardenSheetRequest(itemID: StarSharePreviewData.item.id, photo: AppPreviewData.albumPhoto)
                }.accessibilityIdentifier("preview-finish-capture")
                if item != nil {
                    Button("Rigel") { route = .detail }.accessibilityIdentifier("preview-collected-star")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Image("asterra-share-background").resizable().scaledToFill().ignoresSafeArea() }
        .preferredColorScheme(.dark)
        .sheet(item: $route) { current in
            if let item {
                CollectedObjectSheet(item: item, direction: nil, collection: collection,
                    capturedPhoto: AppPreviewData.albumPhoto, startsWithNoteEntry: false,
                    onSaveNote: { collection.updateObservationNote(id: item.id, note: $0) },
                    onDelete: { collection.deleteCollected(id: item.id); route = nil })
                    .id(current.id)
            }
        }
    }
}
#endif
