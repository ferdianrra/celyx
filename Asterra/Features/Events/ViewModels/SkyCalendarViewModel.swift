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
    var month: Date
    var displayMode: DisplayMode = .list
    var selectedDay: Date?
    var dayEventChoices: [SkyEvent] = []
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
        month = calendar.dateInterval(of: .month, for: now())?.start ?? now()
    }
    /// Events overlapping `interval`, computed for the user's current location.
    private func events(in interval: DateInterval) -> [SkyEvent] {
        guard let fixedEvents else { return catalog.events(in: interval) }
        return fixedEvents.filter { $0.start < interval.end && $0.end >= interval.start }
    }
    var upcoming: [SkyEvent] {
        let today = calendar.startOfDay(for: now())
        let horizon = calendar.date(byAdding: .year, value: 1, to: today) ?? today
        return events(in: DateInterval(start: today, end: horizon)).filter { $0.end >= today && (filters.isEmpty || filters.contains($0.kind)) }
            .sorted { $0.start < $1.start }
    }
    /// Events of the shown month that pass the category filters.
    var monthEvents: [SkyEvent] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        return events(in: interval).filter { filters.isEmpty || filters.contains($0.kind) }
        .sorted { $0.start < $1.start }
    }
    func events(on day: Date) -> [SkyEvent] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return events(in: DateInterval(start: start, end: end)).filter {
            (filters.isEmpty || filters.contains($0.kind)) && calendar.startOfDay(for: $0.start) <= day
                && calendar.startOfDay(for: $0.end) >= day
        }.sorted { $0.start < $1.start }
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
