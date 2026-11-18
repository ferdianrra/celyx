import Foundation
import UIKit

@MainActor
enum StarSocialShare {
    enum Failure: LocalizedError {
        case notInstalled(String), instagramNotConfigured, image, open(String)
        var errorDescription: String? {
            switch self {
            case .notInstalled(let app): "Install \(app) to share this card there, or use More to choose another app."
            case .instagramNotConfigured: "Couldn’t identify Asterra for Instagram Stories. You can still use More or Save."
            case .image: "The share image couldn’t be prepared. Please try again."
            case .open(let app): "Couldn’t share the image with \(app). Try sharing your card using More."
            }
        }
    }

    static func instagramHandoff(imageData: Data, appID: String?, bundleID: String?) throws
        -> (url: URL, items: [String: Any])
    {
        let id = appID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasMetaID = !id.isEmpty && id.allSatisfy { $0.isASCII && $0.isNumber }
        guard let source = hasMetaID ? id : bundleID, !source.isEmpty else {
            throw Failure.instagramNotConfigured
        }
        var components = URLComponents()
        components.scheme = "instagram-stories"
        components.host = "share"
        components.queryItems = [URLQueryItem(name: "source_application", value: source)]
        guard let url = components.url else { throw Failure.instagramNotConfigured }

        if hasMetaID {
            return (url, ["com.instagram.sharedSticker.backgroundImage": imageData])
        }
        return (url, [
            "com.instagram.sharedSticker.stickerImage": imageData,
            "com.instagram.sharedSticker.backgroundTopColor": "#1C2450",
            "com.instagram.sharedSticker.backgroundBottomColor": "#080D20"
        ])
    }

    static func instagram(_ image: UIImage) async throws {
        guard let data = image.pngData() else { throw Failure.image }
        let handoff = try instagramHandoff(
            imageData: data,
            appID: Bundle.main.object(forInfoDictionaryKey: "FacebookAppID") as? String,
            bundleID: Bundle.main.bundleIdentifier
        )
        guard UIApplication.shared.canOpenURL(handoff.url) else { throw Failure.notInstalled("Instagram") }
        // Instagram reads the image from the pasteboard on opening its composer.
        // Expire the temporary payload rather than leaving the captured photo on the clipboard.
        UIPasteboard.general.setItems([handoff.items], options: [
            .expirationDate: Date().addingTimeInterval(300), .localOnly: true
        ])
        guard await UIApplication.shared.open(handoff.url) else { throw Failure.open("Instagram") }
    }

    /// A PNG file for the share sheet, preserving the card’s alpha channel.
    static func pngFile(_ image: UIImage) throws -> ShareCardFile {
        guard let data = image.pngData() else { throw Failure.image }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AsterraShares", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Remove abandoned handoffs from earlier app sessions; keep active/recent requests intact.
        let staleDate = Date().addingTimeInterval(-86400)
        for file in (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            if let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               date < staleDate { try? FileManager.default.removeItem(at: file) }
        }
        let file = directory.appendingPathComponent("Asterra-\(UUID().uuidString).png")
        try data.write(to: file, options: .atomic)
        return ShareCardFile(url: file)
    }
}

struct ShareCardFile: Identifiable {
    let id = UUID()
    let url: URL
    func removeFile() { try? FileManager.default.removeItem(at: url) }
}
