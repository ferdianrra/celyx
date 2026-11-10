import Foundation
import Photos
import UIKit
import UniformTypeIdentifiers

enum StarSharePhotoSaver {
    enum Failure: LocalizedError {
        case permission, rendering
        var errorDescription: String? {
            switch self {
            case .permission: "Allow Asterra to add photos in Settings to save your card."
            case .rendering: "The share card couldn’t be created. Please try again."
            }
        }
    }
    static func save(_ image: UIImage, title: String) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.permission }
        let data = await Task.detached(priority: .userInitiated) { image.pngData() }.value
        guard let data else { throw Failure.rendering }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.uniformTypeIdentifier = UTType.png.identifier
            options.originalFilename = "Asterra-\(title.replacingOccurrences(of: "/", with: "-")).png"
            request.addResource(with: .photo, data: data, options: options)
        }
    }
}
