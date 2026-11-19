import Foundation
import Observation

@MainActor @Observable
final class SkyCalendarViewModel {
    enum DisplayMode: String, CaseIterable, Identifiable {
        case list = "List"
        case calendar = "Calendar"
        var id: Self { self }
    }
    /// Fixed events (previews/tests); otherwise events come live from `SkyEventCatalog`.
    private let fixedEvents: [SkyEvent]?
    private let catalog: SkyEventCatalog
    let calendar: Calendar
    private let now: () -> Date
    private(set) var currentTime: Date
    var month: Date
    var displayMode: DisplayMode = .list
    var selectedDay: Date?
    var dayEventChoices: [SkyEvent] { selectedDay.map { events(on: $0) } ?? [] }
    var showsDayEventChoices = false
    var filters: Set<SkyEvent.Kind> = []

    init(
        events: [SkyEvent]? = nil, catalog: SkyEventCatalog? = nil, calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        fixedEvents = events
        self.catalog = catalog ?? .shared
        self.calendar = calendar
        self.now = now
        let date = now()
        currentTime = date
        month = calendar.dateInterval(of: .month, for: date)?.start ?? date
    }
    /// Events overlapping `interval`, computed for the user's current location.
    private func events(in interval: DateInterval) -> [SkyEvent] {
        guard let fixedEvents else { return catalog.events(in: interval) }
        return fixedEvents.filter { $0.start < interval.end && $0.end >= interval.start }
    }
    func refreshTime() {
        currentTime = now()
    }

    private func visibleEvents(in interval: DateInterval) -> [SkyEvent] {
        guard interval.end >= currentTime else { return [] }
        return events(in: interval).filter {
            !$0.hasEnded(at: currentTime) && (filters.isEmpty || filters.contains($0.kind))
        }.sorted { $0.start < $1.start }
    }

    var upcoming: [SkyEvent] {
        let today = calendar.startOfDay(for: currentTime)
        let horizon = calendar.date(byAdding: .year, value: 1, to: today) ?? today
        return visibleEvents(in: DateInterval(start: today, end: horizon))
    }

    var monthEvents: [SkyEvent] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        return visibleEvents(in: interval)
    }

    func events(on day: Date) -> [SkyEvent] {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return [] }
        return visibleEvents(in: interval)
    }

    func moveMonth(by value: Int) {
        if let next = calendar.date(byAdding: .month, value: value, to: month) { month = next }
    }
    var weeksInMonth: [[Date?]] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let leading = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        cells += range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
        cells += Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

}
