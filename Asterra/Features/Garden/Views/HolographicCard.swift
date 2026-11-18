import SwiftUI
import CoreMotion

/// Tilt for the collected-star card, in -1...1 on each axis (+x: right edge away, +y: bottom edge away).
///
/// Motion, done like a physical object rather than a value that jumps:
/// - Inputs only set a *target*: the finger (where it presses), else the gyro (how far the phone is
///   tipped from however it is being held; that rest pose drifts along over ~4 s).
/// - Inputs pass through a soft response curve (tanh), so small moves read clearly and big ones ease
///   into the limit instead of hitting a wall.
/// - The card follows the target with a damped spring integrated every frame (ζ ≈ 0.8: settles with a
///   whisper of overshoot, no wobble). Press, release, and phone movement all get the same easing.
@Observable @MainActor
final class CardTilt {
    /// Largest lean, in degrees.
    static let maxAngle = 10.0
    /// Finger on the card, in -1...1 from its centre. While set it leads and the gyro adds a little.
    var touch: CGPoint?
    private(set) var x: Double = 0
    private(set) var y: Double = 0
    @ObservationIgnored private var vx = 0.0
    @ObservationIgnored private var vy = 0.0
    @ObservationIgnored private var gx = 0.0
    @ObservationIgnored private var gy = 0.0
    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var restRoll: Double?
    @ObservationIgnored private var restPitch = 0.0
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var proxy: LinkProxy?
    @ObservationIgnored private var last: CFTimeInterval = 0

    /// Spring stiffness (1/s²) and damping, ζ = damping / (2√stiffness) ≈ 0.8.
    private static let stiffness = 110.0
    private static let damping = 2*0.8*sqrt(110.0)
    /// Phone tilt (radians from rest) that gives about 76% lean (tanh 1).
    private static let gyroRange = 0.30

    func start() {
        guard link == nil else { return }
        let proxy = LinkProxy { [weak self] link in self?.step(link) }
        let link = CADisplayLink(target:proxy,selector:#selector(LinkProxy.tick(_:)))
        link.add(to:.main,forMode:.common)
        self.proxy = proxy; self.link = link; last = 0
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1/60
        manager.startDeviceMotionUpdates(to:.main) { [weak self] motion,_ in
            guard let self, let motion else { return }
            let roll = motion.attitude.roll, pitch = motion.attitude.pitch
            if restRoll == nil { restRoll = roll; restPitch = pitch }
            restRoll! += (roll-restRoll!)*0.004
            restPitch += (pitch-restPitch)*0.004
            gx = tanh((roll-restRoll!)/Self.gyroRange)
            gy = -tanh((pitch-restPitch)/Self.gyroRange)
        }
    }
    func stop() {
        manager.stopDeviceMotionUpdates()
        link?.invalidate(); link = nil; proxy = nil
        restRoll = nil; gx = 0; gy = 0; x = 0; y = 0; vx = 0; vy = 0
    }

    private func step(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = last == 0 ? 1.0/60 : min(1.0/30,now-last)
        last = now
        let tx: Double, ty: Double
        if let touch {
            // A finger on the card: a soft curve so the middle of the card is calm and the edges lean most.
            tx = tanh(Double(touch.x)*1.3)/tanh(1.3)*0.85+gx*0.25
            ty = tanh(Double(touch.y)*1.3)/tanh(1.3)*0.85+gy*0.25
        } else {
            tx = gx; ty = gy
        }
        // Semi-implicit Euler, split into small substeps so the spring stays stable at any frame rate.
        let steps = 4, h = dt/Double(steps)
        for _ in 0..<steps {
            vx += (Self.stiffness*(tx-x)-Self.damping*vx)*h; x += vx*h
            vy += (Self.stiffness*(ty-y)-Self.damping*vy)*h; y += vy*h
        }
    }
}

private final class LinkProxy: NSObject {
    let onTick: (CADisplayLink) -> Void
    init(_ onTick: @escaping (CADisplayLink) -> Void) { self.onTick = onTick }
    @objc func tick(_ link: CADisplayLink) { MainActor.assumeIsolated { onTick(link) } }
}

/// Slowly morphing card gradient: the Figma palette (navy floor, 0066E2 blue, 7459DF violet, lavender)
/// on a mesh whose inner points drift on long, out-of-phase loops, so it never visibly repeats.
struct MorphingCardGradient: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval:1/30,paused:reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let s = { (period: Double,phase: Double) in Float(sin(t*2 * .pi/period+phase)) }
            MeshGradient(width:3,height:4,points:[
                [0,0],[0.5+0.12*s(17,0),0],[1,0],
                [0,0.3+0.06*s(13,1)],[0.5+0.18*s(19,2),0.32+0.08*s(11,3)],[1,0.3+0.06*s(15,4)],
                [0,0.68+0.06*s(14,5)],[0.5+0.16*s(21,6),0.66+0.08*s(12,7)],[1,0.7+0.06*s(16,8)],
                [0,1],[0.5+0.14*s(18,9),1],[1,1]
            ],colors:[
                Color(hex:0x8A7CF0),Color(hex:0x5C5FE0),Color(hex:0x8A7CF0),
                Color(hex:0x1F4FD0),Color(hex:0x0B1A4A),Color(hex:0x2A3FCF),
                Color(hex:0x3A3FC8),Color(hex:0x090C1C),Color(hex:0x4A42C9),
                Color(hex:0x6E66E8),Color(hex:0x2A2F9C),Color(hex:0x8FA0FF)
            ],smoothsColors:true)
        }
        .accessibilityHidden(true)
    }
}

