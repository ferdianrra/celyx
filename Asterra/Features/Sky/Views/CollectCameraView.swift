import SwiftUI

/// Presents the live camera in ordinary collection or in guided event mode.
struct CollectCameraView: View {
    let mode: CameraCollectionMode
    let model: HomeViewModel
    var handover: WormholeHandover? = nil
    var onCollect: ((StarCollectCameraView.CollectResult) -> Void)? = nil
    let onClose: () -> Void

    var body: some View {
        switch mode {
        case .star:
            StarCollectCameraView(model: model, onClose: onClose)
        case .event(let event):
            StarCollectCameraView(model: model, handover: handover, onCollect: onCollect, event: event, onClose: onClose)
        }
    }
}
