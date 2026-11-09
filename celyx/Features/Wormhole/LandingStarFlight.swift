//  LandingStarFlight.swift
//  After T_LAND the collected star flies to its real place in the Night Sea and settles there.

import SwiftUI

/// The collected star arriving in the virtual sky. It comes in from just past the camera (bottom of the
/// screen, large and soft), sweeps up on a curve that bends toward its place, slows into it while it shrinks
/// to a point of light, and settles with a small bloom; the Night Sea's own star lights up under it.
/// Drawn in the wormhole view and in the garden (same clock), so it continues across the hand-off.
struct LandingStarFlight: View {
    let handover: WormholeHandover

    var body: some View {
        let TL = handover.landing
        let object = handover.scene.objects.first { $0.id == handover.scene.newID }
        let tint = object.map { Color(red:$0.color.x,green:$0.color.y,blue:$0.color.z) } ?? Color(hex:0xCFE0FF)
        TimelineView(.animation(paused:handover.phase >= .releasing)) { _ in
            let tt = handover.tt()
            let raw = WormholeTimeline.seg(tt,TL+WormholeTimeline.flyStart,TL+WormholeTimeline.flyEnd)
            let settle = WormholeTimeline.seg(tt,TL+WormholeTimeline.flyEnd-40,TL+WormholeTimeline.flyEnd+560)
            if tt > TL+WormholeTimeline.flyStart, settle < 1, let target = targetPoint(tt) {
                let size = handover.freeze.size
                // Ease: leaves quickly, glides into place (no overshoot on position).
                let e = WormholeTimeline.out(raw)
                let start = CGPoint(x:size.width*0.5+(target.x-size.width*0.5)*0.35+size.width*0.14,
                                    y:size.height*1.08)
                let control = CGPoint(x:WormholeTimeline.mix(start.x,target.x,0.1),
                                      y:WormholeTimeline.mix(start.y,target.y,0.85))
                let point = Self.bezier(start,control,target,e)
                let diameter = WormholeTimeline.mix(54,10,WormholeTimeline.ss01(raw))
                let blur = 6*(1-WormholeTimeline.ss01(raw))
                let fadeIn = WormholeTimeline.ss01(WormholeTimeline.seg(tt,TL+WormholeTimeline.flyStart,TL+WormholeTimeline.flyStart+160))
                let handOff = 1-WormholeTimeline.ss01(WormholeTimeline.seg(settle,0.15,1))
                ZStack {
                    // Trail: a short streak along the direction of travel, gone by arrival.
                    if raw < 0.92 {
                        let ahead = Self.bezier(start,control,target,min(1,e+0.06))
                        let angle = atan2(ahead.y-point.y,ahead.x-point.x)
                        Capsule()
                            .fill(LinearGradient(colors:[tint.opacity(0),tint.opacity(0.55),.white.opacity(0.8)],
                                                 startPoint:.leading,endPoint:.trailing))
                            .frame(width:diameter*2.4*(1-raw),height:max(1.5,diameter*0.12))
                            .offset(x:-diameter*1.2*(1-raw))
                            .rotationEffect(.radians(angle))
                            .blur(radius:3)
                            .opacity(1-WormholeTimeline.ss01(raw/0.92))
                    }
                    Circle()
                        .fill(RadialGradient(colors:[tint.opacity(0.6),tint.opacity(0.12),.clear],center:.center,
                                             startRadius:0,endRadius:diameter*1.2))
                        .frame(width:diameter*2.4,height:diameter*2.4)
                    Circle()
                        .fill(RadialGradient(colors:[.white,.white.opacity(0.85),tint.opacity(0)],center:.center,
                                             startRadius:0,endRadius:diameter*0.5))
                        .frame(width:diameter,height:diameter)
                        .blur(radius:blur)
                    // Settling: a thin ring opens and a soft flash as it takes its place.
                    Circle().stroke(.white.opacity(0.7),lineWidth:1)
                        .frame(width:16,height:16)
                        .scaleEffect(0.6+2.4*WormholeTimeline.out(settle))
                        .opacity(settle > 0 ? 0.8*(1-settle) : 0)
                }
                .blendMode(.plusLighter)
                .opacity(fadeIn*handOff)
                .position(point)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Where the star sits on screen right now, through the handover's own camera.
    private func targetPoint(_ tt: Double) -> CGPoint? {
        handover.camera(tt).project(handover.starDirection,in:handover.freeze.size)
    }

    static func bezier(_ a: CGPoint,_ b: CGPoint,_ c: CGPoint,_ t: Double) -> CGPoint {
        let u = 1-t
        return CGPoint(x:u*u*a.x+2*u*t*b.x+t*t*c.x,y:u*u*a.y+2*u*t*b.y+t*t*c.y)
    }
}
