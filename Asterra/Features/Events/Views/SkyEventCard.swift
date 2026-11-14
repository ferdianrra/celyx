import SwiftUI

/// 370×109 event card (Figma "Liquid Glass - Regular - Medium" in 998:2116): dark Liquid Glass lit by the
/// card inner-shadow stack, artwork added with Plus Lighter on the leading edge, reminder bell on the trailing one.
struct SkyEventCard: View {
    let event: SkyEvent
    let isReminderOn: Bool
    let toggleReminder: () -> Void
    @ScaledMetric(relativeTo: .body) private var cardHeight: CGFloat = 144

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
                .frame(width:90).clipped()
                // Keep artwork in its own column, away from the category and title.
                .mask(LinearGradient(stops:[.init(color:.black,location:0.72),.init(color:.clear,location:1)],
                                     startPoint:.leading,endPoint:.trailing))
                .blendMode(.plusLighter)
                .accessibilityHidden(true)
            HStack(spacing:10) {
                VStack(alignment:.leading,spacing:8) {
                    SkyEventKindLabel(kind:event.kind,size:12,opacity:0.64)
                    Text(event.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .lineLimit(2).fixedSize(horizontal:false,vertical:true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(dayText).foregroundStyle(.white.opacity(0.85))
                        Text(timeText).foregroundStyle(.white.opacity(0.65))
                    }
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth:.infinity,alignment:.leading)
                ReminderBell(isOn:isReminderOn,action:toggleReminder)
            }
            .padding(.leading,106).padding(.trailing,16).padding(.vertical,16)
        }
        .frame(height:cardHeight)
        .clipShape(shape)
        .contentShape(shape)
        .accessibilityIdentifier("sky-event-card-\(event.id)")
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
