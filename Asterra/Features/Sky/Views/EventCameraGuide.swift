import SwiftUI

/// Where a sky event sits relative to the live camera, refreshed while the star camera runs in event mode.
struct EventCameraGuide: Equatable {
    /// On-screen position, when the event is inside the camera view.
    var point: CGPoint?
    /// Shortest turn toward the event, in screen space (x right, y down).
    var arrow: CGVector
    /// Angle between the camera centre and the event, in degrees.
    var separation: Double
    var azimuth: Double
    var altitude: Double

    /// Close enough to the centre circle to collect.
    var isAimed: Bool { separation <= 8 && altitude > 0 }

    /// Screen direction from `center` toward the event: straight at it when visible, else the shortest turn.
    func pointing(from center: CGPoint) -> CGVector {
        guard let point else { return arrow }
        let dx = point.x - center.x, dy = point.y - center.y
        let length = hypot(dx, dy)
        return length < 1 ? arrow : CGVector(dx: dx / length, dy: dy / length)
    }

    var compass: String {
        let names = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
        return names[Int(((azimuth.truncatingRemainder(dividingBy: 360) + 360 + 22.5) / 45)) % 8]
    }
}

/// Top banner: the event and the only time it can be collected (the same window as its card).
struct EventWindowBanner: View {
    let event: SkyEvent
    let now: Date

    private var status: (text: String, color: Color) {
        if event.isOpen(at: now) {
            return ("Open now · until " + event.end.formatted(date: .omitted, time: .shortened), .green)
        }
        if event.hasEnded(at: now) { return ("This event has ended", .red) }
        let remaining = event.start.timeIntervalSince(now)
        let text =
            remaining < 86400
            ? "Opens in " + Duration.seconds(remaining).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
            : event.opensLabel
        return (text, .orange)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                SkyEventKindLabel(kind: event.kind, size: 12, opacity: 0.7)
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    Circle().fill(status.color).frame(width: 7, height: 7)
                    Text(status.text).font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
            }
            Text(event.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.8)
            Label {
                Text("Can only be collected \(event.collectWindow)")
            } icon: {
                Image(systemName: "clock")
            }
            .font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.black.opacity(0.25)), in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
}

/// Ring drawn on the sky where the event is.
struct EventGuideMarker: View {
    let title: String
    let isAimed: Bool
    var body: some View {
        VStack(spacing: 6) {
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: isAimed ? [] : [6, 5]))
                .foregroundStyle(isAimed ? Color.green : .white)
                .frame(width: 92, height: 92)
                .shadow(color: .black.opacity(0.4), radius: 2)
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .glassEffect(.regular, in: .capsule)
        }
        .offset(y: 20)
        .animation(.snappy, value: isAimed)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Big arrow orbiting the centre circle, pointing toward the event as the phone moves.
struct EventDirectionArrow: View {
    let arrow: CGVector
    let size: CGSize
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let orbit: CGFloat = 96
        let center = CGPoint(x: size.width / 2, y: size.height / 2 + 10)
        let angle = atan2(arrow.dy, arrow.dx)
        Image(systemName: "location.north.fill")
            .font(.system(size: 46, weight: .bold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 4)
            // The symbol points up; rotate it onto the arrow's screen angle.
            .rotationEffect(.radians(angle + .pi / 2))
            .offset(x: cos(angle) * (pulse ? 10 : 0), y: sin(angle) * (pulse ? 10 : 0))
            .position(x: center.x + cos(angle) * orbit, y: center.y + sin(angle) * orbit)
            .animation(.smooth(duration: 0.25), value: angle)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Bottom guidance and the collect button for an event.
struct EventCollectPanel: View {
    let event: SkyEvent
    let guide: EventCameraGuide?
    let now: Date
    let isCollected: Bool
    let onCollect: () -> Void

    private var message: String {
        if isCollected { return "\(event.title) is in your collection" }
        guard let guide else { return "Hold your phone up to the sky to find \(event.title)" }
        if guide.altitude <= 0 {
            return "It’s below your horizon right now. Face the \(guide.compass) during the viewing time."
        }
        if guide.isAimed { return "You’re facing \(event.title)" }
        return "Follow the arrow"
    }

    var body: some View {
        VStack(spacing: 20) {
            CameraCollectionPrompt(text: message, ready: guide?.isAimed == true)
            button
        }
    }

    @ViewBuilder private var button: some View {
        if isCollected {
            CelyxPillButton(title: "Collected", systemImage: "checkmark", style: .collected) {}
                .allowsHitTesting(false)
        } else if event.hasEnded(at: now) {
            CelyxPillButton(title: "This event has ended", style: .disabled) {}
        } else if !event.isOpen(at: now) {
            CelyxPillButton(title: event.opensLabel, style: .disabled) {}
        } else if guide?.isAimed == true {
            CelyxPillButton(title: "Collect this event", action: onCollect)
        } else {
            CelyxPillButton(title: "Point at the event to collect", style: .disabled) {}
        }
    }
}
