import SwiftUI

/// Figma "Calender and Events Screen" (795:1980).
struct SkyCalendarView: View {
    let store: SkyEventStore
    var events: [SkyEvent] = SkyEvent.catalogue
    let onSelect: (SkyEvent) -> Void
    @State private var month = Calendar.current.dateInterval(of:.month,for:Date())?.start ?? Date()
    private enum DisplayMode: String, CaseIterable, Identifiable {
        case list = "List", calendar = "Calendar"
        var id: Self { self }
    }
    @State private var displayMode: DisplayMode = .list
    @State private var selectedDay: Date?
    @State private var dayEventChoices: [SkyEvent] = []
    @State private var showsDayEventChoices = false
    @State private var filters: Set<SkyEvent.Kind> = []
    private let calendar = Calendar.current

    /// Events of the shown month that pass the category filters.
    private var monthEvents: [SkyEvent] {
        guard let interval = calendar.dateInterval(of:.month,for:month) else { return [] }
        return events.filter {
            $0.start < interval.end && $0.end >= interval.start && (filters.isEmpty || filters.contains($0.kind))
        }
        .sorted { $0.start < $1.start }
    }

    // Figma "Calender and Events Screen" (998:2106 list, 998:2526 calendar): a fixed top section under the
    // native toolbar, overlapped by a rounded bottom section whose items scroll under soft scroll edges.
    var body: some View {
        VStack(spacing:0) {
            CelyxSegmentedControl(selection:$displayMode,segments:[
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
        .confirmationDialog(selectedDay?.formatted(date:.complete,time:.omitted) ?? "Choose an event",
                            isPresented:$showsDayEventChoices,titleVisibility:.visible) {
            ForEach(dayEventChoices) { event in
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
                switch displayMode {
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
            if let next = calendar.date(byAdding:.month,value:value,to:month) { withAnimation(.snappy) { month = next } }
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
            let dayEvents = events.filter {
                (filters.isEmpty || filters.contains($0.kind)) &&
                calendar.startOfDay(for:$0.start) <= day && calendar.startOfDay(for:$0.end) >= day
            }.sorted { $0.start < $1.start }
            let highlighted = calendar.isDate(day,inSameDayAs:selectedDay ?? Date())
            Button {
                selectedDay = day
                if dayEvents.count == 1, let event = dayEvents.first {
                    onSelect(event)
                } else if !dayEvents.isEmpty {
                    dayEventChoices = dayEvents
                    showsDayEventChoices = true
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
    private var weeksInMonth: [[Date?]] {
        guard let range = calendar.range(of:.day,in:.month,for:month) else { return [] }
        let leading = (calendar.component(.weekday,from:month)-calendar.firstWeekday+7)%7
        var cells: [Date?] = Array(repeating:nil,count:leading)
        cells += range.compactMap { calendar.date(byAdding:.day,value:$0-1,to:month) }
        cells += Array(repeating:nil,count:(7-cells.count%7)%7)
        return stride(from:0,to:cells.count,by:7).map { Array(cells[$0..<$0+7]) }
    }

    // MARK: Filters

    /// Categories (Figma section 1001:3509): white when picked, quiet grey glass otherwise.
    private var filterChips: some View {
        HStack(spacing:8) {
            ForEach([SkyEvent.Kind.object,.moon,.event]) { kind in
                let isOn = filters.contains(kind)
                Button {
                    withAnimation(.snappy(duration:0.25)) {
                        if isOn { filters.remove(kind) } else { filters.insert(kind) }
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

/// 370×109 event card (Figma "Liquid Glass - Regular - Medium" in 998:2116): dark Liquid Glass lit by the
/// card inner-shadow stack, artwork added with Plus Lighter on the leading edge, reminder bell on the trailing one.
struct SkyEventCard: View {
    let event: SkyEvent
    let isReminderOn: Bool
    let toggleReminder: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius:20,style:.continuous)
        ZStack(alignment:.leading) {
            // Figma export "CardBG": the card's glass over its inner-shadow gradient.
            Image("celyx-card-bg").resizable()
            Color.clear
                .overlay(alignment:.topLeading) {
                    Image(event.artwork.asset).resizable().scaledToFill()
                        .frame(width:event.artwork.size,height:event.artwork.size)
                        .scaleEffect(x:event.artwork.flipped ? -1 : 1,y:1)
                        .clipShape(RoundedRectangle(cornerRadius:24,style:.continuous))
                        .offset(x:event.artwork.x,y:event.artwork.y)
                }
                .frame(width:133).clipped()
                // The 133pt art frame meets the text column with a soft edge instead of a hard cut.
                .mask(LinearGradient(stops:[.init(color:.black,location:0.72),.init(color:.clear,location:1)],
                                     startPoint:.leading,endPoint:.trailing))
                .blendMode(.plusLighter)
                .accessibilityHidden(true)
            HStack(spacing:10) {
                VStack(alignment:.leading,spacing:8) {
                    SkyEventKindLabel(kind:event.kind,size:12,opacity:0.64)
                    VStack(alignment:.leading,spacing:4) {
                        Text(event.title).font(.system(size:15,weight:.semibold)).foregroundStyle(.white)
                            .lineLimit(2).fixedSize(horizontal:false,vertical:true)
                        HStack(spacing:4) {
                            Text(dayText).opacity(0.8)
                            Text("·").opacity(0.5)
                            Text(timeText).opacity(0.5)
                        }
                        .font(.system(size:11)).foregroundStyle(.white).lineLimit(1)
                    }
                }
                .frame(maxWidth:.infinity,alignment:.leading)
                ReminderBell(isOn:isReminderOn,action:toggleReminder)
            }
            .padding(.leading,101).padding(.trailing,16).padding(.vertical,16)
        }
        .frame(height:109)
        .clipShape(shape)
        .contentShape(shape)
        .accessibilityElement(children:.combine)
        .accessibilityLabel("\(event.title), \(event.headerDate), \(event.viewingTime)")
    }

    /// "15-16 Nov" (or "18 Nov" for a one-night event).
    private var dayText: String {
        let calendar = Calendar.current
        let locale = Locale(identifier:"en_GB")
        let endDay = event.end.addingTimeInterval(-1)
        if calendar.isDate(event.start,inSameDayAs:endDay) {
            return event.start.formatted(.dateTime.day().month(.abbreviated).locale(locale))
        }
        if calendar.isDate(event.start,equalTo:endDay,toGranularity:.month) {
            return "\(calendar.component(.day,from:event.start))-"+endDay.formatted(.dateTime.day().month(.abbreviated).locale(locale))
        }
        return event.start.formatted(.dateTime.day().month(.abbreviated).locale(locale))+" - "+endDay.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }
    /// "00:00 – 05:00"
    private var timeText: String {
        let style = Date.FormatStyle().hour(.twoDigits(amPM:.omitted)).minute(.twoDigits).locale(Locale(identifier:"en_GB"))
        return event.start.formatted(style)+" – "+event.end.formatted(style)
    }
}

struct SkyEventKindLabel: View {
    let kind: SkyEvent.Kind
    var size: CGFloat = 13
    var opacity: Double = 0.5
    var body: some View {
        HStack(spacing:4) {
            kind.glyph.resizable().scaledToFit().frame(width:16,height:16)
            Text(kind.chipTitle).font(.system(size:size))
        }
        .foregroundStyle(.white)
        .frame(height:16)
        .opacity(opacity)
    }
}

/// Reminder toggle: glass when off, prominent white with a black bell once a reminder is set.
private struct ReminderBell: View {
    let isOn: Bool
    let action: () -> Void
    var body: some View {
        Button(action:action) {
            Image(systemName:"bell.fill").font(.system(size:15))
                .foregroundStyle(isOn ? .black : CelyxColor.primaryLabel)
                .symbolEffect(.bounce,value:isOn)
                .frame(width:34,height:36).contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(isOn ? .regular.tint(.white).interactive() : .regular.interactive(),in:Capsule())
        .animation(.snappy(duration:0.25),value:isOn)
        .sensoryFeedback(.success,trigger:isOn) { _,on in on }
        .accessibilityLabel(isOn ? "Turn off reminder" : "Remind me")
        .accessibilityAddTraits(isOn ? .isSelected : [])
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

#Preview("Sky event card") {
    SkyEventCard(event:SkyEvent.catalogue[0],isReminderOn:false,toggleReminder:{}).padding().background(.black)
        .preferredColorScheme(.dark)
}

#Preview("Event kind label") {
    SkyEventKindLabel(kind:SkyEvent.catalogue[0].kind).padding().background(.black)
        .preferredColorScheme(.dark)
}

#Preview("Reminder bell") {
    HStack { ReminderBell(isOn:false,action:{}); ReminderBell(isOn:true,action:{}) }.padding().background(.black)
        .preferredColorScheme(.dark)
}
