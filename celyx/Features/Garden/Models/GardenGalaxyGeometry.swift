import SceneKit
import UIKit

/// Native adaptation of Assets Galaxy/Galaxy/3d/index.html.
/// Same four logarithmic arms, warm bar/bulge and young blue clusters; fewer particles.
@MainActor
enum GardenGalaxyGeometry {
    static var particleBudget: Int { ProcessInfo.processInfo.isLowPowerModeEnabled ? 28_000 : 64_000 }
    private struct Random {
        var seed: UInt64 = 1337
        mutating func unit() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 32) % 1_000_000)/1_000_000
        }
        mutating func normal() -> Double { sqrt(-2*log(max(0.000001,1-unit())))*cos(2 * .pi*unit()) }
    }
    static func make() -> SCNNode {
        let root = SCNNode()
        let count = particleBudget
        var random = Random()
        var positions: [SCNVector3] = [], colors: [SIMD4<Float>] = []
        positions.reserveCapacity(count); colors.reserveCapacity(count)
        let warm: [SIMD3<Float>] = [SIMD3(1,0.74,0.5),SIMD3(1,0.90,0.72),SIMD3(1,0.65,0.44)]
        let blue: [SIMD3<Float>] = [SIMD3(0.62,0.72,1),SIMD3(0.7,0.8,1),SIMD3(0.85,0.89,1)]
        let pitch = tan(12 * Double.pi/180)
        let armRadii = [29300.0,21000,15050,10780]
        let worldScale = 6.6/62000.0
        func add(_ x: Double,_ y: Double,_ z: Double,_ color: SIMD3<Float>,_ brightness: Float) {
            positions.append(SCNVector3(x*worldScale,y*worldScale,z*worldScale))
            colors.append(SIMD4(color*brightness*0.22,1))
        }
        var nebulaPositions: [SCNVector3] = [], nebulaColors: [SIMD4<Float>] = []
        var dustPositions: [SCNVector3] = []
        for i in 0..<count {
            let family = Double(i)/Double(count)
            if family < 0.13 {
                let spread = 2300*pow(random.unit(),0.7)
                let color = warm[Int(random.unit()*3)]
                add(random.normal()*spread,random.normal()*spread*0.55,random.normal()*spread,color,0.30)
            } else if family < 0.23 {
                let along = random.normal()*5600, across = random.normal()*1500
                let angle = 27 * Double.pi/180
                add(-cos(angle)*along+sin(angle)*across,random.normal()*700,
                    -sin(angle)*along-cos(angle)*across,warm[Int(random.unit()*3)],0.22)
            } else if family < 0.45 {
                let radius = -11000*log(max(0.000001,random.unit()*random.unit()))
                if radius > 62000 { continue }
                let angle = random.unit()*2 * .pi
                add(radius*cos(angle),random.normal()*(380+radius*0.012),radius*sin(angle),warm[Int(random.unit()*3)],0.10)
            } else {
                let arm = i%4
                let radius = 10000+44000*pow(random.unit(),1.45)
                let angle = Double.pi+log(radius/armRadii[arm])/pitch
                let spread = random.normal()*(750+0.03*radius)
                let young = random.unit() < 0.8
                add((radius+spread)*cos(angle),random.normal()*170,(radius+spread)*sin(angle),
                    young ? blue[Int(random.unit()*3)] : warm[Int(random.unit()*3)],young ? 0.46 : 0.22)
                if i%180 == 0 {
                    nebulaPositions.append(SCNVector3((radius+spread)*cos(angle)*worldScale,0.025,(radius+spread)*sin(angle)*worldScale))
                    nebulaColors.append(i%3 == 0 ? SIMD4(0.35,0.55,1,0.18) : SIMD4(1,0.30,0.55,0.14))
                }
                if i%40 == 0 {
                    let offset = radius-650-0.025*radius
                    dustPositions.append(SCNVector3(offset*cos(angle)*worldScale,0.04,offset*sin(angle)*worldScale))
                }
            }
        }
        root.addChildNode(points(positions,colors:colors,size:1.7))
        root.addChildNode(sheets(at:dustPositions,colors:Array(repeating:SIMD4<Float>(0,0,0,0.10),count:dustPositions.count),radius:0.11,blend:.alpha))
        root.addChildNode(sheets(at:nebulaPositions,colors:nebulaColors,radius:0.12,blend:.add))
        root.addChildNode(sheets(at:[SCNVector3(0,0.02,0)],colors:[SIMD4(1,0.70,0.38,0.24)],radius:1.25,blend:.add))
        return root
    }
    static func background() -> SCNNode {
        var random = Random(seed:97)
        var positions: [SCNVector3] = [], colors: [SIMD4<Float>] = []
        for _ in 0..<850 {
            positions.append(SCNVector3((random.unit()-0.5)*38,(random.unit()-0.3)*24,(random.unit()-0.1)*65))
            let brightness = Float(0.12+random.unit()*0.35)
            colors.append(SIMD4(0.8*brightness,0.87*brightness,brightness,1))
        }
        return points(positions,colors:colors,size:2.1)
    }
    private static func points(_ vertices: [SCNVector3],colors: [SIMD4<Float>],size: CGFloat) -> SCNNode {
        let source = SCNGeometrySource(vertices:vertices)
        let colorSource = SCNGeometrySource(data:colors.withUnsafeBytes { Data($0) },semantic:.color,
            vectorCount:colors.count,usesFloatComponents:true,componentsPerVector:4,bytesPerComponent:4,dataOffset:0,dataStride:16)
        let indices = (0..<vertices.count).map(UInt32.init)
        let element = SCNGeometryElement(data:indices.withUnsafeBytes { Data($0) },primitiveType:.point,primitiveCount:vertices.count,bytesPerIndex:4)
        element.pointSize = size; element.minimumPointScreenSpaceRadius = 0.3; element.maximumPointScreenSpaceRadius = 1.8
        let geometry = SCNGeometry(sources:[source,colorSource],elements:[element])
        let material = SCNMaterial(); material.lightingModel = .constant
        material.diffuse.contents = UIColor.white; material.blendMode = .add
        material.writesToDepthBuffer = false; material.readsFromDepthBuffer = false
        geometry.firstMaterial = material
        return SCNNode(geometry:geometry)
    }
    // Soft nebula and absorption layers are batched into two meshes, not one draw per puff.
    private static func sheets(at positions: [SCNVector3],colors: [SIMD4<Float>],radius: Float,blend: SCNBlendMode) -> SCNNode {
        var vertices: [SCNVector3] = [], uv: [CGPoint] = [], tints: [SIMD4<Float>] = [], indices: [UInt32] = []
        for (i,p) in positions.enumerated() {
            let base = UInt32(vertices.count)
            vertices += [SCNVector3(p.x-radius,p.y,p.z-radius),SCNVector3(p.x+radius,p.y,p.z-radius),
                         SCNVector3(p.x+radius,p.y,p.z+radius),SCNVector3(p.x-radius,p.y,p.z+radius)]
            uv += [CGPoint(x:0,y:0),CGPoint(x:1,y:0),CGPoint(x:1,y:1),CGPoint(x:0,y:1)]
            tints += Array(repeating:colors[i],count:4)
            indices += [base,base+1,base+2,base,base+2,base+3]
        }
        let colorSource = SCNGeometrySource(data:tints.withUnsafeBytes { Data($0) },semantic:.color,
            vectorCount:tints.count,usesFloatComponents:true,componentsPerVector:4,bytesPerComponent:4,dataOffset:0,dataStride:16)
        let geometry = SCNGeometry(sources:[SCNGeometrySource(vertices:vertices),SCNGeometrySource(textureCoordinates:uv),colorSource],
            elements:[SCNGeometryElement(data:indices.withUnsafeBytes { Data($0) },primitiveType:.triangles,primitiveCount:indices.count/3,bytesPerIndex:4)])
        let material = SCNMaterial(); material.lightingModel = .constant
        material.diffuse.contents = UIColor.white
        material.transparent.contents = GardenBodyAssets.glow
        material.transparencyMode = .aOne; material.isDoubleSided = true
        material.transparency = blend == .alpha ? 0.15 : 0.55
        material.blendMode = blend; material.writesToDepthBuffer = false; material.readsFromDepthBuffer = false
        geometry.firstMaterial = material
        let node = SCNNode(geometry:geometry); node.renderingOrder = blend == .alpha ? 1 : 2
        return node
    }
}
