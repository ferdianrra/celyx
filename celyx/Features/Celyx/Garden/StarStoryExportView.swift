import SwiftUI
import Photos
import UniformTypeIdentifiers

enum StarStoryRenderer {
    static func png(item: GardenCollectionItem,photo: UIImage?) -> Data? {
        let renderer = ImageRenderer(content:StarStoryTemplate(item:item,photo:photo))
        renderer.scale = 3 // 1080 × 1920, independently of the phone's display scale.
        renderer.isOpaque = true
        return renderer.uiImage?.pngData()
    }
}

struct StarStoryExportView: View {
    let item: GardenCollectionItem
    let photo: UIImage?
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var saved = false
    @State private var permissionDenied = false
    @State private var errorMessage: String?
    @State private var placeName: String?
    private var displayedItem: GardenCollectionItem {
        var record = item.record
        record.placeName = placeName ?? record.placeName
        return GardenCollectionItem(star:item.star,record:record)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let scale = min((geometry.size.width-32)/360,(geometry.size.height-24)/640)
                StarStoryTemplate(item:displayedItem,photo:photo)
                    .clipShape(RoundedRectangle(cornerRadius:20))
                    .scaleEffect(max(0.1,scale))
                    .frame(width:geometry.size.width,height:geometry.size.height)
            }
            .background(CelyxColor.night)
            .navigationTitle("Story preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button("Close",systemImage:"xmark") { dismiss() }.labelStyle(.iconOnly)
                }
                ToolbarItem(placement:.primaryAction) {
                    Button(action:{ Task { await saveToPhotos() } }) {
                        if isSaving { ProgressView().accessibilityLabel("Saving to Photos") }
                        else { Label("Save to Photos",systemImage:"square.and.arrow.down") }
                    }
                    .disabled(isSaving).accessibilityIdentifier("save-story-png")
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            if item.record.placeName == nil {
                placeName = await ObservationPlaceName.shared.resolve(latitude:item.record.latitude,longitude:item.record.longitude)
            }
        }
        .alert(saved ? "Saved to Photos" : "Couldn’t save photo",isPresented:Binding(get:{ errorMessage != nil },set:{ if !$0 { errorMessage = nil } })) {
            Button("OK",role:.cancel) {}
            if permissionDenied {
                Button("Open Settings") {
                    if let url = URL(string:UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        } message: { Text(errorMessage ?? "") }
    }
    private func saveToPhotos() async {
        guard !isSaving else { return }
        isSaving = true; saved = false; permissionDenied = false
        defer { isSaving = false }
        let authorization = await PHPhotoLibrary.requestAuthorization(for:.addOnly)
        guard authorization == .authorized || authorization == .limited else {
            permissionDenied = authorization == .denied
            errorMessage = "Allow Celyx to add photos to save your story template to the gallery."; return
        }
        if item.record.placeName == nil, placeName == nil {
            placeName = await ObservationPlaceName.shared.resolve(latitude:item.record.latitude,longitude:item.record.longitude)
        }
        guard let data = StarStoryRenderer.png(item:displayedItem,photo:photo) else {
            errorMessage = "The template couldn’t be created. Please try again."; return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.uniformTypeIdentifier = UTType.png.identifier
                options.originalFilename = "Celyx-\(item.star.title).png"
                request.addResource(with:.photo,data:data,options:options)
            }
            saved = true; errorMessage = "Your story template has been saved to your photo library."
        } catch { errorMessage = error.localizedDescription }
    }
}

#Preview("PNG export") { StarStoryExportView(item:AppPreviewData.item,photo:nil) }
