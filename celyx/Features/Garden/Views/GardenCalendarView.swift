import SwiftUI

struct GardenCalendarView: View {
    @State private var service = AstronomyEventsService()
    @State private var category: AstronomyEvent.Category = .all
    @State private var selectedEvent: AstronomyEvent?
    @State private var selectedMonth: String?

    private var upcoming: [AstronomyEvent] { service.events.filter { $0.time >= Date() } }
    private var events: [AstronomyEvent] {
        upcoming.filter { (category == .all || $0.category == category) && (selectedMonth == nil || monthKey($0.time) == selectedMonth) }
    }
    private var months: [Date] {
        let calendar = Calendar.current
        return Array(Set(upcoming.compactMap { calendar.dateInterval(of:.month,for:$0.time)?.start })).sorted()
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:14) {
                HStack {
                    Menu {
                        Button("Next 6 months") { selectedMonth = nil }
                        ForEach(months,id:\.self) { date in
                            Button(date.formatted(.dateTime.month(.wide).year().locale(Locale(identifier:"en")))) { selectedMonth = monthKey(date) }
                        }
                    } label: {
                        Label(selectedMonthTitle,systemImage:"calendar").font(.subheadline.weight(.medium))
                    }
                    Spacer()
                    if service.isLoading && !service.events.isEmpty { ProgressView().controlSize(.small) }
                }.padding(.bottom,2)
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack(spacing:8) {
                        ForEach(AstronomyEvent.Category.allCases) { item in
                            Button { category = item } label: {
                                Text(item.rawValue).font(.caption.weight(.medium))
                                    .padding(.horizontal,13).padding(.vertical,8)
                                    .background(category == item ? Color.white : Color.white.opacity(0.07),in:Capsule())
                                    .foregroundStyle(category == item ? .black : .white.opacity(0.7))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if let message = service.message {
                    HStack(alignment:.top,spacing:10) {
                        Image(systemName:service.isUsingSavedEvents ? "clock.arrow.circlepath" : "wifi.exclamationmark")
                        Text(message).font(.caption)
                        Spacer(minLength:0)
                        Button("Retry") { Task { await service.load(force:true) } }.font(.caption.weight(.semibold))
                    }.foregroundStyle(.secondary).padding(12).background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:14))
                }
                if service.isLoading && service.events.isEmpty {
                    ProgressView("Looking up what’s next…").frame(maxWidth:.infinity).padding(.vertical,70)
                } else if events.isEmpty {
                    ContentUnavailableView(service.message == nil ? "Nothing coming up here yet" : "Events aren’t available right now",
                        systemImage:service.message == nil ? "sparkles" : "wifi.exclamationmark",
                        description:Text(service.message == nil ? "Try another category or check back soon." : "Pull down to try again."))
                } else {
                    ForEach(events) { event in
                        Button { selectedEvent = event } label: { AstronomyEventCard(event:event) }
                            .buttonStyle(.plain)
                    }
                }
                VStack(alignment:.leading,spacing:6) {
                    Text("Times shown in \(TimeZone.current.abbreviation() ?? TimeZone.current.identifier). Visibility depends on where you are.")
                    Link("Data from SpaceCatalog.org",destination:URL(string:"https://spacecatalog.org/api")!)
                }.font(.caption2).foregroundStyle(.white.opacity(0.45)).padding(.top,10)
            }.padding(.horizontal,20).padding(.top,14).padding(.bottom,28)
        }
        .background(Color(white:0.09))
        .navigationTitle("Upcoming Events")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden,for:.navigationBar)
        .toolbarColorScheme(.dark,for:.navigationBar)
        .preferredColorScheme(.dark).tint(.white)
        .task { await service.load() }
        .refreshable { await service.load(force:true) }
        .sheet(item:$selectedEvent) { AstronomyEventDetailView(event:$0) }
    }
    private var selectedMonthTitle: String {
        guard let selectedMonth, let date = months.first(where: { monthKey($0) == selectedMonth }) else { return "Next 6 months" }
        return date.formatted(.dateTime.month(.wide).year().locale(Locale(identifier:"en")))
    }
    private func monthKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year,.month],from:date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)"
    }
}
