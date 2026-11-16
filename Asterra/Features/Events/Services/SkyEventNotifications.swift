import Foundation
import Observation
import UserNotifications

/// Local notifications for Sky Calendar events, worked out on the device for the user's location:
/// one 30 minutes before each viewing window opens, and one when it opens ("happening now").
/// iOS keeps at most 64 pending requests, so only the soonest are queued and the queue is rebuilt
/// whenever the app becomes active, the location changes, or an event is collected or muted.
@MainActor @Observable
final class SkyEventNotifications: NSObject {
    static let shared = SkyEventNotifications()

    enum Moment: String { case soon, live }
    /// An event opened from a notification, waiting for the home screen to show it.
    struct Opened: Equatable {
        let eventID: String
        let moment: Moment
    }

    /// Set when the user taps a notification; the home screen consumes and clears it.
    var opened: Opened?

    private static let prefix = "skyevent."
    private static let lead: TimeInterval = 30 * 60
    private static let horizon: TimeInterval = 30 * 86400
    /// Stay under iOS's 64 pending requests.
    private static let limit = 60

    @ObservationIgnored private var rescheduling: Task<Void, Never>?

    private var center: UNUserNotificationCenter { .current() }

    /// Call once at launch so taps on notifications reach the app, even from a cold start.
    func activate() {
        center.delegate = self
    }

    /// Rebuilds the queue for the events in the next 30 days. Asks for permission the first time.
    func reschedule(store: SkyEventStore) {
        rescheduling?.cancel()
        let skipped = store.collected.union(store.muted)
        rescheduling = Task { [weak self] in
            guard let self else { return }
            let settings = await center.notificationSettings()
            var status = settings.authorizationStatus
            if status == .notDetermined {
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
                status = granted ? .authorized : .denied
            }
            guard !Task.isCancelled else { return }
            await removePending()
            guard status == .authorized || status == .provisional || status == .ephemeral,
                !Task.isCancelled
            else { return }

            let now = Date()
            let events = SkyEventCatalog.shared.events(in: DateInterval(start: now, duration: Self.horizon))
                .filter { !skipped.contains($0.id) }
            let requests = events.flatMap { Self.requests(for: $0, after: now) }
                .sorted { $0.date < $1.date }
                .prefix(Self.limit)
            for request in requests {
                guard !Task.isCancelled else { return }
                try? await center.add(request.request)
            }
        }
    }

    private func removePending() async {
        let ids = await center.pendingNotificationRequests().map(\.identifier)
            .filter { $0.hasPrefix(Self.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: Building requests

    private struct Scheduled {
        let date: Date
        let request: UNNotificationRequest
    }

    private static func requests(for event: SkyEvent, after now: Date) -> [Scheduled] {
        let windows = event.nights.isEmpty ? [DateInterval(start: event.start, end: event.end)] : event.nights
        return windows.flatMap { window -> [Scheduled] in
            var result: [Scheduled] = []
            let soon = window.start.addingTimeInterval(-lead)
            if soon > now { result.append(make(event, window, .soon, at: soon)) }
            if window.start > now { result.append(make(event, window, .live, at: window.start)) }
            return result
        }
    }

    private static func make(_ event: SkyEvent, _ window: DateInterval, _ moment: Moment, at date: Date)
        -> Scheduled
    {
        let copy = Copy(event: event, start: time(window.start), end: time(window.end))
        let content = UNMutableNotificationContent()
        // iOS always shows the app icon on local notifications; the text carries the context.
        content.title = moment == .soon ? copy.soonTitle : copy.liveTitle
        // Just where to look ("Eastern Sky"), without the altitude in degrees.
        content.subtitle = event.direction.components(separatedBy: " · ").first ?? event.direction
        content.body = moment == .soon ? copy.soonBody : copy.liveBody
        content.sound = .default
        content.interruptionLevel = .active
        content.relevanceScore = moment == .live ? 1 : 0.6
        content.threadIdentifier = event.id
        content.userInfo = ["eventID": event.id, "moment": moment.rawValue]
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let id = "\(prefix)\(event.id).\(Int(window.start.timeIntervalSince1970)).\(moment.rawValue)"
        return Scheduled(date: date, request: UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Short, punchy wording per kind of event: what it is, and the deadline.
    private struct Copy {
        let soonTitle: String, soonBody: String, liveTitle: String, liveBody: String

        init(event: SkyEvent, start: String, end: String) {
            let name = event.title
            switch event.target {
            case .radiant:
                soonTitle = "\(name) in 30 min"
                soonBody = "Find a dark spot and get ready."
                liveTitle = "Shooting stars now"
                liveBody = "Look up before \(end). Catch one!"
            case .pair:
                soonTitle = "\(name) in 30 min"
                soonBody = "A rare pair. Don't miss it."
                liveTitle = "\(name) now"
                liveBody = "Side by side until \(end). Collect it!"
            case .body where name.lowercased().contains("eclipse"):
                soonTitle = "\(name) in 30 min"
                soonBody = "Could be years until the next one."
                liveTitle = "Eclipse happening now"
                liveBody = "Look up before \(end). Collect it!"
            case .body("Moon"):
                soonTitle = "\(name) in 30 min"
                soonBody = "Biggest right after it rises."
                liveTitle = "\(name) is up"
                liveBody = "Glowing until \(end). Collect it!"
            case .body:
                soonTitle = "\(name) in 30 min"
                soonBody = "Best view of the year. No telescope needed."
                liveTitle = "\(name) now"
                liveBody = "Visible until \(end). Collect it!"
            }
        }
    }

    private static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "en_US")))
    }
}

extension SkyEventNotifications: UNUserNotificationCenterDelegate {
    /// Show the banner even while the app is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let id = info["eventID"] as? String else { return }
        let moment = (info["moment"] as? String).flatMap(Moment.init(rawValue:)) ?? .soon
        await MainActor.run { self.opened = Opened(eventID: id, moment: moment) }
    }
}
