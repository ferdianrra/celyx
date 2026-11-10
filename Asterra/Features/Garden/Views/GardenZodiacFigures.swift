import SwiftUI
import UIKit
import QuartzCore

/// Preparing artwork never runs in the motion-driven rendering path.
struct GardenZodiacFigures: View {
    let unlocked: [GardenZodiacFigure]
    let projected: [ProjectedConstellationFigure]
    let skyClip: [CGPoint]
    var isActive = true

    @State private var knownIDs: Set<String>?
    @State private var animatedIDs: Set<String> = []
    @State private var artwork: [String: GardenZodiacArtwork] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GardenZodiacFigureLayers(unlockedIDs: Set(unlocked.map(\.id)), projected: projected,
            skyClip: skyClip, artwork: artwork, animatedIDs: animatedIDs,
            isActive: isActive, reduceMotion: reduceMotion)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: unlocked.map(\.id)) {
            let current = Set(unlocked.map(\.id))
            let added = current.subtracting(knownIDs ?? current)
            knownIDs = current
            animatedIDs = animatedIDs.intersection(current).union(added)
            artwork = artwork.filter { current.contains($0.key) }
            for item in unlocked where artwork[item.id] == nil {
                let decoded = await GardenZodiacArtworkStore.shared.load(assetNamed: item.assetName)
                guard !Task.isCancelled else { return }
                artwork[item.id] = decoded
            }
        }
    }
}

private struct GardenZodiacFigureLayers: UIViewRepresentable {
    let unlockedIDs: Set<String>
    let projected: [ProjectedConstellationFigure]
    let skyClip: [CGPoint]
    let artwork: [String: GardenZodiacArtwork]
    let animatedIDs: Set<String>
    let isActive: Bool
    let reduceMotion: Bool

    func makeUIView(context: Context) -> GardenZodiacFigureLayerView { GardenZodiacFigureLayerView() }
    func updateUIView(_ view: GardenZodiacFigureLayerView, context: Context) {
        view.update(unlockedIDs: unlockedIDs, projected: projected, skyClip: skyClip,
                    artwork: artwork, animatedIDs: animatedIDs, isActive: isActive, reduceMotion: reduceMotion)
    }
}

/// Image contents stay on the compositor; sensor frames update only affine transforms and the horizon mask.
final class GardenZodiacFigureLayerView: UIView {
    private let horizonMask = CAShapeLayer()
    private var figures: [String: CALayer] = [:]
    private var revealed: Set<String> = []

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        layer.mask = horizonMask
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        horizonMask.frame = bounds
        CATransaction.commit()
    }

    func update(unlockedIDs: Set<String>, projected: [ProjectedConstellationFigure], skyClip: [CGPoint],
                artwork: [String: GardenZodiacArtwork], animatedIDs: Set<String>,
                isActive: Bool, reduceMotion: Bool) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for id in Array(figures.keys) where !unlockedIDs.contains(id) {
            figures.removeValue(forKey: id)?.removeFromSuperlayer()
            revealed.remove(id)
        }
        let clip = CGMutablePath()
        if let first = skyClip.first {
            clip.move(to: first)
            for point in skyClip.dropFirst() { clip.addLine(to: point) }
            clip.closeSubpath()
        }
        horizonMask.path = clip
        for container in figures.values { container.isHidden = true }

        for drawing in projected {
            guard let asset = artwork[drawing.id] else { continue }
            let container: CALayer
            if let existing = figures[drawing.id] {
                container = existing
            } else {
                container = CALayer()
                container.name = drawing.id
                container.anchorPoint = .zero
                container.position = .zero
                container.bounds = CGRect(x: 0, y: 0, width: drawing.figure.definition.size[0],
                                           height: drawing.figure.definition.size[1])
                let image = CALayer(); image.name = "artwork"
                image.frame = container.bounds; image.contents = asset.image
                let glow = CALayer(); glow.name = "glow"
                glow.frame = container.bounds; glow.contents = asset.glow; glow.opacity = 0
                container.addSublayer(image); container.addSublayer(glow)
                layer.addSublayer(container)
                figures[drawing.id] = container
            }
            container.isHidden = !isActive
            container.setAffineTransform(drawing.transform)
            guard let image = container.sublayers?.first, let glow = container.sublayers?.last else { continue }
            image.opacity = Float(drawing.opacity)
            if reduceMotion || !isActive {
                image.removeAllAnimations(); glow.removeAllAnimations(); glow.opacity = 0
            }
            guard isActive, !revealed.contains(drawing.id) else { continue }
            revealed.insert(drawing.id)
            guard animatedIDs.contains(drawing.id), !reduceMotion else { continue }
            let start = CACurrentMediaTime()
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0; fade.toValue = drawing.opacity
            fade.duration = 1.8; fade.beginTime = start
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            image.add(fade, forKey: "zodiac-reveal")
            let bloom = CAKeyframeAnimation(keyPath: "opacity")
            bloom.values = [0, 0.24, 0]; bloom.keyTimes = [0, 0.45, 1]
            bloom.duration = 1.8; bloom.beginTime = start
            glow.add(bloom, forKey: "zodiac-glow")
        }
    }
}
