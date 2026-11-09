import SwiftUI

/// Figma "Calender and Events Screen" (795:1980).
struct SkyCalendarView: View {
    let store: SkyEventStore
    let onSelect: (SkyEvent) -> Void
    @State private var viewModel: SkyCalendarViewModel
    private typealias DisplayMode = SkyCalendarViewModel.DisplayMode

    init(
        store: SkyEventStore, events: [SkyEvent] = SkyEvent.catalogue,
        onSelect: @escaping (SkyEvent) -> Void
    ) {
        self.store = store
        self.onSelect = onSelect
        _viewModel = State(initialValue: SkyCalendarViewModel(events: events))
    }

    var body: some View {
        VStack(spacing: 16) {
            Picker("View", selection: $viewModel.displayMode) {
                ForEach(DisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20).padding(.top, 12)

            ScrollView(.horizontal) {
                filterChips.padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                switch viewModel.displayMode {
                case .list:
                    eventList
                case .calendar:
                    VStack(alignment: .leading, spacing: 16) {
                        monthHeader
                        monthGrid
                        Text("Tap a marked date to view its events.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20).padding(.bottom, 24)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(CelyxScreenWash())
        .navigationTitle("Sky Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .preferredColorScheme(.dark)
        .confirmationDialog(
            viewModel.selectedDay?.formatted(date: .complete, time: .omitted) ?? "Choose an event",
            isPresented: $viewModel.showsDayEventChoices, titleVisibility: .visible
        ) {
            ForEach(viewModel.dayEventChoices) { event in
                Button(event.title) { onSelect(event) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var eventList: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            if viewModel.upcoming.isEmpty {
                ContentUnavailableView(
                    "No Upcoming Events", systemImage: "calendar",
                    description: Text(
                        "Try changing the event filters or switch to Calendar to explore other dates."
                    ))
            }
            ForEach(viewModel.upcoming) { event in
                VStack(alignment: .leading, spacing: 12) {
                    Text(event.headerDate).font(.system(size: 14, weight: .semibold)).tracking(-0.43)
                        .foregroundStyle(.white).frame(height: 22)
                    Button {
                        onSelect(event)
                    } label: {
                        SkyEventCard(event: event, isReminderOn: store.reminders.contains(event.id)) {
                            store.toggleReminder(event)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 54)
    }

    private var monthHeader: some View {
        HStack {
            Text(
                viewModel.month.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "en_US")))
            )
            .font(.system(size: 17, weight: .semibold)).tracking(-0.43).foregroundStyle(.white)
            Spacer()
            HStack(spacing: 12) {
                monthButton("chevron.left", by: -1).accessibilityLabel("Previous month")
                monthButton("chevron.right", by: 1).accessibilityLabel("Next month")
            }
        }
        .frame(minHeight: 44)
    }
    private func monthButton(_ symbol: String, by value: Int) -> some View {
        CelyxGlassButton(
            width: 44, height: 44,
            action: {
                withAnimation(.snappy) { viewModel.moveMonth(by: value) }
            }
        ) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
        }
    }

    // MARK: Month grid

    private var monthGrid: some View {
        let weeks = viewModel.weeksInMonth
        let symbols = viewModel.calendar.shortWeekdaySymbols.rotated(
            by: viewModel.calendar.firstWeekday - 1)
        return VStack(spacing: 12) {
            weekRow(0..<7) { index in
                Text(symbols[index]).font(.system(size: 12, weight: .semibold)).tracking(-0.45)
                    .foregroundStyle(.white.opacity(0.25)).frame(height: 25)
            }
            ForEach(weeks.indices, id: \.self) { row in
                weekRow(0..<7) { column in
                    dayCell(weeks[row][column])
                }
            }
        }
    }
    private func weekRow<Cell: View>(
        _ columns: Range<Int>, @ViewBuilder cell: @escaping (Int) -> Cell
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(columns, id: \.self) { column in
                cell(column).frame(maxWidth: .infinity)
            }
        }
    }
    @ViewBuilder private func dayCell(_ day: Date?) -> some View {
        if let day {
            let dayEvents = viewModel.events(on: day)
            let highlighted = viewModel.calendar.isDate(day, inSameDayAs: viewModel.selectedDay ?? Date())
            Button {
                viewModel.selectedDay = day
                if dayEvents.count == 1, let event = dayEvents.first {
                    onSelect(event)
                } else if !dayEvents.isEmpty {
                    viewModel.dayEventChoices = dayEvents
                    viewModel.showsDayEventChoices = true
                }
            } label: {
                VStack(spacing: 2) {
                    Text("\(viewModel.calendar.component(.day,from:day))").font(.system(size: 16)).tracking(
                        -0.45
                    ).foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background {
                            if highlighted {
                                Circle().fill(.white.opacity(0.12)).glassEffect(.regular, in: Circle())
                            }
                        }
                    ZStack {
                        if let kind = dayEvents.first?.kind {
                            Image(kind.icon).resizable().frame(width: 15, height: 15)
                        }
                    }
                    .frame(width: 32, height: 32)
                }
                .frame(maxWidth: .infinity, minHeight: 66)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(dayEvents.isEmpty)
            .opacity(dayEvents.isEmpty ? 0.45 : 1)
            .accessibilityLabel(
                day.formatted(date: .complete, time: .omitted)
                    + (dayEvents.isEmpty
                        ? ", No events" : ", " + dayEvents.map(\.title).joined(separator: ", ")))
        } else {
            Color.clear.frame(width: 32, height: 66)
        }
    }

    // MARK: Filters

    private var filterChips: some View {
        HStack(spacing: 12) {
            ForEach(SkyEvent.Kind.allCases) { kind in
                let isOn = viewModel.filters.contains(kind)
                Button {
                    if isOn { viewModel.filters.remove(kind) } else { viewModel.filters.insert(kind) }
                } label: {
                    HStack(spacing: 6) {
                        Image(kind.icon).resizable().frame(width: 15, height: 15)
                        Text(kind.chipTitle).font(.system(size: 12)).tracking(-0.45).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12).frame(height: 37)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(
                    isOn ? .regular.tint(.white.opacity(0.25)).interactive() : .regular.interactive(),
                    in: Capsule()
                )
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

extension Array {
    fileprivate func rotated(by count: Int) -> [Element] {
        guard !isEmpty else { return self }
        let shift = ((count % self.count) + self.count) % self.count
        return Array(self[shift...] + self[..<shift])
    }
}

#Preview {
    NavigationStack { SkyCalendarView(store: SkyEventStore()) { _ in } }
}
