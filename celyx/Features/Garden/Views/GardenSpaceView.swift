import SwiftUI
import SceneKit

struct GardenSpaceView: UIViewRepresentable {
    let items: [GardenCollectionItem]
    let selectedID: Int?
    let rotation: Double
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
        view.update(items:items,selectedID:selectedID,rotation:rotation,zoom:zoom,travel:travel)
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
        antialiasingMode = .multisampling4X
        preferredFramesPerSecond = 30
        let world = SCNScene()
        world.background.contents = UIColor.black
        scene = world
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 52
        cameraNode.camera?.zNear = 0.05
        cameraNode.camera?.zFar = 180
        cameraNode.camera?.wantsHDR = true
        cameraNode.camera?.bloomIntensity = 0.55
        cameraNode.camera?.bloomThreshold = 0.85
        cameraNode.camera?.bloomBlurRadius = 9
        world.rootNode.addChildNode(cameraNode)
        pointOfView = cameraNode
        world.rootNode.addChildNode(galaxyRoot)
        galaxyRoot.addChildNode(collectionRoot)
        makeDisc()
        galaxyRoot.addChildNode(makeStars(count:5200,spiral:true))
        world.rootNode.addChildNode(makeStars(count:900,spiral:false))
        addGestureRecognizer(UITapGestureRecognizer(target:self,action:#selector(tapped(_:))))
        isPlaying = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func makeDisc() {
        guard let url = try? SkyAssets.url("your-galaxy-1400",extension:"jpg"), let image = UIImage(contentsOfFile:url.path) else { return }
        let plane = SCNPlane(width:14,height:14)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = image
        material.emission.contents = image
        material.emission.intensity = 0.4
        material.isDoubleSided = true
        material.blendMode = .add
        material.writesToDepthBuffer = false
        // Feather the edge of the disc in its own plane, before perspective projection.
        material.transparent.contents = UIGraphicsImageRenderer(size:CGSize(width:256,height:256)).image { renderer in
            let colors = [UIColor.white.cgColor,UIColor.white.cgColor,UIColor.clear.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,0.73,1]) {
                renderer.cgContext.drawRadialGradient(gradient,startCenter:CGPoint(x:128,y:128),startRadius:0,
                    endCenter:CGPoint(x:128,y:128),endRadius:128,options:.drawsAfterEndLocation)
            }
        }
        material.transparencyMode = .aOne
        plane.firstMaterial = material
        let disc = SCNNode(geometry:plane)
        disc.eulerAngles.x = -.pi/2
        galaxyRoot.addChildNode(disc)
    }
    private func makeStars(count: Int,spiral: Bool) -> SCNNode {
        var vertices: [SCNVector3] = []
        var colors: [SIMD4<Float>] = []
        var seed: UInt64 = spiral ? 53 : 97
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 32) % 100000)/100000
        }
        for index in 0..<count {
            if spiral {
                let radius = 0.35+pow(random(),0.65)*6.3
                let angle = radius*0.95+Double(index%3)*2 * .pi/3+(random()-0.5)*0.85
                vertices.append(SCNVector3(Float(cos(angle)*radius),Float((random()-0.5)*0.32),Float(sin(angle)*radius)))
                let warm = radius < 1.8
                colors.append(SIMD4(warm ? 1 : 0.74,warm ? 0.88 : 0.83,warm ? 0.65 : 1,Float(0.25+random()*0.65)))
            } else {
                vertices.append(SCNVector3(Float((random()-0.5)*35),Float((random()-0.3)*24),Float((random()-0.1)*65)))
                colors.append(SIMD4(0.8,0.87,1,Float(0.2+random()*0.65)))
            }
        }
        let source = SCNGeometrySource(vertices:vertices)
        let colorData = colors.withUnsafeBytes { Data($0) }
        let colorSource = SCNGeometrySource(data:colorData,semantic:.color,vectorCount:count,usesFloatComponents:true,
            componentsPerVector:4,bytesPerComponent:4,dataOffset:0,dataStride:16)
        let indices = (0..<count).map(UInt32.init)
        let element = SCNGeometryElement(data:indices.withUnsafeBytes { Data($0) },primitiveType:.point,primitiveCount:count,bytesPerIndex:4)
        element.pointSize = spiral ? 2 : 2.8
        element.minimumPointScreenSpaceRadius = 0.35
        element.maximumPointScreenSpaceRadius = spiral ? 2.2 : 3.5
        let geometry = SCNGeometry(sources:[source,colorSource],elements:[element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.white
        material.blendMode = .add
        material.writesToDepthBuffer = false
        geometry.firstMaterial = material
        return SCNNode(geometry:geometry)
    }

    func update(items: [GardenCollectionItem],selectedID: Int?,rotation: Double,zoom: Double,travel: Double) {
        let progress = min(1,max(0,(travel-0.15)/0.85))
        let distance = exp(log(48)+(log(11.8)-log(48))*progress)/max(0.5,zoom)
        cameraNode.position = SCNVector3(Float(sin(progress * .pi)*1.2),Float(distance*0.63),Float(distance))
        cameraNode.look(at:SCNVector3(0,0,0))
        galaxyRoot.eulerAngles.y = Float(-rotation)
        if ids != items.map(\.id) {
            ids = items.map(\.id)
            collectionRoot.childNodes.forEach { $0.removeFromParentNode() }
            markers.removeAll()
            for item in items {
                let point = GardenOrbit.point(id:item.id,rotation:0,diameter:14,center:.zero)
                let sphere = SCNSphere(radius:0.075)
                sphere.segmentCount = 16
                let color = item.star.isSun ? UIColor(red:1,green:0.7,blue:0.3,alpha:1) : .white
                sphere.firstMaterial?.lightingModel = .constant
                sphere.firstMaterial?.diffuse.contents = color
                sphere.firstMaterial?.emission.contents = color
                sphere.firstMaterial?.emission.intensity = 2
                let node = SCNNode(geometry:sphere)
                node.position = SCNVector3(Float(point.x),0.16,Float(point.y/0.58))
                collectionRoot.addChildNode(node); markers[item.id] = node
            }
            selected = nil
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
