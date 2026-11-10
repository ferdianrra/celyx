//
//  ContentView.swift
//  celyx
//
import SwiftUI

struct ContentView: View {
    @State private var model = HomeViewModel()

    var body: some View {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-share-flow") {
                StarShareFlowPreview()
            } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-album") {
                StarAlbumView(
                    item: AppPreviewData.item, photo: AppPreviewData.albumPhoto, onSaveNote: { _ in })
            } else {
                home
            }
        #else
            home
        #endif
    }
    private var home: some View {
        HomeView(model: model)
            .environment(\.locale, Locale(identifier: "en"))
    }
}

#Preview { ContentView() }
