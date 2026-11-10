import SwiftUI

/// The remembered world ray is reprojected as the phone turns; the reticle stays fixed.
struct CameraPinnedLightOverlay: View {
    let guide: SkyFinderProjection
    let title: String
    let isRecognizing: Bool
    var subtitle: String? = nil

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            if let point = guide.point {
                Circle().stroke(CelyxColor.primaryLabel, lineWidth: 1.5).frame(width: 18, height: 18)
                    .overlay(alignment: .top) {
                        VStack(spacing: 2) {
                            HStack(spacing: 6) {
                                if isRecognizing {
                                    ProgressView().tint(CelyxColor.primaryLabel).scaleEffect(0.75)
                                }
                                Text(title).font(.system(size: 12, weight: .semibold))
                            }
                            if let subtitle {
                                Text(subtitle).font(.system(size: 10)).foregroundStyle(
                                    CelyxColor.secondaryLabel)
                            }
                        }
                        .foregroundStyle(CelyxColor.primaryLabel).padding(.horizontal, 10).padding(
                            .vertical, 6
                        )
                        .background(.black.opacity(0.65), in: Capsule())
                        .fixedSize().offset(y: 24)
                    }
                    .position(point)
            }
            if needsArrow(from: center) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 28, weight: .semibold)).foregroundStyle(CelyxColor.primaryLabel)
                    .rotationEffect(.radians(atan2(Double(guide.arrow.dy), Double(guide.arrow.dx)) + .pi / 2))
                    .frame(width: 52, height: 52).background(.black.opacity(0.55), in: Circle())
                    .position(
                        x: center.x + guide.arrow.dx * min(geometry.size.width, geometry.size.height) * 0.25,
                        y: center.y + guide.arrow.dy * min(geometry.size.width, geometry.size.height) * 0.25)
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
    private func needsArrow(from center: CGPoint) -> Bool {
        guard let point = guide.point else { return true }
        return hypot(point.x - center.x, point.y - center.y) > 28
    }
}

#Preview("Pinned light · recognizing") {
    GeometryReader { geometry in
        CameraPinnedLightOverlay(
            guide: .init(
                point: CGPoint(x: geometry.size.width * 0.75, y: geometry.size.height * 0.35),
                arrow: CGVector(dx: 0.7, dy: -0.7), separation: 12), title: "Last seen light",
            isRecognizing: true)
    }.background(CelyxColor.night)
}

#Preview("Pinned light · outside camera") {
    CameraPinnedLightOverlay(
        guide: .init(point: nil, arrow: CGVector(dx: -1, dy: 0), separation: 80),
        title: "Sirius", isRecognizing: false, subtitle: "Estimated identity"
    ).background(CelyxColor.night)
}

#Preview("Pinned light · estimated identity") {
    GeometryReader { geometry in
        CameraPinnedLightOverlay(
            guide: .init(
                point: CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2),
                arrow: CGVector(dx: 0, dy: -1), separation: 0), title: "Sirius", isRecognizing: false,
            subtitle: "Estimated identity")
    }.background(CelyxColor.night)
}
