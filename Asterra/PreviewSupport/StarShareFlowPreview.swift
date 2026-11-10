#if DEBUG
import SwiftUI

/// Isolated detail-sheet entry point for previewing and testing the new share navigation.
struct StarShareFlowPreview: View {
    @State private var showsDetails = false
    @State private var collection = StarSharePreviewData.model()

    var body: some View {
        ZStack {
            CelyxColor.night.ignoresSafeArea()
            Button(StarSharePreviewData.item.star.title) { showsDetails = true }
                .accessibilityIdentifier("share-flow-star")
        }
        .sheet(isPresented: $showsDetails) {
            CollectedObjectSheet(item: StarSharePreviewData.item, direction: SIMD3(0, 0.8, 0.6), collection: collection, onDelete: {})
        }
        .preferredColorScheme(.dark)
    }
}

#Preview { StarShareFlowPreview() }
#endif
