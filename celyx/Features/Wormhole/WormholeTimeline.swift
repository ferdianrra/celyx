//  WormholeTimeline.swift
//  The camera → Night Sea "wormhole handover", ported 1:1 from the approved web prototype.
//
//  Everything is a pure function of `tt` (milliseconds since the collect succeeded) and the screen size
//  in points, so the Metal pass, SwiftUI fades, sound and haptics all read the same clock.

import CoreGraphics
import Foundation

nonisolated enum WormholeTimeline {
    // MARK: Easing (same maths as the prototype)

    /// CSS-style cubic-bezier(x1,y1,x2,y2) as a function of x in 0…1 (Newton iterations on t).
    struct Bezier: Sendable {
        let ax, bx, cx, ay, by, cy: Double
        init(_ x1: Double,_ y1: Double,_ x2: Double,_ y2: Double) {
            cx = 3*x1; bx = 3*(x2-x1)-cx; ax = 1-cx-bx
            cy = 3*y1; by = 3*(y2-y1)-cy; ay = 1-cy-by
        }
        func callAsFunction(_ x: Double) -> Double {
            if x <= 0 { return 0 }
            if x >= 1 { return 1 }
            var t = x
            for _ in 0..<8 {
                let e = ((ax*t+bx)*t+cx)*t-x, d = (3*ax*t+2*bx)*t+cx
                if abs(e) < 1e-5 || abs(d) < 1e-6 { break }
                t -= e/d
            }
            t = min(1,max(0,t))
            return ((ay*t+by)*t+cy)*t
        }
    }
    static let flow = Bezier(0.65,0,0.15,1)
    static let out = Bezier(0.16,1,0.3,1)
    static let grow = Bezier(0.62,0,0.18,1)
    /// Landing / release easing.
    static let reframe = Bezier(0.42,0,0.12,1)

    static func clamp(_ x: Double,_ a: Double = 0,_ b: Double = 1) -> Double { min(b,max(a,x)) }
    static func seg(_ t: Double,_ a: Double,_ b: Double) -> Double { clamp((t-a)/(b-a)) }
    static func bump(_ x: Double) -> Double { sin(.pi*clamp(x)) }
    static func ss01(_ x: Double) -> Double { x*x*(3-2*x) }
    static func mix(_ a: Double,_ b: Double,_ t: Double) -> Double { a+(b-a)*t }

    static func impulse(_ t: Double,_ w: Double,_ z: Double) -> Double {
        guard t > 0 else { return 0 }
        let s = (1-z*z).squareRoot(), wd = w*s
        return exp(-z*w*t)*sin(wd*t)*exp(z*atan(s/z)/s)
    }
    static func spring(_ t: Double,_ w: Double,_ z: Double) -> Double {
        guard t > 0 else { return 0 }
        let wd = w*(1-z*z).squareRoot()
        return 1-exp(-z*w*t)*(cos(wd*t)+z*w/wd*sin(wd*t))
    }

    // MARK: Constants

    /// Pace of the run-up to landing: the prototype's keyframes (bend, pop, breathe, grow) play this much
    /// faster. Everything measured from T_LAND keeps real time, so the landing itself feels the same.
    static let pace: Double = 1.25
    /// Prototype time for a real elapsed time.
    static func proto(_ tt: Double) -> Double { tt*pace }

    /// Landing + 420 ms: the Night Sea takes over and the reframe starts.
    static let crossDelay: Double = 420
    /// Collected-object sheet springs in this long after the cross.
    static let sheetDelay: Double = 120
    /// From T_LAND the view eases onto the collected star (cubic-bezier .42,0,.12,1) over this long.
    static let landingDuration: Double = 900
    /// Field of view while resting on the star (kit convention), so some sea/horizon shows when it is low.
    static let landingFieldOfView: Double = 70
    /// Once the card is up, the star sits in the middle of the sky above it (fraction of screen height).
    static let sheetStarY: Double = 0.30
    /// Closing the card hands the view back to gyro/drag over this long.
    static let releaseDuration: Double = 600

    // MARK: Radius

    static func radius(_ tt: Double,diag: Double) -> Double {
        let sp = tt >= 820 ? spring(max(0,tt-820)/1000,17,0.38) : 0
        let breathe = out(seg(tt,1100,1750))+0.025*sin((tt-1100)/1000*5.2)*seg(tt,1100,1300)*(1-seg(tt,1650,1800))
        let dip = 0.07*bump(seg(tt,1700,1900)), g = grow(seg(tt,1820,2760))
        return (50*sp+12*breathe)*(1-dip)+(diag*1.45-62)*g
    }

    /// Centre of the hole: the star's screen point plus a small drifting offset (y scaled .8).
    static func center(_ tt: Double,star: CGPoint) -> CGPoint {
        let off = 7*(1-seg(tt,1700,2300)), angle = tt/1000*1.4
        return CGPoint(x:star.x+off*cos(angle),y:star.y+off*sin(angle)*0.8)
    }

    /// First tt (2 ms steps from 1820) where the hole covers the farthest screen corner + 4 pt.
    /// Every impact cue fires here (≈2176 ms on iPhone 15).
    static func landing(size: CGSize,star: CGPoint) -> Double {
        let diag = hypot(size.width,size.height)
        var tt = 1820.0
        while tt < 2760 {
            let c = center(tt,star:star)
            let far = [CGPoint.zero,CGPoint(x:size.width,y:0),CGPoint(x:0,y:size.height),CGPoint(x:size.width,y:size.height)]
                .map { hypot($0.x-c.x,$0.y-c.y) }.max() ?? diag
            if radius(tt,diag:diag) >= far+4 { return tt/pace }
            tt += 2
        }
        return 2760/pace
    }

    // MARK: The star going in

    /// The collected star as a light that the wormhole swallows: it swells as space bends toward it,
    /// sits glowing at the mouth while the hole breathes, then rushes up past the camera as the hole opens
    /// (we fly into it), thinning out just before landing. Size is a diameter in points.
    static func starLight(_ tt: Double,size: CGSize,radius R: Double) -> (size: Double, opacity: Double, flare: Double, spikes: Double) {
        let diag = hypot(size.width,size.height)
        let p = proto(tt)
        // One continuous approach, no plateau: drawn in with the bend, keeps creeping closer while the hole
        // breathes, then the opening hole carries it past the camera (size follows the hole, accelerating).
        let approach = ss01(seg(p,40,1500))                    // steady approach, no plateau
        let near = 18+90*approach
        let rushT = seg(p,1450,2250)                           // then it comes at us, accelerating
        let rush = near*(1+11*grow(rushT))
        let d = max(rush,R*1.6)
        let fadeIn = ss01(seg(p,0,90))                         // no pop over the real star in the photo
        let through = 1-ss01(seg(p,1800,2250))                 // dissolving as we pass through it (~360 ms)
        let flare = bump(seg(p,780,1050))                      // brief bloom at the pop
        let spikes = 1-ss01(seg(p,1550,1950))                  // spikes go first, then the glow
        return (d,fadeIn*through,flare,spikes)
    }

    // MARK: Frame

    /// Every animated value at one instant. `wh*` fields are the shader uniforms.
    struct Frame: Sendable {
        var crossAlpha = 1.0, cameraUI = 1.0, envUI = 0.0
        var pull = 0.0, jitter = 0.0, shake = 0.0
        var center = CGPoint.zero
        var R = 0.0, E = 0.0, W = 1.0
        var glow = 0.0, grain = 0.0, star = 0.0, expo = 1.0
        var swirl = 0.0, blur = 0.0
        var waveR = 0.0, waveA = 0.0, waveW = 22.0
    }

    /// `tt` and `TL` are real milliseconds; the run-up keyframes read prototype time `p` (see `pace`),
    /// anything measured from T_LAND reads real time.
    static func frame(_ tt: Double,size: CGSize,star: CGPoint,landing TL: Double) -> Frame {
        let diag = hypot(size.width,size.height)
        let p = proto(tt)
        var f = Frame()
        f.crossAlpha = 1-seg(p,0,180)
        f.cameraUI = 1-seg(p,0,260)
        let bend = flow(seg(p,120,850))
        let sp = p >= 820 ? spring(max(0,p-820)/1000,17,0.38) : 0
        let breathe = out(seg(p,1100,1750))+0.025*sin((p-1100)/1000*5.2)*seg(p,1100,1300)*(1-seg(p,1650,1800))
        let dip = 0.07*bump(seg(p,1700,1900)), g = grow(seg(p,1820,2760))
        let r0 = 50*sp+12*breathe
        let Rr = r0*(1-dip)+(diag*1.45-62)*g
        let dR = (diag*1.45-62)*(grow(seg(p+16*pace,1820,2760))-g)
        f.pull = -2.4*bend*(1-seg(p,820,950))
            +(p >= 820 ? spring(max(0,p-820)/1000,14,0.45)*2.4 : 0)-(p >= 820 ? 2.4 : 0)
            +(tt >= TL ? impulse((tt-TL)/1000,12,0.72)*2.8 : 0)
        f.waveR = p >= 820 ? Rr+(p-820)*0.75 : 0
        f.waveA = p >= 820 ? 16*exp(-(p-820)/380) : 0
        f.R = max(0,Rr)
        f.E = 20*bend*(1-seg(tt,820,900))+max(0,Rr)*1.18
        f.W = 1-ss01(seg(Rr,diag*0.3,diag*1.15))
        f.glow = min(1,bend*1.3)*(1-seg(tt,TL-100,TL+250))
        f.grain = 1-ss01(seg(tt,TL-80,TL+450))
        f.star = ss01(seg(tt,TL,TL+350))
        f.expo = 1+(tt >= TL ? 0.22*impulse((tt-TL)/1000,14,0.75) : 0)
        f.swirl = 0.9*bend*(1-seg(p,820,1000))+0.35*seg(p,900,1100)*(1-flow(seg(p,2100,2700)))+0.8*bump(seg(p,1800,2600))
        f.blur = min(28,max(0,dR*0.9))
        f.center = center(p,star:star)
        f.shake = tt >= TL ? impulse((tt-TL)/1000,11,0.74) : 0
        f.jitter = 0.55*(1-ss01(seg(tt,TL-250,TL+300)))
        f.envUI = ss01(seg(tt,TL+100,TL+500))
        return f
    }
}
