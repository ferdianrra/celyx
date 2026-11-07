import ARKit
import SceneKit
import SwiftUI

struct SkyCameraPreview: UIViewRepresentable {
    let session: ARSession
    let onViewport: (CGSize,UIInterfaceOrientation) -> Void
    var onTap: ((CGPoint) -> Void)? = nil
    var onHold: ((CGPoint) -> Void)? = nil
    var onExposureDrag: ((CGFloat,CGPoint,Bool) -> Void)? = nil
    var skyMarkers: [CameraSkyPrediction] = []
    var labeledMarkerIDs: Set<Int> = []
    var selectedMarkerID: Int? = nil
    var onSelectMarker: ((Int) -> Void)? = nil
    var markerColor: UIColor = .systemCyan
    var markerTitlePrefix = ""
    var zoom: Double = 1
    func makeUIView(context: Context) -> FinderCameraContainer {
        let container = FinderCameraContainer()
        container.zoom = zoom
        let view = container.cameraView
        view.session = session
        view.scene = SCNScene()
        view.preferredFramesPerSecond = 60
        view.onSelectMarker = onSelectMarker
        view.markerColor = markerColor; view.markerTitlePrefix = markerTitlePrefix
        view.viewportChanged = onViewport
        view.tapped = onTap; view.held = onHold; view.exposureDragged = onExposureDrag
        view.installCameraGestures()
        return container
    }
    func updateUIView(_ container: FinderCameraContainer,context: Context) {
        container.zoom = zoom
        let view = container.cameraView
        view.tapped = onTap; view.held = onHold; view.exposureDragged = onExposureDrag
        view.onSelectMarker = onSelectMarker
        view.markerColor = markerColor; view.markerTitlePrefix = markerTitlePrefix
        view.updateSkyMarkers(skyMarkers,labeledIDs:labeledMarkerIDs,selectedID:selectedMarkerID)
        view.updateViewport()
    }
    static func dismantleUIView(_ view: FinderCameraContainer,coordinator: ()) { view.cameraView.isPlaying = false }
}

