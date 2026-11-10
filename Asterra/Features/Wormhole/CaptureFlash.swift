//  CaptureFlash.swift
//  The "cekrek" capture cue before the wormhole: the frame freezes at the click and over-exposes like a
//  real shutter firing. Shared by the real collect and the debug demo. ~400 ms total; the wormhole opens at 350 ms.

import SwiftUI

enum CaptureFlash {
    /// The wormhole starts this long after the shutter.
    static let handoverDelay: Double = 350
    /// Everything has settled by then.
    static let duration: Double = 400

    private static func easeOut(_ x: Double) -> Double { let u = min(1,max(0,x)); return 1-pow(1-u,3) }

    /// Exposure lift 0…1 (1 = +1.5 stops): peaks at 50 ms, eases out over 330 ms.
    static func exposure(_ t: Double) -> Double {
        if t < 0 { return 0 }
        if t < 50 { return easeOut(t/50) }
        return 1-easeOut((t-50)/330)
    }
    /// White overlay: 0 → .65 in 40 ms, hold 60 ms, ease out to 0 over 280 ms.
    static func white(_ t: Double) -> Double {
        if t < 0 { return 0 }
        if t < 40 { return 0.65*t/40 }
        if t < 100 { return 0.65 }
        return 0.65*(1-easeOut((t-100)/280))
    }
    /// Vignette pulse 0…1 (edges darken up to 15 % and release).
    static func vignette(_ t: Double) -> Double { t < 0 || t > 300 ? 0 : sin(.pi*t/300) }
    /// Shutter squeeze 1 → 0.98 → 1 over 300 ms.
    static func squeeze(_ t: Double) -> Double { t < 0 || t > 300 ? 1 : 1-0.02*sin(.pi*t/300) }
}

/// The frozen frame, over-exposed (+1.5 stops at the peak) with a slight bloom, a vignette pulse and a 1.5 %
/// chromatic split toward the edges. `t` = ms since the shutter.
struct CaptureFlashView: View {
    let image: CGImage?
    let t: Double

    var body: some View {
        let e = CaptureFlash.exposure(t), v = CaptureFlash.vignette(t)
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                if let image {
                    let frame = Image(decorative:image,scale:1).resizable().scaledToFill()
                        .frame(width:size.width,height:size.height).clipped()
                    frame
                    // +1.5 stops ≈ ×2.83: add the frame onto itself (two layers of up to +0.915 each).
                    frame.blendMode(.plusLighter).opacity(min(1,1.83*e))
                    frame.blendMode(.plusLighter).opacity(max(0,1.83*e-1))
                    // Bloom.
                    frame.blur(radius:14).blendMode(.plusLighter).opacity(0.45*e)
                    // Chromatic split at the edges (red pushed out, blue pulled in), only near the peak.
                    ZStack {
                        frame.colorMultiply(.red).scaleEffect(1.015)
                        frame.colorMultiply(.blue).scaleEffect(0.985)
                    }
                    .blendMode(.screen).opacity(0.35*e)
                    .mask(RadialGradient(colors:[.clear,.clear,.white],center:.center,startRadius:0,endRadius:max(size.width,size.height)*0.62))
                } else {
                    CelyxColor.night
                }
                RadialGradient(colors:[.clear,.black.opacity(0.15*v)],center:.center,
                               startRadius:min(size.width,size.height)*0.35,endRadius:max(size.width,size.height)*0.7)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
