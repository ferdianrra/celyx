import Foundation
import Observation

/// State for the existing event-camera prototype, independent of its SwiftUI presentation.
@MainActor @Observable
final class EventCollectionViewModel {
    enum Phase { case scanning, found, collected }
    let mode: CameraCollectionMode
    let events: SkyEventStore
    var phase: Phase = .scanning
    @ObservationIgnored private var detection: Task<Void, Never>?

    init(mode: CameraCollectionMode, events: SkyEventStore) {
        self.mode = mode
        self.events = events
    }
    func startDetection() {
        stop()
        detection = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            self?.phase = .found
            self?.detection = nil
        }
    }
    func collect() {
        if case .event(let event) = mode { events.collect(event) }
        phase = .collected
    }
    func stop() {
        detection?.cancel()
        detection = nil
    }
}