/// Holographic foil: a rainbow band that slides across the card as it tilts (Framer "holographic 3D card").
struct HoloFoil: View {
    let tilt: CardTilt
    var body: some View {
        GeometryReader { geometry in
            let shift = CGFloat(tilt.x*0.6+tilt.y*0.4)
            LinearGradient(stops:[
                .init(color:.clear,location:0.0),
                .init(color:Color(hex:0x5CE1FF),location:0.30),
                .init(color:Color(hex:0xB78CFF),location:0.42),
                .init(color:Color(hex:0xFF8AD8),location:0.52),
                .init(color:Color(hex:0x9DFFB5),location:0.62),
                .init(color:.clear,location:0.8)
            ],startPoint:UnitPoint(x:-0.6+shift,y:-0.2),endPoint:UnitPoint(x:1.0+shift,y:1.2))
            .frame(width:geometry.size.width,height:geometry.size.height)
            .blendMode(.overlay)
            .opacity(0.22+0.28*min(1,abs(Double(shift))))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Specular glare that follows the light as the card tips.
struct HoloGlare: View {
    let tilt: CardTilt
    var body: some View {
        RadialGradient(colors:[.white.opacity(0.22),.white.opacity(0.06),.clear],
                       center:UnitPoint(x:0.5-tilt.x*0.6,y:0.3-tilt.y*0.6),startRadius:0,endRadius:320)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Where the card's light lands in the sky: a quick flash and a thin ring opening out, with a soft tap.
struct LandingBloom: View {
    @State private var open = false
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors:[.white,Color(hex:0xB9C6FF,opacity:0.6),.clear],center:.center,startRadius:0,endRadius:22))
                .frame(width:44,height:44)
                .scaleEffect(open ? 1.4 : 0.5)
                .opacity(open ? 0 : 1)
            Circle().stroke(.white.opacity(0.8),lineWidth:1.2)
                .frame(width:40,height:40)
                .scaleEffect(open ? 2.2 : 0.2)
                .opacity(open ? 0 : 0.9)
        }
        .blendMode(.plusLighter)
        .onAppear { withAnimation(.easeOut(duration:0.9)) { open = true } }
        .sensoryFeedback(.impact(flexibility:.soft,intensity:0.8),trigger:open) { _,isOpen in isOpen }
        .accessibilityHidden(true)
    }
}