/// Scale the entire AR composite, keeping the camera image and world markers together.
/// ARKit continues to own its camera projection and capture-device configuration.
final class FinderCameraContainer: UIView {
    let cameraView = FinderCameraView()
    var zoom: Double = 1 { didSet { updateCameraLayout() } }
    override init(frame: CGRect) {
        super.init(frame:frame)
        clipsToBounds = true
        addSubview(cameraView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() { super.layoutSubviews(); updateCameraLayout() }
    private func updateCameraLayout() {
        cameraView.bounds = CGRect(origin:.zero,size:bounds.size)
        cameraView.center = CGPoint(x:bounds.midX,y:bounds.midY)
        let scale = CGFloat(CameraZoom.clamped(zoom))
        cameraView.transform = CGAffineTransform(scaleX:scale,y:scale)
    }
}

final class FinderCameraView: ARSCNView {
    var viewportChanged: ((CGSize,UIInterfaceOrientation) -> Void)?
    var tapped: ((CGPoint) -> Void)?
    var held: ((CGPoint) -> Void)?
    var exposureDragged: ((CGFloat,CGPoint,Bool) -> Void)?
    var onSelectMarker: ((Int) -> Void)?
    var markerColor: UIColor = .systemCyan
    var markerTitlePrefix = ""
    private var skyNodes: [Int:SCNNode] = [:]
    private var exposurePanActive = false

    // SceneKit projects these world-space nodes with the camera on every render frame.
    // At 1 km, a small step barely changes their apparent celestial direction.
    func updateSkyMarkers(_ markers: [CameraSkyPrediction],labeledIDs: Set<Int>,selectedID: Int?) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        let ids = Set(markers.map(\.id))
        for id in Array(skyNodes.keys) where !ids.contains(id) {
            skyNodes.removeValue(forKey:id)?.removeFromParentNode()
        }
        for marker in markers {
            let node: SCNNode
            if let existing = skyNodes[marker.id] { node = existing }
            else {
                node = makeSkyMarker(marker)
                scene.rootNode.addChildNode(node)
                skyNodes[marker.id] = node
            }
            node.simdPosition = simd_normalize(marker.direction)*1000
            node.childNode(withName:"label",recursively:false)?.isHidden = !labeledIDs.contains(marker.id)
            node.childNode(withName:"ring",recursively:false)?.simdScale = SIMD3(repeating:marker.id == selectedID ? 1.2 : 1)
        }
        pointOfView?.camera?.zFar = 2000
        SCNTransaction.commit()
    }

    private func makeSkyMarker(_ marker: CameraSkyPrediction) -> SCNNode {
        let root = SCNNode()
        root.name = "sky:\(marker.id)"
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        root.constraints = [billboard]
        func plane(image: UIImage,width: CGFloat,height: CGFloat) -> SCNNode {
            let geometry = SCNPlane(width:width,height:height)
            geometry.firstMaterial?.diffuse.contents = image
            geometry.firstMaterial?.lightingModel = .constant
            geometry.firstMaterial?.isDoubleSided = true
            geometry.firstMaterial?.writesToDepthBuffer = false
            return SCNNode(geometry:geometry)
        }
        let color = markerColor
        let ringImage = UIGraphicsImageRenderer(size:CGSize(width:64,height:64)).image { context in
            color.setStroke()
            context.cgContext.setLineWidth(3)
            context.cgContext.strokeEllipse(in:CGRect(x:3,y:3,width:58,height:58))
        }
        let ring = plane(image:ringImage,width:28,height:28)
        ring.name = "ring"
        root.addChildNode(ring)
        let font = UIFont.systemFont(ofSize:24,weight:.medium)
        let attributes: [NSAttributedString.Key:Any] = [.font:font,.foregroundColor:color]
        let title = (markerTitlePrefix+marker.star.title) as NSString
        let size = CGSize(width:ceil(title.size(withAttributes:attributes).width)+24,height:42)
        let image = UIGraphicsImageRenderer(size:size).image { _ in
            UIColor.black.withAlphaComponent(0.65).setFill()
            UIBezierPath(roundedRect:CGRect(origin:.zero,size:size),cornerRadius:21).fill()
            title.draw(at:CGPoint(x:12,y:6),withAttributes:attributes)
        }
        let label = plane(image:image,width:size.width*0.65,height:size.height*0.65)
        label.name = "label"
        label.position.y = -32
        root.addChildNode(label)
        return root
    }

    func installCameraGestures() {
        let tap = UITapGestureRecognizer(target:self,action:#selector(didTap(_:)))
        let hold = UILongPressGestureRecognizer(target:self,action:#selector(didHold(_:)))
        hold.minimumPressDuration = 0.7
        tap.require(toFail:hold)
        addGestureRecognizer(tap); addGestureRecognizer(hold)
        if exposureDragged != nil {
            let pan = UIPanGestureRecognizer(target:self,action:#selector(didDragExposure(_:)))
            pan.minimumNumberOfTouches = 1; pan.maximumNumberOfTouches = 1
            tap.require(toFail:pan)
            addGestureRecognizer(pan)
        }
    }
    @objc private func didDragExposure(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in:superview ?? self)
        let location = gesture.location(in:superview ?? self)
        let start = CGPoint(x:location.x-translation.x,y:location.y-translation.y)
        switch gesture.state {
        case .began:
            let velocity = gesture.velocity(in:self)
            exposurePanActive = abs(velocity.y) > abs(velocity.x)
            if exposurePanActive { exposureDragged?(translation.y,start,false) }
        case .changed:
            if exposurePanActive { exposureDragged?(translation.y,start,false) }
        case .ended,.cancelled,.failed:
            if exposurePanActive { exposureDragged?(translation.y,start,true) }
            exposurePanActive = false
        default: break
        }
    }
    @objc private func didTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in:self)
        if onSelectMarker != nil {
            for hit in hitTest(point,options:nil) {
                var node: SCNNode? = hit.node
                while let current = node {
                    if let name = current.name, name.hasPrefix("sky:"),let id = Int(name.dropFirst(4)) {
                        onSelectMarker?(id); return
                    }
                    node = current.parent
                }
            }
        }
        tapped?(convert(point,to:superview))
    }
    @objc private func didHold(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { held?(convert(gesture.location(in:self),to:superview)) }
    }
    override func layoutSubviews() { super.layoutSubviews(); updateViewport() }
    func updateViewport() {
        let orientation = window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
        viewportChanged?(bounds.size,orientation)
    }
}

#Preview("Camera preview") {
    SkyCameraPreview(session:ARSession(),onViewport:{ _,_ in }).background(.black)
}
