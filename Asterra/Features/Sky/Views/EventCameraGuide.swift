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

    /// Close enough to the centre to collect.
    var isAimed: Bool { separation <= 8 && altitude > 0 }

    /// Screen direction from `center` toward the event: straight at it when visible, else the shortest turn.
    func pointing(from center: CGPoint) -> CGVector {
        guard let point else { return arrow }
        let dx = point.x - center.x, dy = point.y - center.y
        let length = hypot(dx, dy)
        return length < 1 ? arrow : CGVector(dx: dx / length, dy: dy / length)
    }

    /// Short Find My–style wording under the angle.
    var relation: String {
        if isAimed { return "ahead" }
        if altitude <= 0 { return "below the horizon" }
        if abs(arrow.dx) >= abs(arrow.dy) { return arrow.dx > 0 ? "to your right" : "to your left" }
        return arrow.dy > 0 ? "lower" : "higher"
    }
}

/// Apple "Nearby" (Precision Finding) style guide: one big arrow that turns toward the event, the angle
/// left to turn, and a green screen once the camera faces it. No cards over the sky.
struct EventNearbyFinder: View {
    let guide: EventCameraGuide?
    let size: CGSize
    /// Unwrapped arrow angle, so it turns the short way instead of spinning around at ±180°.
    @State private var angle: Double = 0
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var center: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2 + 10) }
    private var aimed: Bool { guide?.isAimed == true }
    private var targetAngle: Double? {
        guard let guide else { return nil }
        let v = guide.pointing(from: center)
        return atan2(v.dy, v.dx) + .pi / 2  // the arrow symbol points up
    }

    var body: some View {
        ZStack {
            // The whole screen washes green when the event is straight ahead, like Find My.
            Color.green.opacity(aimed ? 0.32 : 0).ignoresSafeArea()

            Group {
                if aimed {
                    Circle().fill(.white)
                        .frame(width: 128, height: 128)
                        .scaleEffect(pulse ? 1.06 : 0.94)
                        .transition(.scale.combined(with: .opacity))
                } else if guide != nil {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 150, weight: .bold))
                        .foregroundStyle(.white)
                        .rotationEffect(.radians(angle))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 6)
            .position(center)

            if let guide {
                VStack(alignment: .leading, spacing: 0) {
                    Text(aimed ? "Here" : "\(Int(guide.separation.rounded()))°")
                        .font(.system(size: 64, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                    Text(guide.relation).font(.system(size: 24, weight: .medium))
                        .opacity(0.8)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 28).padding(.bottom, 150)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: aimed)
        .animation(.snappy, value: Int(guide?.separation.rounded() ?? 0))
        .onChange(of: targetAngle, initial: true) { _, value in
            guard let value else { return }
            var delta = (value - angle).truncatingRemainder(dividingBy: 2 * .pi)
            if delta > .pi { delta -= 2 * .pi } else if delta < -.pi { delta += 2 * .pi }
            // Updates arrive every frame; a short interactive spring follows them without lag or stutter.
            withAnimation(reduceMotion ? nil : .interactiveSpring(response: 0.15, dampingFraction: 0.9)) {
                angle += delta
            }
        }
        .onChange(of: aimed, initial: true) { _, value in
            guard value, !reduceMotion else { pulse = false; return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
        }
        // A tick every 10° closer, and a success tap once it's straight ahead.
        .sensoryFeedback(.selection, trigger: Int((guide?.separation ?? 0) / 10))
        .sensoryFeedback(.success, trigger: aimed) { _, now in now }
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(
            guide.map { aimed ? "Facing the event" : "\(Int($0.separation.rounded())) degrees \($0.relation)" }
                ?? "Finding the event")
    }
}

/// The collect button for an event; it carries the timing so nothing else covers the sky.
struct EventCollectPanel: View {
    let event: SkyEvent
    let guide: EventCameraGuide?
    let now: Date
    let isCollected: Bool
    let onCollect: () -> Void

    private var opensTitle: String {
        let start = event.nextNight(after: now)?.start ?? event.start
        let remaining = start.timeIntervalSince(now)
        guard remaining < 86400 else { return event.opensLabel }
        return "Opens in "
            + Duration.seconds(remaining).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    var body: some View {
        if isCollected {
            CelyxPillButton(title: "Collected", systemImage: "checkmark", style: .collected) {}
                .allowsHitTesting(false)
        } else if event.hasEnded(at: now) {
            CelyxPillButton(title: "This event has ended", style: .disabled) {}
        } else if !event.isOpen(at: now) {
            CelyxPillButton(title: opensTitle, systemImage: "lock.fill", style: .disabled) {}
        } else if guide?.isAimed == true {
            CelyxPillButton(title: "Collect this event", action: onCollect)
        } else {
            CelyxPillButton(title: "Follow the arrow", style: .disabled) {}
        }
    }
}
