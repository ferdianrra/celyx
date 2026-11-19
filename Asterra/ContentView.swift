//
//  ContentView.swift
//  celyx
//
import SwiftUI

struct ContentView: View {
    @State private var model = HomeViewModel()

    var body: some View {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-observation-log") {
                CollectionCaptureFlowPreview(showsObservationLog: true)
            } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-collection-observation-log") {
                NavigationStack {
                    CollectionListView(category: .stars, model: StarSharePreviewData.observationLogModel,
                        events: SkyEventStore(), onGuide: { _ in }, onSelectEvent: { _ in })
                }
            } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-note-flow") {
                CollectionCaptureFlowPreview()
            } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-share-flow") {
                StarShareFlowPreview()
            } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-event-guidance") {
                SkyEventFlowPreview(showsCompletedDemo:
                    ProcessInfo.processInfo.arguments.contains("-ui-testing-completed-demo"))
            } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-event-garden") {
                HomeView(model: SkyEventFlowPreview.gardenModel)
            } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-constellation-book") {
                ZodiacBookPreviewFlow(detailCode: UserDefaults.standard.string(forKey: "constellation-detail"))
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
