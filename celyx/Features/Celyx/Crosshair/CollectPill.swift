import SwiftUI

/// "Collect Rigel" (Figma 1000:3473): a small green Liquid Glass pill under the locked crosshair label,
/// like the "Open in Safari" chip the iPhone camera shows under a QR code.
///
/// Gradient-border button: a soft radial light runs around the pill's 1.5pt rim, following the actual
/// capsule outline (straight edges and round ends) at an even pace, so it reads as light tracing the edge
/// rather than a spinning cone. A blurred copy of the light spills a faint glow outside the rim.
/// - Arrival: rises out of the label (6pt), scales from 0.82 and unblurs on a soft spring.
/// - Press: squashes slightly and brightens (CelyxTintedGlassButtonStyle).
/// - Reduce Motion: no travel; the rim holds a still, even light.
struct CollectPill: View {
    let title: String
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var start = Date()

    /// One lap of the light around the rim.
    private static let lap = 2.4
    private static let rim: CGFloat = 1.5

    var body: some View {
        Button(action:action) {
            Text(title).font(.system(size:15,weight:.medium)).lineLimit(1)
                .foregroundStyle(CelyxColor.primaryLabel)
                .padding(.horizontal,10).frame(height:28)
                .contentShape(Capsule())
        }
        .buttonStyle(CelyxTintedGlassButtonStyle(glow:.celyxCollect))
        .background { travellingLight.allowsHitTesting(false) }
        .environment(\.colorScheme,.dark)   // dark glass keeps the green deep and the label readable
        .scaleEffect(appeared ? 1 : 0.82,anchor:.top)
        .offset(y:appeared || reduceMotion ? 0 : -6)
        .blur(radius:appeared ? 0 : 6)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            start = .now
            // Rise on the crosshair's lock tap (190 ms in), and settle with its soft second tap.
            withAnimation((reduceMotion ? Animation.easeOut(duration:0.2) : .spring(duration:0.5,bounce:0.28)).delay(0.19)) { appeared = true }
        }
        .accessibilityLabel(title)
        .accessibilityHint("Captures this moment and adds the star to your sky")
        .accessibilityIdentifier("collect-pill")
    }

    /// The light sits just outside the glass: the pill covers all of it except the rim and the glow.
    private var travellingLight: some View {
        GeometryReader { geometry in
            let size = CGSize(width:geometry.size.width+Self.rim*2,height:geometry.size.height+Self.rim*2)
            TimelineView(.animation(paused:reduceMotion)) { context in
                let progress = reduceMotion ? 0 : context.date.timeIntervalSince(start)/Self.lap
                let head = Self.point(on:size,at:progress)
                let tail = Self.point(on:size,at:progress-0.5)
                let light = { (center: CGPoint,colors: [Color]) in
                    RadialGradient(colors:colors,center:UnitPoint(x:center.x/size.width,y:center.y/size.height),
                                   startRadius:0,endRadius:size.width*0.42)
                }
                ZStack {
                    Capsule().fill(Color(hex:0x30D158,opacity:reduceMotion ? 0.7 : 0.28))
                    Capsule().fill(light(head,[.white,Color(hex:0x5CFF8A),.clear]))
                    Capsule().fill(light(tail,[Color(hex:0x30D158,opacity:0.8),.clear]))
                }
                .overlay {
                    // Glow spilling outside the rim, carried by the head of the light.
                    Capsule().stroke(light(head,[Color(hex:0x7DFFA3),.clear]),lineWidth:4)
                        .blur(radius:6).opacity(0.8)
                }
                .frame(width:size.width,height:size.height)
                .offset(x:-Self.rim,y:-Self.rim)
                .blendMode(.plusLighter)
            }
        }
    }

    /// A point on a capsule's outline at `progress` laps (clockwise from the top-left of the straight edge),
    /// spaced evenly by arc length.
    private static func point(on size: CGSize,at progress: Double) -> CGPoint {
        let r = size.height/2
        let straight = max(0,size.width-size.height)
        let arc = CGFloat.pi*r
        let perimeter = 2*straight+2*arc
        var d = CGFloat(progress-floor(progress))*perimeter
        if d < straight { return CGPoint(x:r+d,y:0) }
        d -= straight
        if d < arc { let a = -CGFloat.pi/2+d/r; return CGPoint(x:r+straight+r*cos(a),y:r+r*sin(a)) }
        d -= arc
        if d < straight { return CGPoint(x:r+straight-d,y:size.height) }
        d -= straight
        let a = CGFloat.pi/2+d/r
        return CGPoint(x:r+r*cos(a),y:r+r*sin(a))
    }
}

#Preview("Collect pill") {
    VStack(spacing:8) {
        Text("Rigel").font(.system(size:15)).foregroundStyle(.white)
        CollectPill(title:"Collect Rigel") {}
    }
    .frame(maxWidth:.infinity,maxHeight:.infinity)
    .background(Color(hex:0x0B1026))
    .preferredColorScheme(.dark)
}
