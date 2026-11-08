// Pre-processes the Night Sea kit's Milky Way map into three softened versions (the shader just samples them).
//
//   swiftc -O scripts/make_soft_milky_way.swift -o /tmp/softmw && /tmp/softmw
//
// Input:  celyx/Resources/sky/garden-milky-way-radec.jpg (4096x2048, equirectangular RA/Dec, gamma-encoded)
// Output: celyx/Resources/sky/garden-milky-way-radec-soft{1,2,3}.jpg, same size.
//
// All maths on the values as stored (gamma-encoded 0..1; the shader squares them later). No colour management.
// B(s) = Gaussian blur, sigma s px at 4096 wide, wrapping horizontally across the RA seam (padded, then cropped);
// L = luminance (.2126, .7152, .0722); sat(a,k) = L + (a-L)k; filmic(a,e) = (1 - exp(-a e)) / (1 - exp(-e));
// core blend X: w = X * clamp(2L, 0, 1); a = a(1-w) + (1, .88, .88) L w   (warm pale pink-beige, not white-hot)
// lavender tint T: a = mix(a, L * (.92, .82, 1.0), T)   (mauve / dusty lavender like the user's reference)
//   Soft 1 (light):    a = .75 B(2) + .25 B(24); sat .7;  magenta calmed; core 25 %; tint .30; filmic 1.3 x .92
//   Soft 2 (lavender): a = .45 B(3) + .55 B(30); sat .45; core 35 %; tint .50; filmic 1.4 x .85  (closest to the reference)
//   Soft 3 (dreamy):   a = .30 B(6) + .70 B(30); sat .55; core 20 %; tint .50; filmic 1.6 x .78

import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

let dir = "celyx/Resources/sky"
let input = URL(fileURLWithPath: "\(dir)/garden-milky-way-radec.jpg")
guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("cannot read \(input.path)") }
let W = cg.width, H = cg.height
let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
let base = CIImage(cgImage: cg, options: [.colorSpace: NSNull()])

/// Gaussian blur that wraps across the left/right (RA) seam and clamps at the poles. Returns RGBA float pixels.
func blur(_ sigma: Double) -> [Float] {
    let pad = CGFloat(ceil(sigma * 4))
    let left = base.transformed(by: CGAffineTransform(translationX: -CGFloat(W), y: 0))
    let right = base.transformed(by: CGAffineTransform(translationX: CGFloat(W), y: 0))
    let wrapped = base.composited(over: left.composited(over: right))
        .cropped(to: CGRect(x: -pad, y: 0, width: CGFloat(W) + 2 * pad, height: CGFloat(H)))
        .clampedToExtent()
    let blurred = sigma > 0 ? wrapped.applyingGaussianBlur(sigma: sigma) : wrapped
    var out = [Float](repeating: 0, count: W * H * 4)
    out.withUnsafeMutableBytes { buffer in
        context.render(blurred, toBitmap: buffer.baseAddress!, rowBytes: W * 16,
                       bounds: CGRect(x: 0, y: 0, width: W, height: H), format: .RGBAf, colorSpace: nil)
    }
    return out
}

struct Recipe { let name: String; let s1: Double; let w1: Float; let s2: Double; let sat: Float; let cream: Float; let tint: Float; let e: Float; let gain: Float; let magenta: Float }
let recipes = [
    Recipe(name: "soft1", s1: 2, w1: 0.75, s2: 24, sat: 0.70, cream: 0.25, tint: 0.30, e: 1.3, gain: 0.92, magenta: 0.5),
    Recipe(name: "soft2", s1: 3, w1: 0.45, s2: 30, sat: 0.45, cream: 0.35, tint: 0.50, e: 1.4, gain: 0.85, magenta: 0.3),
    Recipe(name: "soft3", s1: 6, w1: 0.30, s2: 30, sat: 0.55, cream: 0.20, tint: 0.50, e: 1.6, gain: 0.78, magenta: 0.3),
]

var cache: [Double: [Float]] = [:]
func blurred(_ s: Double) -> [Float] { if let b = cache[s] { return b }; let b = blur(s); cache[s] = b; return b }

for r in recipes {
    let a1 = blurred(r.s1), a2 = blurred(r.s2)
    var rgba = [UInt8](repeating: 255, count: W * H * 4)
    let cream: (Float, Float, Float) = (1, 0.88, 0.88)        // warm pale pink-beige core
    let norm = 1 - exp(-r.e)
    for i in 0..<(W * H) {
        let k = i * 4
        var c = (r.w1 * a1[k] + (1 - r.w1) * a2[k], r.w1 * a1[k + 1] + (1 - r.w1) * a2[k + 1], r.w1 * a1[k + 2] + (1 - r.w1) * a2[k + 2])
        var L = 0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2
        c = (L + (c.0 - L) * r.sat, L + (c.1 - L) * r.sat, L + (c.2 - L) * r.sat)
        if r.magenta > 0 {          // pull magenta/pink patches further toward grey
            let m = max(0, min(c.0, c.2) - c.1) * 4
            let t = min(1, m) * r.magenta
            c = (c.0 + (L - c.0) * t, c.1 + (L - c.1) * t, c.2 + (L - c.2) * t)
        }
        if r.cream > 0 {
            L = 0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2
            let w = r.cream * min(1, max(0, L * 2))
            c = (c.0 * (1 - w) + cream.0 * L * w, c.1 * (1 - w) + cream.1 * L * w, c.2 * (1 - w) + cream.2 * L * w)
        }
        if r.tint > 0 {             // dusty lavender / mauve
            L = 0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2
            c = (c.0 + (L * 0.92 - c.0) * r.tint, c.1 + (L * 0.82 - c.1) * r.tint, c.2 + (L * 1.0 - c.2) * r.tint)
        }
        func filmic(_ x: Float) -> Float { (1 - exp(-max(0, x) * r.e)) / norm * r.gain }
        rgba[k] = UInt8(max(0, min(255, filmic(c.0) * 255 + 0.5)))
        rgba[k + 1] = UInt8(max(0, min(255, filmic(c.1) * 255 + 0.5)))
        rgba[k + 2] = UInt8(max(0, min(255, filmic(c.2) * 255 + 0.5)))
    }
    let provider = CGDataProvider(data: Data(rgba) as CFData)!
    let image = CGImage(width: W, height: H, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: W * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let url = URL(fileURLWithPath: "\(dir)/garden-milky-way-radec-\(r.name).jpg")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    CGImageDestinationFinalize(dest)
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    print(url.lastPathComponent, W, "x", H, String(format: "%.2f MB", Double(size) / 1_048_576))
}
