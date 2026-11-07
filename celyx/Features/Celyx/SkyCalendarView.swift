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

    private var upcoming: [SkyEvent] {
        let today = calendar.startOfDay(for:Date())
        return events.filter { $0.end >= today && (filters.isEmpty || filters.contains($0.kind)) }.sorted { $0.start < $1.start }
    }

    var body: some View {
        VStack(spacing:16) {
            Picker("View",selection:$displayMode) {
                ForEach(DisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal,20).padding(.top,12)

            ScrollView(.horizontal) {
                filterChips.padding(.horizontal,20)
            }
            .scrollIndicators(.hidden)
            .fixedSize(horizontal:false,vertical:true)

            ScrollView {
                switch displayMode {
                case .list:
                    eventList
                case .calendar:
                    VStack(alignment:.leading,spacing:16) {
                        monthHeader
                        monthGrid
                        Text("Tap a marked date to view its events.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal,20).padding(.bottom,24)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(CelyxScreenWash())
        .navigationTitle("Sky Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible,for:.navigationBar)
        .preferredColorScheme(.dark)
        .confirmationDialog(selectedDay?.formatted(date:.complete,time:.omitted) ?? "Choose an event",
                            isPresented:$showsDayEventChoices,titleVisibility:.visible) {
            ForEach(dayEventChoices) { event in
                Button(event.title) { onSelect(event) }
            }
            Button("Cancel",role:.cancel) {}
        }
    }

    private var eventList: some View {
        LazyVStack(alignment:.leading,spacing:24) {
            if upcoming.isEmpty {
                ContentUnavailableView("No Upcoming Events",systemImage:"calendar",
                                       description:Text("Try changing the event filters or switch to Calendar to explore other dates."))
            }
            ForEach(upcoming) { event in
                VStack(alignment:.leading,spacing:12) {
                    Text(event.headerDate).font(.system(size:14,weight:.semibold)).tracking(-0.43).foregroundStyle(.white).frame(height:22)
                    Button { onSelect(event) } label: {
                        SkyEventCard(event:event,isReminderOn:store.reminders.contains(event.id)) { store.toggleReminder(event) }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal,20).padding(.bottom,54)
    }

    private var monthHeader: some View {
        HStack {
            Text(month.formatted(.dateTime.month(.wide).year().locale(Locale(identifier:"en_US"))))
                .font(.system(size:17,weight:.semibold)).tracking(-0.43).foregroundStyle(.white)
            Spacer()
            HStack(spacing:12) {
                monthButton("chevron.left",by:-1).accessibilityLabel("Previous month")
                monthButton("chevron.right",by:1).accessibilityLabel("Next month")
            }
        }
        .frame(minHeight:44)
    }
    private func monthButton(_ symbol: String,by value: Int) -> some View {
        CelyxGlassButton(width:44,height:44,action:{
            if let next = calendar.date(byAdding:.month,value:value,to:month) { withAnimation(.snappy) { month = next } }
        }) {
            Image(systemName:symbol).font(.system(size:12,weight:.bold)).foregroundStyle(.white)
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
                        if let kind = dayEvents.first?.kind {
                            Image(kind.icon).resizable().frame(width:15,height:15)
                        }
                    }
                    .frame(width:32,height:32)
                }
                .frame(maxWidth:.infinity,minHeight:66)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(dayEvents.isEmpty)
            .opacity(dayEvents.isEmpty ? 0.45 : 1)
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

    private var filterChips: some View {
        HStack(spacing:12) {
            ForEach(SkyEvent.Kind.allCases) { kind in
                let isOn = filters.contains(kind)
                Button {
                    if isOn { filters.remove(kind) } else { filters.insert(kind) }
                } label: {
                    HStack(spacing:6) {
                        Image(kind.icon).resizable().frame(width:15,height:15)
                        Text(kind.chipTitle).font(.system(size:12)).tracking(-0.45).foregroundStyle(.white)
                    }
                    .padding(.horizontal,12).frame(height:37)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(isOn ? .regular.tint(.white.opacity(0.25)).interactive() : .regular.interactive(),in:Capsule())
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

/// 362×109 event card used on the Sky Calendar.
struct SkyEventCard: View {
    let event: SkyEvent
    let isReminderOn: Bool
    let toggleReminder: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius:20,style:.continuous)
        ZStack(alignment:.leading) {
            CelyxBluePanel(cornerRadius:20)
            Color.clear
                .overlay(alignment:.topLeading) {
                    Image(event.artwork.asset).resizable().scaledToFill()
                        .frame(width:event.artwork.size,height:event.artwork.size)
                        .scaleEffect(x:event.artwork.flipped ? -1 : 1,y:1)
                        .clipShape(RoundedRectangle(cornerRadius:24,style:.continuous))
                        .offset(x:event.artwork.x,y:event.artwork.y)
                }
                .clipShape(shape)
                // Figma blends the artwork with Screen over the blue card.
                .blendMode(.screen)
                .accessibilityHidden(true)
            HStack(spacing:0) {
                VStack(alignment:.leading,spacing:4) {
                    SkyEventKindLabel(kind:event.kind,size:13)
                    Text(event.title).font(.system(size:13,weight:.semibold)).tracking(-0.08).lineSpacing(0).foregroundStyle(.white)
                        .fixedSize(horizontal:false,vertical:true)
                    Text(event.viewingTime).font(.system(size:12)).tracking(-0.08).foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth:.infinity,alignment:.leading)
                .padding(.leading,125).padding(.trailing,8)
                ReminderBell(isOn:isReminderOn,action:toggleReminder).padding(.trailing,15)
            }
        }
        .frame(height:109)
        .contentShape(shape)
        .accessibilityElement(children:.combine)
        .accessibilityLabel("\(event.title), \(event.headerDate), \(event.viewingTime)")
    }
}

struct SkyEventKindLabel: View {
    let kind: SkyEvent.Kind
    var size: CGFloat = 13
    var body: some View {
        HStack(spacing:6) {
            Image(kind.icon).resizable().frame(width:15,height:15)
            Text(kind.rawValue).font(.system(size:size)).tracking(-0.08).foregroundStyle(.white)
        }
        .frame(height:18)
        .opacity(0.5)
    }
}

private struct ReminderBell: View {
    let isOn: Bool
    let action: () -> Void
    var body: some View {
        Group {
            if isOn {
                Button(action:action) {
                    Image(systemName:"bell.fill").font(.system(size:16,weight:.medium)).foregroundStyle(CelyxColor.bellInk)
                        .frame(width:40,height:40).background(Circle().fill(.white)).contentShape(Circle())
                }
                .buttonStyle(.plain)
            } else {
                CelyxGlassButton(width:40,height:40,action:action) {
                    Image(systemName:"bell").font(.system(size:16,weight:.medium)).foregroundStyle(.white)
                }
            }
        }
        .accessibilityLabel(isOn ? "Turn off reminder" : "Remind me")
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
