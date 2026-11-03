import SwiftUI

struct GardenCollectionCard: View {
    let star: CatalogStar
    var record: CollectedStar?
    var isSelected = false
    var isLocked: Bool { record == nil }
    var body: some View {
        HStack(spacing:16) {
            StarPortraitView(star:star).frame(width:78,height:78)
                .saturation(isLocked ? 0.15 : 1).opacity(isLocked ? 0.45 : 1)
            VStack(alignment:.leading,spacing:8) {
                HStack(spacing:8) {
                    Text(star.title).font(.headline).lineLimit(1)
                    if !isLocked { Image(systemName:"sparkle").font(.caption).padding(.horizontal,9).padding(.vertical,3).background(.white.opacity(0.1),in:Capsule()) }
                }
                if let record {
                    Text(record.date.formatted(.dateTime.month(.abbreviated).day().year().locale(Locale(identifier:"en")))).font(.caption).foregroundStyle(.white.opacity(0.7))
                    Label(String(format:"%.2f°, %.2f°",record.latitude,record.longitude),systemImage:"location")
                        .font(.caption2).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                } else {
                    Label("Still to discover",systemImage:"lock.fill").font(.caption).foregroundStyle(.white.opacity(0.55))
                }
            }
            Spacer(minLength:0)
            if !isLocked { Image(systemName:"chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6)) }
        }
        .padding(.horizontal,16).padding(.vertical,12)
        .frame(maxWidth:.infinity,alignment:.leading)
        .background {
            RoundedRectangle(cornerRadius:25).fill(LinearGradient(
                colors:isLocked ? [Color(white:0.12),Color(white:0.09)] : [Color(red:0.29,green:0.36,blue:0.96),Color(red:0.035,green:0.10,blue:0.32),Color(red:0.035,green:0.045,blue:0.1)],
                startPoint:.topLeading,endPoint:.bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius:25).strokeBorder(.white.opacity(isSelected ? 0.55 : 0.16),lineWidth:isSelected ? 1.5 : 0.7))
        .foregroundStyle(.white)
        .contentShape(RoundedRectangle(cornerRadius:25))
    }
}
