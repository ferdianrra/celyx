import SwiftUI

/// Always-visible vertical exposure rail, shared by collect and the filtered AR map.
struct CameraExposureControl: View {
    let minimum: Double
    let maximum: Double
    @Binding var value: Double
    var message: String?
    let onReset: () -> Void
    var onEditingChanged: (Bool) -> Void = { _ in }

    private var available: Bool { maximum > minimum }
    private var fraction: Double {
        available ? min(1, max(0, (value - minimum) / (maximum - minimum))) : 0.5
    }
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sun.max").font(.system(size: 18))
            GeometryReader { geometry in
                ZStack {
                    Capsule().fill(.white.opacity(0.35)).frame(width: 2)
                    Circle().fill(CelyxColor.primaryLabel).frame(width: 12, height: 12)
                        .position(
                            x: geometry.size.width / 2, y: 6 + (1 - fraction) * (geometry.size.height - 12))
                }.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0).onChanged { drag in
                            guard available else { return }
                            onEditingChanged(true)
                            value = CameraExposureGesture.value(
                                at: Double(drag.location.y - 6),
                                height: Double(geometry.size.height - 12), minimum: minimum, maximum: maximum)
                        }.onEnded { _ in onEditingChanged(false) })
            }.frame(height: 112)
            Text(available ? String(format: "%+.1f", value) : "—")
                .font(.system(size: 11, weight: .semibold)).monospacedDigit()
        }
        .foregroundStyle(CelyxColor.primaryLabel).padding(.vertical, 14).frame(width: 48)
        .background(.black.opacity(0.4), in: Capsule()).opacity(available ? 1 : 0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("camera-brightness-control")
        .accessibilityLabel("Camera brightness")
        .accessibilityValue(available ? String(format: "%+.1f EV", value) : "Unavailable")
        .accessibilityHint(message ?? "Swipe up to brighten, down to darken. Double-tap to reset.")
        .accessibilityAdjustableAction { direction in
            guard available else { return }
            onEditingChanged(true)
            defer { onEditingChanged(false) }
            switch direction {
            case .increment: value = min(maximum, value + 0.2)
            case .decrement: value = max(minimum, value - 0.2)
            @unknown default: break
            }
        }
        .onTapGesture(count: 2) {
            if available {
                onEditingChanged(true)
                onReset()
                onEditingChanged(false)
            }
        }
    }
}

#Preview("Camera brightness · vertical rail") {
    HStack {
        Spacer()
        CameraExposureControl(minimum: -3, maximum: 3, value: .constant(1.2), onReset: {})
    }
    .padding().frame(height: 400).background(CelyxColor.night).preferredColorScheme(.dark)
}
