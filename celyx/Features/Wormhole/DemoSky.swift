//  DemoSky.swift
//  DEBUG-only "demo sky": a fake Rigel fixed in the sensor world, so the WHOLE real collect flow
//  (aim → lock → sheet → Collect → validating → capture → wormhole) can be tried indoors.
//  The fake star only feeds the real StarCollectCameraView code paths; it is never saved.

#if DEBUG
import SwiftUI
import simd

enum DemoSky {
    /// Places the demo star ~22° to the side and a little up from where the phone points (sensor world, y up).
    static func direction(from forward: SIMD3<Float>) -> SIMD3<Float> {
        let yaw = simd_quatf(angle:22 * .pi/180,axis:SIMD3(0,1,0))
        var d = yaw.act(forward)
        let side = simd_normalize(simd_cross(d,SIMD3(0,1,0)))
        d = simd_quatf(angle:4 * .pi/180,axis:side).act(d)
        return simd_normalize(d)
    }

    static func star(in catalogue: [CatalogStar]) -> CatalogStar? {
        catalogue.first { $0.name == "Rigel" || $0.title == "Rigel" }
    }

    /// Paints the demo star into the frozen camera frame (so it is still there when the wormhole opens).
    static func composite(_ image: CGImage?,star point: CGPoint,viewSize: CGSize,color: SIMD3<Double>) -> CGImage? {
        guard let image, viewSize.width > 0 else { return image }
        let size = CGSize(width:image.width,height:image.height)
        let scale = size.width/viewSize.width
        let p = CGPoint(x:point.x*scale,y:point.y*(size.height/viewSize.height))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let rendered = UIGraphicsImageRenderer(size:size,format:format).image { context in
            UIImage(cgImage:image).draw(at:.zero)
            let cg = context.cgContext
            let tint = UIColor(red:color.x,green:color.y,blue:color.z,alpha:1)
            let colors = [UIColor.white.cgColor,tint.withAlphaComponent(0.55).cgColor,tint.withAlphaComponent(0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,0.18,1]) {
                cg.drawRadialGradient(gradient,startCenter:p,startRadius:0,endCenter:p,endRadius:16*scale,options:[])
            }
        }
        return rendered.cgImage
    }
}

/// A believable bright star over the live camera: soft core, glow, slight twinkle.
struct DemoStarView: View {
    let color: SIMD3<Double>
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let twinkle = 0.88+0.12*sin(t*7.3)*sin(t*3.1+1.2)
            let tint = Color(red:color.x,green:color.y,blue:color.z)
            ZStack {
                Circle().fill(RadialGradient(colors:[tint.opacity(0.55),tint.opacity(0)],center:.center,startRadius:0,endRadius:18))
                    .frame(width:36,height:36)
                Circle().fill(RadialGradient(colors:[.white,.white.opacity(0.6),.white.opacity(0)],center:.center,startRadius:0,endRadius:5))
                    .frame(width:10,height:10)
                Rectangle().fill(LinearGradient(colors:[.clear,.white.opacity(0.5),.clear],startPoint:.leading,endPoint:.trailing))
                    .frame(width:30,height:0.8)
                Rectangle().fill(LinearGradient(colors:[.clear,.white.opacity(0.5),.clear],startPoint:.top,endPoint:.bottom))
                    .frame(width:0.8,height:30)
            }
            .opacity(twinkle)
            .blendMode(.screen)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Small capsule shown while the demo sky is on.
struct DemoSkyPill: View {
    var body: some View {
        Label("Demo sky on",systemImage:"sparkles")
            .font(.system(size:12,weight:.semibold)).foregroundStyle(.white)
            .padding(.horizontal,10).padding(.vertical,6)
            .background(Capsule().fill(Color.purple.opacity(0.55)))
            .accessibilityLabel("Demo sky is on")
    }
}
#endif
