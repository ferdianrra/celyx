#if DEBUG
import SwiftUI

struct SkyEventFlowPreview: View {
    static let gardenModel = HomeViewModel(location: AppPreviewData.location,
        defaults: UserDefaults(suiteName: "asterra.event.garden-test.\(UUID())")!)
    private static let guideModel = HomeViewModel(location: AppPreviewData.location,
        defaults: UserDefaults(suiteName: "asterra.event.guide-test.\(UUID())")!)
    private static let completedFixture: (HomeViewModel, SkyEvent) = {
        let model = HomeViewModel(location: AppPreviewData.location,
            defaults: UserDefaults(suiteName: "asterra.event.completed-test.\(UUID())")!)
        let demo = SkyEvent.demo()
        _ = try? model.saveEventObservation(demo, image: AppPreviewData.albumPhoto, date: .now,
            location: AppPreviewData.location)
        return (model, demo)
    }()
    let model: HomeViewModel
    @State private var store: SkyEventStore
    @State private var path: [SkyEvent]
    @State private var camera: CameraCollectionMode?
    @State private var events = Self.fixture()

    init(showsCompletedDemo: Bool = false) {
        let store = SkyEventStore(defaults: UserDefaults(suiteName: "asterra.event.preview")!)
        _store = State(initialValue: store)
        if showsCompletedDemo {
            let (model, demo) = Self.completedFixture
            self.model = model
            _path = State(initialValue: [demo])
        } else {
            model = Self.guideModel
            _path = State(initialValue: [])
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            SkyCalendarView(store: store, events: events) { path.append($0) }
                .navigationDestination(for: SkyEvent.self) { event in
                    SkyEventDetailView(event: event, store: store, hasObservation: model.hasEventCapture(event)) {
                        camera = .event(event)
                    }
                }
        }
        .fullScreenCover(item: $camera) { mode in
            CollectCameraView(mode: mode, model: model) { camera = nil }
        }
    }

    private static func fixture() -> [SkyEvent] {
        let now = Date()
        func event(_ id: String, _ title: String, start: TimeInterval, end: TimeInterval) -> SkyEvent {
            SkyEvent(id: id, kind: .moon, title: title, start: now.addingTimeInterval(start),
                end: now.addingTimeInterval(end), headerDate: "Today", detailDate: "Today",
                viewingTime: "Local viewing window", direction: "East", about: "Watch the Moon rise.",
                tips: "Find a clear view of the horizon.",
                artwork: .init(asset: "event-moon", size: 140, x: -40, y: 0), target: .body("Moon"))
        }
        return [
            event("preview-past", "Past Moon", start: -7200, end: -60),
            event("preview-open", "Open Moon", start: -60, end: 3600),
            event("preview-future", "Upcoming Moon", start: 3600, end: 7200),
        ]
    }
}
#endif
