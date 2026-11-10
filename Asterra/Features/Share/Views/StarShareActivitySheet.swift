import SwiftUI
import UIKit

/// Destination selection and the final send/post action remain in the user's control.
struct StarShareActivitySheet: UIViewControllerRepresentable {
    let image: UIImage
    var fileURL: URL? = nil
    final class Coordinator {
        let fileURL: URL?
        init(fileURL: URL?) { self.fileURL = fileURL }
        func cleanup() {
            if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(fileURL: fileURL) }
    static func dismantleUIViewController(_ controller: UIActivityViewController, coordinator: Coordinator) {
        coordinator.cleanup()
    }
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let items: [Any] = fileURL.map { [$0] } ?? [image]
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // The receiving extension has finished consuming the file when completion fires.
        let coordinator = context.coordinator
        controller.completionWithItemsHandler = { _, _, _, _ in
            DispatchQueue.main.async { coordinator.cleanup() }
        }
        controller.excludedActivityTypes = [.assignToContact, .addToReadingList, .print]
        if let popover = controller.popoverPresentationController {
            popover.sourceView = controller.view
            popover.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
