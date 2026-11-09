import SwiftUI

/// 362×109 event card used on the Sky Calendar.
struct SkyEventCard: View {
    let event: SkyEvent
    let isReminderOn: Bool
    let toggleReminder: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        ZStack(alignment: .leading) {
            CelyxBluePanel(cornerRadius: 20)
            Color.clear
                .overlay(alignment: .topLeading) {
                    Image(event.artwork.asset).resizable().scaledToFill()
                        .frame(width: event.artwork.size, height: event.artwork.size)
                        .scaleEffect(x: event.artwork.flipped ? -1 : 1, y: 1)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .offset(x: event.artwork.x, y: event.artwork.y)
                }
                .clipShape(shape)
                // Figma blends the artwork with Screen over the blue card.
                .blendMode(.screen)
                .accessibilityHidden(true)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    SkyEventKindLabel(kind: event.kind, size: 13)
                    Text(event.title).font(.system(size: 13, weight: .semibold)).tracking(-0.08).lineSpacing(
                        0
                    ).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(event.viewingTime).font(.system(size: 12)).tracking(-0.08).foregroundStyle(
                        .white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 125).padding(.trailing, 8)
                ReminderBell(isOn: isReminderOn, action: toggleReminder).padding(.trailing, 15)
            }
        }
        .frame(height: 109)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), \(event.headerDate), \(event.viewingTime)")
    }
}

struct SkyEventKindLabel: View {
    let kind: SkyEvent.Kind
    var size: CGFloat = 13
    var body: some View {
        HStack(spacing: 6) {
            Image(kind.icon).resizable().frame(width: 15, height: 15)
            Text(kind.rawValue).font(.system(size: size)).tracking(-0.08).foregroundStyle(.white)
        }
        .frame(height: 18)
        .opacity(0.5)
    }
}

private struct ReminderBell: View {
    let isOn: Bool
    let action: () -> Void
    var body: some View {
        Group {
            if isOn {
                Button(action: action) {
                    Image(systemName: "bell.fill").font(.system(size: 16, weight: .medium)).foregroundStyle(
                        CelyxColor.bellInk
                    )
                    .frame(width: 40, height: 40).background(Circle().fill(.white)).contentShape(Circle())
                }
                .buttonStyle(.plain)
            } else {
                CelyxGlassButton(width: 40, height: 40, action: action) {
                    Image(systemName: "bell").font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
                }
            }
        }
        .accessibilityLabel(isOn ? "Turn off reminder" : "Remind me")
    }
}

#Preview("Sky event card") {
    SkyEventCard(event: SkyEvent.catalogue[0], isReminderOn: false, toggleReminder: {}).padding()
        .background(.black)
        .preferredColorScheme(.dark)
}

#Preview("Event kind label") {
    SkyEventKindLabel(kind: SkyEvent.catalogue[0].kind).padding().background(.black)
        .preferredColorScheme(.dark)
}

#Preview("Reminder bell") {
    HStack {
        ReminderBell(isOn: false, action: {})
        ReminderBell(isOn: true, action: {})
    }.padding().background(.black)
        .preferredColorScheme(.dark)
}
