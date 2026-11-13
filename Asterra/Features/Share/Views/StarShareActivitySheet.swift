import SwiftUI
import UIKit

/// Destination selection and the final send/post action remain in the user's control.
struct StarShareActivitySheet: UIViewControllerRepresentable {
    let fileURL: URL
    var onError: ((Error) -> Void)? = nil
    final class Coordinator {
        let fileURL: URL
        init(fileURL: URL) { self.fileURL = fileURL }
        func cleanup() {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(fileURL: fileURL) }
    static func dismantleUIViewController(_ controller: UIActivityViewController, coordinator: Coordinator) {
        coordinator.cleanup()
    }
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        // The receiving extension has finished consuming the file when completion fires.
        let coordinator = context.coordinator
        controller.completionWithItemsHandler = { _, _, _, error in
            DispatchQueue.main.async {
                coordinator.cleanup()
                if let error { onError?(error) }
            }
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
