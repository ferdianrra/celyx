import Foundation
import UIKit

@MainActor
enum StarSocialShare {
    enum Failure: LocalizedError {
        case notInstalled(String), instagramNotConfigured, image, open(String)
        var errorDescription: String? {
            switch self {
            case .notInstalled(let app): "Install \(app) to share this card there, or use More to choose another app."
            case .instagramNotConfigured: "Instagram Story sharing isn’t configured yet. You can still share your card using More or Save."
            case .image: "The share image couldn’t be prepared. Please try again."
            case .open(let app): "Couldn’t share the image with \(app). Try sharing your card using More."
            }
        }
    }

    static let instagramImageKey = "com.instagram.sharedSticker.backgroundImage"

    static func instagramURL(appID: String?) throws -> URL {
        let id = appID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw Failure.instagramNotConfigured
        }
        var url = URLComponents()
        url.scheme = "instagram-stories"
        url.host = "share"
        url.queryItems = [URLQueryItem(name: "source_application", value: id)]
        return url.url!
    }

    static func instagram(_ image: UIImage) async throws {
        let url = try instagramURL(appID: Bundle.main.object(forInfoDictionaryKey: "FacebookAppID") as? String)
        guard UIApplication.shared.canOpenURL(url) else { throw Failure.notInstalled("Instagram") }
        guard let data = image.pngData() else { throw Failure.image }
        // Instagram reads its background image from the pasteboard on opening its composer.
        // Expire the temporary payload rather than leaving the captured photo on the clipboard.
        UIPasteboard.general.setItems([[instagramImageKey: data]], options: [
            .expirationDate: Date().addingTimeInterval(300), .localOnly: true
        ])
        guard await UIApplication.shared.open(url) else { throw Failure.open("Instagram") }
    }

    /// A standard JPEG file for WhatsApp's share extension (also works with WhatsApp Business).
    static func whatsappFile(_ image: UIImage) throws -> WhatsAppShareRequest {
        guard let data = image.jpegData(compressionQuality: 0.95) else { throw Failure.image }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AsterraShares", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Remove abandoned handoffs from earlier app sessions; keep active/recent requests intact.
        let staleDate = Date().addingTimeInterval(-86400)
        for file in (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            if let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               date < staleDate { try? FileManager.default.removeItem(at: file) }
        }
        let file = directory.appendingPathComponent("Asterra-\(UUID().uuidString).jpg")
        try data.write(to: file, options: .atomic)
        return WhatsAppShareRequest(url: file)
    }
}

struct WhatsAppShareRequest: Identifiable {
    let id = UUID()
    let url: URL
    func removeFile() { try? FileManager.default.removeItem(at: url) }
}
