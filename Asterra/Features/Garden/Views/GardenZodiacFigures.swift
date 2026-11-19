import SwiftUI
import UIKit
import QuartzCore

/// Preparing artwork never runs in the motion-driven rendering path.
struct GardenZodiacFigures: View {
    let unlocked: [GardenZodiacFigure]
    let projected: [ProjectedConstellationFigure]
    let skyMask: CGImage?
    var isActive = true

    @State private var knownIDs: Set<String>?
    @State private var animatedIDs: Set<String> = []
    @State private var artwork: [String: GardenZodiacArtwork] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GardenZodiacFigureLayers(unlockedIDs: Set(unlocked.map(\.id)), projected: projected,
            skyMask: skyMask, artwork: artwork, animatedIDs: animatedIDs,
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
    let skyMask: CGImage?
    let artwork: [String: GardenZodiacArtwork]
    let animatedIDs: Set<String>
    let isActive: Bool
    let reduceMotion: Bool

    func makeUIView(context: Context) -> GardenZodiacFigureLayerView { GardenZodiacFigureLayerView() }
    func updateUIView(_ view: GardenZodiacFigureLayerView, context: Context) {
        view.update(unlockedIDs: unlockedIDs, projected: projected, skyMask: skyMask,
                    artwork: artwork, animatedIDs: animatedIDs, isActive: isActive, reduceMotion: reduceMotion)
    }
}

/// Image contents stay on the compositor; sensor frames update transforms, visibility and the horizon mask.
final class GardenZodiacFigureLayerView: UIView {
    /// Soft horizon: an alpha image stretched over the view (see GardenZodiacFigure.skyMask).
    private let horizonMask = CALayer()
    private var figures: [String: CALayer] = [:]
    private var revealed: Set<String> = []

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        horizonMask.contentsGravity = .resize
        horizonMask.magnificationFilter = .linear
        layer.mask = horizonMask
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        horizonMask.frame = bounds
        CATransaction.commit()
    }

    func update(unlockedIDs: Set<String>, projected: [ProjectedConstellationFigure], skyMask: CGImage?,
                artwork: [String: GardenZodiacArtwork], animatedIDs: Set<String>,
                isActive: Bool, reduceMotion: Bool) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for id in Array(figures.keys) where !unlockedIDs.contains(id) {
            figures.removeValue(forKey: id)?.removeFromSuperlayer()
            revealed.remove(id)
        }
        horizonMask.contents = skyMask
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
                container.allowsGroupOpacity = false
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
            // Keep the camera fade live while the image and glow animate on the sublayers.
            container.opacity = Float(drawing.opacity)
            guard let image = container.sublayers?.first, let glow = container.sublayers?.last else { continue }
            if reduceMotion || !isActive {
                image.removeAllAnimations(); glow.removeAllAnimations(); glow.opacity = 0
            }
            guard isActive, !revealed.contains(drawing.id) else { continue }
            revealed.insert(drawing.id)
            guard animatedIDs.contains(drawing.id), !reduceMotion else { continue }
            // The whole figure materialises at once: a soft fade with a slight settle (1.04 → 1)
            // around its own centre and a brief glow, instead of edges popping in.
            let start = CACurrentMediaTime()
            let ease = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1)
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0; fade.toValue = 1
            fade.duration = 2.2; fade.beginTime = start
            fade.timingFunction = ease
            image.add(fade, forKey: "zodiac-reveal")
            let settle = CABasicAnimation(keyPath: "transform.scale")
            settle.fromValue = 1.04; settle.toValue = 1
            settle.duration = 2.2; settle.beginTime = start
            settle.timingFunction = ease
            image.add(settle, forKey: "zodiac-settle")
            glow.add(settle, forKey: "zodiac-settle")
            let bloom = CAKeyframeAnimation(keyPath: "opacity")
            bloom.values = [0, 0.375, 0]; bloom.keyTimes = [0, 0.45, 1]
            bloom.duration = 2.2; bloom.beginTime = start
            bloom.timingFunction = ease
            glow.add(bloom, forKey: "zodiac-glow")
        }
    }
}
