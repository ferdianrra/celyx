import SwiftUI

extension GardenCollectionItem {
    var albumLocation: String {
        ObservationPlaceName.readableName(city: record.placeName, region: nil)
            ?? ObservationPlaceName.shared.cached(latitude: record.latitude, longitude: record.longitude)
            ?? "Location unavailable"
    }
    var albumSubtitle: String {
        if star.isSolarSystemBody { return star.kind }
        if let code = star.con, let name = ConstellationNames.name(for: code) {
            return "Star in \(name)"
        }
        return "Star"
    }
    var albumDate: String {
        record.date.formatted(
            .dateTime.day().month(.wide).year().hour().minute().locale(Locale(identifier: "en_GB")))
    }
    var albumNote: String {
        let note = record.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return note.isEmpty ? "A sky observation captured with Celyx." : note
    }
}

/// The reference palette: dark center, blue inner glow, violet and lavender rim.
struct StarAlbumSurface: View {
    var cornerRadius: CGFloat = 28
    var body: some View {
        GeometryReader { geometry in
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            let scale = min(geometry.size.width / 360, geometry.size.height / 640)
            shape.fill(Color(hex: 0x191820))
                .overlay(
                    shape.stroke(Color(hex: 0x062277), lineWidth: 110 * scale).blur(radius: 38 * scale)
                )
                .overlay(shape.stroke(Color(hex: 0x156BFC), lineWidth: 45 * scale).blur(radius: 24 * scale))
                .overlay(shape.stroke(Color(hex: 0x7052FF), lineWidth: 20 * scale).blur(radius: 13 * scale))
                .overlay(shape.stroke(Color(hex: 0xDFCFF8), lineWidth: 5 * scale).blur(radius: 5 * scale))
                .clipShape(shape)
                .overlay(shape.strokeBorder(.white.opacity(0.25), lineWidth: 1))
        }
    }
}

struct StarAlbumPaper: View {
    let item: GardenCollectionItem
    let photo: UIImage?
    var limitsNote = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                    } else {
                        CelyxColor.night.overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 260).clipped()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.9)], startPoint: .center, endPoint: .bottom)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "location").font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.albumLocation).font(.system(size: 11, weight: .semibold)).lineLimit(2)
                        Text(item.albumDate).font(.system(size: 9)).foregroundStyle(.white.opacity(0.75))
                    }
                }
                .foregroundStyle(.white).padding(12)
            }
            .frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 7) {
                Text("About this moment").font(.system(size: 11, weight: .semibold))
                Text(item.albumNote).font(.system(size: 11)).italic().lineSpacing(3)
                    .lineLimit(limitsNote ? 8 : nil)
                if item.record.identificationNote != nil {
                    Text("Estimated identity · not independently confirmed")
                        .font(.system(size: 9)).foregroundStyle(.black.opacity(0.6))
                }
            }
            .foregroundStyle(.black).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4).padding(.bottom, 5)
        }
        .padding(8).background(.white, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.3), radius: 15, y: 10)
    }
}

/// The same composition is previewed and exported; no status bar or toolbar is baked in.
struct StarStoryTemplate: View {
    let item: GardenCollectionItem
    let photo: UIImage?
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 4) {
                Text(item.star.title).font(.system(size: 25, weight: .bold)).lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(item.albumSubtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white).padding(.bottom, 24)
            StarAlbumPaper(item: item, photo: photo, limitsNote: true).padding(.horizontal, 30)
            Spacer(minLength: 20)
            Text("Celyx").font(.system(size: 24, weight: .bold)).foregroundStyle(.white).padding(
                .bottom, 44)
        }
        .frame(width: 360, height: 640)
        .background { StarAlbumSurface(cornerRadius: 0) }
        .environment(\.colorScheme, .dark)
    }
}

#Preview("Album paper") {
    StarAlbumPaper(item: AppPreviewData.item, photo: nil).padding(30).background {
        StarAlbumSurface()
    }
}
#Preview("Story template") { StarStoryTemplate(item: AppPreviewData.item, photo: nil) }
#Preview("Album palette") { StarAlbumSurface().frame(width: 330, height: 540).padding() }
