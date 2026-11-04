import SwiftUI

struct EventViewingLocationsSection: View {
    let event: AstronomyEvent
    @State private var model = EventVisibilityViewModel()
    @State private var showsMap = false
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Label("Where could I see it?",systemImage:"map").font(.headline)
            if let plan = model.plan {
                switch plan {
                case .geometry(let geometry):
                    if geometry.needsOpticalAid, let magnitude = geometry.magnitude {
                        Label(String(format:"Faint target · magnitude %.1f",magnitude),systemImage:"binoculars")
                            .font(.subheadline).foregroundStyle(.orange)
                    }
                    Text("Check where the target is above the horizon and the sky is dark at the event time.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if model.isLoading { ProgressView("Preparing the sky map…").font(.caption) }
                    Button { showsMap = true } label: {
                        Label("View Potential Areas",systemImage:"map.fill").frame(maxWidth:.infinity).padding(.vertical,6)
                    }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                    Text(geometry.criteria).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    if let note = geometry.equipmentNote { Text(note).font(.caption).foregroundStyle(.orange) }
                    Text("This checks sky geometry. Clouds, nearby lights, terrain and buildings can still block the view.")
                        .font(.caption).foregroundStyle(.secondary)
                case .greatestEclipse:
                    Text("The catalog provides the point of greatest eclipse, but not its full viewing path.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button { showsMap = true } label: { Label("View Catalog Location",systemImage:"mappin.and.ellipse") }
                        .buttonStyle(.bordered)
                    Text("Only that published point is marked. It isn’t a suggested observing venue or a radius of visibility.")
                        .font(.caption).foregroundStyle(.secondary)
                case .unavailable(let reason):
                    Text(reason).font(.subheadline).foregroundStyle(.secondary)
                }
            } else { ProgressView("Checking available position data…") }
        }
        .padding(16).frame(maxWidth:.infinity,alignment:.leading)
        .background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:20))
        .task(id:event.id) { await model.load(event:event) }
        .onDisappear { model.stopLocation() }
        .sheet(isPresented:$showsMap) { EventVisibilityMapView(event:event,model:model) }
    }
}
