import SwiftUI
import SceneKit

struct GardenSpaceView: UIViewRepresentable {
    let items: [GardenCollectionItem]
    let selectedID: Int?
    let rotation: Double
    let elevation: Double
    let zoom: Double
    let travel: Double
    let isActive: Bool
    let select: (Int) -> Void

    func makeUIView(context: Context) -> GardenSpaceCanvas {
        let view = GardenSpaceCanvas()
        view.select = select
        return view
    }
    func updateUIView(_ view: GardenSpaceCanvas,context: Context) {
        view.select = select
        view.isPlaying = isActive
        view.update(items:items,selectedID:selectedID,rotation:rotation,elevation:elevation,zoom:zoom,travel:travel)
    }
    static func dismantleUIView(_ view: GardenSpaceCanvas,coordinator: ()) { view.isPlaying = false }
}

final class GardenSpaceCanvas: SCNView {
    var select: ((Int) -> Void)?
    private let galaxyRoot = SCNNode()
    private let cameraNode = SCNNode()
    private let collectionRoot = SCNNode()
    private var markers: [Int:SCNNode] = [:]
    private var ids: [Int] = []
    private var selected: Int?
    private var callout: SCNNode?

    init() {
        super.init(frame:.zero,options:nil)
        backgroundColor = .black
        isOpaque = true
        antialiasingMode = .multisampling2X
        preferredFramesPerSecond = 30
        let world = SCNScene()
        world.background.contents = UIColor.black
        scene = world
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 52
        cameraNode.camera?.projectionDirection = .vertical
        cameraNode.camera?.zNear = 0.05
        cameraNode.camera?.zFar = 180
        cameraNode.camera?.wantsHDR = true
        cameraNode.camera?.bloomIntensity = 0.35
        cameraNode.camera?.bloomThreshold = 0.85
        cameraNode.camera?.bloomBlurRadius = 9
        world.rootNode.addChildNode(cameraNode)
        pointOfView = cameraNode
        world.rootNode.addChildNode(galaxyRoot)
        galaxyRoot.addChildNode(collectionRoot)
        galaxyRoot.addChildNode(GardenGalaxyGeometry.make())
        world.rootNode.addChildNode(GardenGalaxyGeometry.background())
        addGestureRecognizer(UITapGestureRecognizer(target:self,action:#selector(tapped(_:))))
        isPlaying = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(items: [GardenCollectionItem],selectedID: Int?,rotation: Double,elevation: Double,zoom: Double,travel: Double) {
        let progress = min(1,max(0,(travel-0.15)/0.85))
        // Fit the full disc to portrait width before allowing the user to move closer.
        let aspect = max(0.4,Double(bounds.width/max(1,bounds.height)))
        let overview = max(11.8,7.2/(tan(26 * .pi/180)*aspect*sqrt(1+0.63*0.63)))
        let distance = exp(log(48)+(log(overview)-log(48))*progress)/max(0.5,zoom)
        let orbitRadius = distance*sqrt(1+0.63*0.63)
        let pitch = min(85 * .pi/180,max(-80 * .pi/180,elevation))
        cameraNode.position = SCNVector3(Float(sin(progress * .pi)*1.2),Float(orbitRadius*sin(pitch)),Float(orbitRadius*cos(pitch)))
        cameraNode.look(at:SCNVector3(0,0,0))
        galaxyRoot.eulerAngles.y = Float(-rotation)
        if ids != items.map(\.id) {
            ids = items.map(\.id)
            collectionRoot.childNodes.forEach { $0.removeFromParentNode() }
            markers.removeAll()
            for item in items {
                let point = GardenOrbit.point(id:item.id,rotation:0,diameter:14,center:.zero)
                let node = GardenBodyAssets.body(item.star)
                node.position = SCNVector3(Float(point.x),0.16,Float(point.y/0.58))
                collectionRoot.addChildNode(node); markers[item.id] = node
            }
            selected = nil
        }
        // A shared update rotates the meshes; no per-object timers or material recompiles.
        for (id,node) in markers {
            node.eulerAngles.y = Float(rotation*2+GardenOrbit.angle(id:id))
            let scale: Float = id == selectedID ? 2 : 1
            node.scale = SCNVector3(scale,scale,scale)
        }
        if selected != selectedID {
            selected = selectedID
            callout?.removeFromParentNode(); callout = nil
            if let id = selectedID, let item = items.first(where:{ $0.id == id }), let marker = markers[id] {
                makeCallout(title:item.star.title,position:marker.position)
            }
        }
        if !isPlaying { setNeedsDisplay() }
    }
    private func makeCallout(title: String,position: SCNVector3) {
        let group = SCNNode()
        group.position = position
        let line = SCNCylinder(radius:0.007,height:0.7)
        line.firstMaterial?.lightingModel = .constant
        line.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.8)
        let stem = SCNNode(geometry:line); stem.position.y = 0.35
        group.addChildNode(stem)
        let text = SCNText(string:title,extrusionDepth:0)
        text.font = UIFont.systemFont(ofSize:0.25,weight:.medium)
        text.flatness = 0.2
        text.firstMaterial?.lightingModel = .constant
        text.firstMaterial?.diffuse.contents = UIColor.white
        let label = SCNNode(geometry:text)
        let bounds = text.boundingBox
        label.pivot = SCNMatrix4MakeTranslation((bounds.min.x+bounds.max.x)/2,(bounds.min.y+bounds.max.y)/2,0)
        label.position.y = 0.9
        label.constraints = [SCNBillboardConstraint()]
        group.addChildNode(label)
        collectionRoot.addChildNode(group); callout = group
    }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in:self)
        let nearest = markers.compactMap { id,node -> (Int,Double)? in
            let point = projectPoint(node.presentation.worldPosition)
            guard point.z > 0 && point.z < 1 else { return nil }
            return (id,hypot(Double(point.x)-location.x,Double(point.y)-location.y))
        }.filter { $0.1 < 30 }.min { $0.1 < $1.1 }
        if let id = nearest?.0 { select?(id) }
    }
}
