import SwiftUI

struct AstronomyEventDetailView: View {
    let event: AstronomyEvent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    AstronomyEventCard(event:event)
                    Text(event.title).font(.title2.bold())
                    VStack(alignment:.leading,spacing:7) {
                        Text(event.time.formatted(.dateTime.weekday(.wide).month(.wide).day().year().locale(Locale(identifier:"en")))).font(.headline)
                        Text(event.time.formatted(.dateTime.hour().minute())+" · "+(TimeZone.current.abbreviation(for:event.time) ?? TimeZone.current.identifier))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let description = event.description ?? event.summary { Text(description).font(.body).foregroundStyle(.white.opacity(0.8)) }
                    EventViewingLocationsSection(event:event)
                    Text("This is the event’s peak time. Whether you can see it depends on your location and the sky that day.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let sourceURL = event.sourceURL {
                        Link(destination:sourceURL) { Label("More about this event",systemImage:"arrow.up.right") }.buttonStyle(.bordered)
                    }
                    Divider().overlay(.white.opacity(0.1))
                    DisclosureGroup("Sources & credits") {
                        VStack(alignment:.leading,spacing:10) {
                            Link("SpaceCatalog.org",destination:URL(string:"https://spacecatalog.org/api")!)
                            if let name = event.source?.name { Text(name) }
                            if let url = event.producerURL { Link("Original source",destination:url) }
                            if let credit = event.source?.attribution { Text(credit).textSelection(.enabled) }
                            if let license = event.source?.license { Text(license).foregroundStyle(.secondary) }
                        }.font(.caption).padding(.top,10)
                    }.font(.footnote)
                }.padding(20)
            }
            .background(Color(white:0.07))
            .navigationTitle("A closer look").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(.white).foregroundStyle(.white).preferredColorScheme(.dark)
    }
}
