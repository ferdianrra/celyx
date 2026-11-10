import SwiftUI

/// Figma "Calender and Events Screen" (795:1980).
struct SkyCalendarView: View {
    let store: SkyEventStore
    let onSelect: (SkyEvent) -> Void
    @State private var viewModel: SkyCalendarViewModel
    private typealias DisplayMode = SkyCalendarViewModel.DisplayMode
    private var calendar: Calendar { viewModel.calendar }
    private var month: Date { viewModel.month }
    private var filters: Set<SkyEvent.Kind> { viewModel.filters }

    init(
        store: SkyEventStore, events: [SkyEvent] = SkyEvent.catalogue,
        onSelect: @escaping (SkyEvent) -> Void
    ) {
        self.store = store
        self.onSelect = onSelect
        _viewModel = State(initialValue: SkyCalendarViewModel(events: events))
    }

    private var monthEvents: [SkyEvent] { viewModel.monthEvents }

    // Figma "Calender and Events Screen" (998:2106 list, 998:2526 calendar): a fixed top section under the
    // native toolbar, overlapped by a rounded bottom section whose items scroll under soft scroll edges.
    var body: some View {
        VStack(spacing:0) {
            CelyxSegmentedControl(selection:$viewModel.displayMode,segments:[
                .init(value:.list,title:"List",systemImage:"list.bullet"),
                .init(value:.calendar,title:"Calendar",systemImage:"calendar")
            ])
            .padding(16)
            .padding(.bottom,24)
            .background(alignment:.top) { topSurface }
            bottomSection
        }
        .background(CelyxColor.screen)
        .navigationTitle("Sky Events")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible,for:.navigationBar)
        .toolbarBackgroundVisibility(.hidden,for:.navigationBar)
        .preferredColorScheme(.dark)
        .confirmationDialog(viewModel.selectedDay?.formatted(date:.complete,time:.omitted) ?? "Choose an event",
                            isPresented:$viewModel.showsDayEventChoices,titleVisibility:.visible) {
            ForEach(viewModel.dayEventChoices) { event in
                Button(event.title) { onSelect(event) }
            }
            Button("Cancel",role:.cancel) {}
        }
    }

    /// TOP SECTION (998:2109): dark fill lit from the top by the blue/violet inner-shadow stack.
    /// Runs under the status bar and the toolbar, and 32pt under the bottom section.
    private var topSurface: some View {
        // Figma export "TopSectionBG2" (402×242, no margins).
        Image("celyx-top-section-bg").resizable()
            .padding(.bottom,-32)
            .ignoresSafeArea(edges:.top)
    }

    /// BOTTOM SECTION (998:2116): only the items scroll; filters and the month stay put as a native
    /// safe-area bar, so the system draws its soft scroll-edge blur where items pass under them.
    private var bottomSection: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius:38,topTrailingRadius:38,style:.continuous)
        return ScrollView {
            Group {
                switch viewModel.displayMode {
                case .list: eventList
                case .calendar: calendarBody
                }
            }
            .padding(.horizontal,16).padding(.top,4).padding(.bottom,32)
            .transition(.opacity)
        }
        .scrollIndicators(.hidden)
        .safeAreaBar(edge:.top,spacing:0) { sheetHeader }
        .scrollEdgeEffectStyle(.soft,for:.all)
        .background(CelyxColor.screen)
        .clipShape(shape)
        .background { shape.fill(CelyxColor.screen).shadow(color:.black.opacity(0.18),radius:37.5,y:15) }
        .ignoresSafeArea(edges:.bottom)
    }

    private var sheetHeader: some View {
        VStack(alignment:.leading,spacing:20) {
            filterChips
            monthHeader
        }
        .padding(.horizontal,16).padding(.top,16).padding(.bottom,12)
    }

    private var eventList: some View {
        LazyVStack(spacing:16) {
            if monthEvents.isEmpty {
                ContentUnavailableView("No Sky Events",systemImage:"sparkles",
                                       description:Text("Nothing matches this month. Try another month or category."))
                    .padding(.top,40)
            }
            ForEach(monthEvents) { event in
                Button { onSelect(event) } label: {
                    SkyEventCard(event:event,isReminderOn:store.reminders.contains(event.id)) { store.toggleReminder(event) }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var calendarBody: some View {
        VStack(spacing:12) {
            monthGrid
            Text("Tap a marked date to view its events.")
                .font(.system(size:12)).foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth:.infinity).padding(.vertical,8)
        }
    }

    private var monthHeader: some View {
        HStack(spacing:12) {
            Text(month.formatted(.dateTime.month(.wide).year().locale(Locale(identifier:"en_US"))))
                .font(.system(size:17,weight:.semibold)).tracking(-0.43).foregroundStyle(.white)
                .contentTransition(.numericText())
            Spacer()
            HStack(spacing:8) {
                monthButton("chevron.left",by:-1).accessibilityLabel("Previous month")
                monthButton("chevron.right",by:1).accessibilityLabel("Next month")
            }
        }
        .frame(height:34)
    }
    private func monthButton(_ symbol: String,by value: Int) -> some View {
        CelyxGlassButton(width:34,height:34,action:{
            withAnimation(.snappy) { viewModel.moveMonth(by:value) }
        }) {
            Image(systemName:symbol).font(.system(size:15,weight:.medium)).foregroundStyle(CelyxColor.primaryLabel)
        }
    }

    // MARK: Month grid

    private var monthGrid: some View {
        let weeks = weeksInMonth
        let symbols = calendar.shortWeekdaySymbols.rotated(by:calendar.firstWeekday-1)
        return VStack(spacing:12) {
            weekRow(0..<7) { index in
                Text(symbols[index]).font(.system(size:12,weight:.semibold)).tracking(-0.45).foregroundStyle(.white.opacity(0.25)).frame(height:25)
            }
            ForEach(weeks.indices,id:\.self) { row in
                weekRow(0..<7) { column in
                    dayCell(weeks[row][column])
                }
            }
        }
    }
    private func weekRow<Cell: View>(_ columns: Range<Int>,@ViewBuilder cell: @escaping (Int) -> Cell) -> some View {
        HStack(spacing:0) {
            ForEach(columns,id:\.self) { column in
                cell(column).frame(maxWidth:.infinity)
            }
        }
    }
    @ViewBuilder private func dayCell(_ day: Date?) -> some View {
        if let day {
            let dayEvents = viewModel.events(on:day)
            let highlighted = calendar.isDate(day,inSameDayAs:viewModel.selectedDay ?? Date())
            Button {
                viewModel.selectedDay = day
                if dayEvents.count == 1, let event = dayEvents.first {
                    onSelect(event)
                } else if !dayEvents.isEmpty {
                    viewModel.dayEventChoices = dayEvents
                    viewModel.showsDayEventChoices = true
                }
            } label: {
                VStack(spacing:2) {
                    Text("\(calendar.component(.day,from:day))").font(.system(size:16)).tracking(-0.45).foregroundStyle(.white)
                        .frame(width:32,height:32)
                        .background { if highlighted { Circle().fill(.white.opacity(0.12)).glassEffect(.regular,in:Circle()) } }
                    ZStack {
                        if let kind = dayEvents.first?.kind { kind.marker }
                    }
                    .frame(width:32,height:32)
                }
                .frame(maxWidth:.infinity,minHeight:66)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(dayEvents.isEmpty)
            .accessibilityLabel(day.formatted(date:.complete,time:.omitted)+(dayEvents.isEmpty ? ", No events" : ", "+dayEvents.map(\.title).joined(separator:", ")))
        } else {
            Color.clear.frame(width:32,height:66)
        }
    }
    private var weeksInMonth: [[Date?]] { viewModel.weeksInMonth }

    // MARK: Filters

    /// Categories (Figma section 1001:3509): white when picked, quiet grey glass otherwise.
    private var filterChips: some View {
        HStack(spacing:8) {
            ForEach([SkyEvent.Kind.object,.moon,.event]) { kind in
                let isOn = filters.contains(kind)
                Button {
                    withAnimation(.snappy(duration:0.25)) {
                        if isOn { viewModel.filters.remove(kind) } else { viewModel.filters.insert(kind) }
                    }
                } label: {
                    HStack(spacing:4) {
                        kind.glyph.resizable().scaledToFit().frame(width:16,height:16)
                        Text(kind.chipTitle).font(.system(size:12))
                    }
                    .foregroundStyle(isOn ? .black : .white)
                    .padding(.leading,8).padding(.trailing,12).frame(height:28)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(isOn ? .regular.tint(.white).interactive() : .regular.tint(Color(hex:0x767680,opacity:0.18)).interactive(),in:Capsule())
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection,trigger:filters)
    }
}

extension SkyEvent.Kind {
    /// Category icon from Figma: an SF Symbol for the Moon, template vectors for objects and events.
    var glyph: Image {
        switch self {
        case .moon: Image(systemName:"moonphase.waxing.gibbous.inverse")
        case .object: Image("celyx-chip-object")
        case .event: Image("celyx-chip-events")
        }
    }
    /// Marker under a date in the month grid.
    @ViewBuilder var marker: some View {
        if self == .moon {
            Circle().fill(.white).frame(width:13,height:13)
        } else {
            glyph.resizable().scaledToFit().frame(width:15,height:15).foregroundStyle(.white)
        }
    }
}

private extension Array {
    func rotated(by count: Int) -> [Element] {
        guard !isEmpty else { return self }
        let shift = ((count % self.count)+self.count)%self.count
        return Array(self[shift...]+self[..<shift])
    }
}

#Preview {
    NavigationStack { SkyCalendarView(store:SkyEventStore()) { _ in } }
}
