import SwiftUI

struct GardenCollectionView: View {
    let model: HomeViewModel
    let select: (Int) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    private var items: [GardenCollectionItem] {
        model.collectionItems.filter { query.isEmpty || $0.star.title.localizedCaseInsensitiveContains(query) }
    }
    private var locked: [CatalogStar] {
        ([CatalogStar.sun,CatalogStar.moon]+model.stars.filter(\.hasCommonName)).filter {
            model.collected[$0.id] == nil && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query))
        }.prefix(6).map { $0 }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:14) {
                if model.collectionItems.isEmpty && query.isEmpty {
                    ContentUnavailableView("Your sky is waiting",systemImage:"sparkles",description:Text("Collect a star to keep its photo and note here."))
                } else if !items.isEmpty {
                    Text("Collected · \(items.count)").font(.subheadline).foregroundStyle(.secondary).padding(.vertical,4)
                    ForEach(items) { item in
                        Button {
                            select(item.id); dismiss()
                        } label: { GardenCollectionCard(star:item.star,record:item.record) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("collection-item-\(item.id)")
                    }
                }
                if !locked.isEmpty {
                    Text("Still to discover").font(.subheadline).foregroundStyle(.secondary).padding(.top,14)
                    ForEach(locked) { star in
                        GardenCollectionCard(star:star)
                            .accessibilityElement(children:.combine)
                    }
                } else if items.isEmpty && !query.isEmpty {
                    ContentUnavailableView.search(text:query)
                }
            }.padding(20)
        }
        .background(Color(white:0.07))
        .navigationTitle("Collection")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text:$query,prompt:"Find a memory")
        .preferredColorScheme(.dark)
    }
}
