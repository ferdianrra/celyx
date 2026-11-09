// Builds the Night Sea's Milky Way map from NASA's "Deep Star Maps 2020" (Milky Way only, no point stars).
// Credit: NASA/Goddard Space Flight Center Scientific Visualization Studio (svs.gsfc.nasa.gov/4851).
//
//   curl -L -o /tmp/nasa/milkyway_2020_4k.exr https://svs.gsfc.nasa.gov/vis/a000000/a004800/a004851/milkyway_2020_4k.exr
//   swiftc -O scripts/make_nasa_milky_way.swift -o /tmp/nasamw && /tmp/nasamw /tmp/nasa/milkyway_2020_4k.exr
//
// Output: celyx/Resources/sky/garden-milky-way-nasa.jpg (4096x2048, equirect RA/Dec in the shader's convention
// u = RA/360, v = (90 - Dec)/180): the photo as is, levels set so the core never clips, stored so that the shader's
// m*m*1.15 is the light added to the sky. The app draws it at 85 % (NightSeaRenderer.milkyWayStrength).

import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

let W = 4096, H = 2048
let dir = "celyx/Resources/sky"
let exrPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/nasa/milkyway_2020_4k.exr"
let ctx = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])

func render(_ image: CIImage, _ w: Int, _ h: Int) -> [Float] {
    var out = [Float](repeating: 0, count: w * h * 4)
    out.withUnsafeMutableBytes { ctx.render(image, toBitmap: $0.baseAddress!, rowBytes: w * 16, bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBAf, colorSpace: nil) }
    return out
}
func image(from px: [Float], _ w: Int, _ h: Int) -> CIImage {
    CIImage(bitmapData: px.withUnsafeBytes { Data($0) }, bytesPerRow: w * 16, size: CGSize(width: w, height: h), format: .RGBAf, colorSpace: nil)
}
/// Gaussian blur of a single-channel map, wrapping across the RA seam.
func blur(_ y: [Float], sigma: Double) -> [Float] {
    var px = [Float](repeating: 0, count: W * H * 4)
    for i in 0..<(W * H) { px[i * 4] = y[i]; px[i * 4 + 3] = 1 }
    let base = image(from: px, W, H)
    let pad = CGFloat(ceil(sigma * 3.5))
    let wrapped = base.composited(over: base.transformed(by: .init(translationX: -CGFloat(W), y: 0))
        .composited(over: base.transformed(by: .init(translationX: CGFloat(W), y: 0))))
        .cropped(to: CGRect(x: -pad, y: 0, width: CGFloat(W) + 2 * pad, height: CGFloat(H))).clampedToExtent()
    let b = render(wrapped.applyingGaussianBlur(sigma: sigma), W, H)
    return (0..<(W * H)).map { b[$0 * 4] }
}

// --- load NASA EXR (linear HDR) ---
guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: exrPath) as CFURL, nil),
      let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("cannot read \(exrPath)") }
precondition(cg.width == W && cg.height == H, "expected 4096x2048, got \(cg.width)x\(cg.height)")
var nasa = render(CIImage(cgImage: cg, options: [.colorSpace: NSNull()]), W, H)

// --- orientation: correlate luminance with the Kit map (already in the shader's convention) ---
func lum(_ p: [Float], _ i: Int) -> Float { 0.2126 * p[i * 4] + 0.7152 * p[i * 4 + 1] + 0.0722 * p[i * 4 + 2] }
let sw = 512, sh = 256
func small(_ p: [Float], gamma: Bool) -> [Float] {
    var s = [Float](repeating: 0, count: sw * sh)
    for y in 0..<H { for x in 0..<W { var v = lum(p, y * W + x); if gamma { v = v * v }; s[(y / 8) * sw + x / 8] += v / 64 } }
    let m = s.reduce(0, +) / Float(s.count)
    return s.map { log(1 + 20 * $0 / m) }
}
let kitURL = URL(fileURLWithPath: "night-sea-environment-kit/data/milky-way-radec-4096.jpg")   // reference for RA alignment
let kitCG = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(kitURL as CFURL, nil)!, 0, nil)!
let kit = small(render(CIImage(cgImage: kitCG, options: [.colorSpace: NSNull()]), W, H), gamma: true)
let ns = small(nasa, gamma: false)
func corr(_ flip: Bool, _ shift: Int) -> Float {
    var sxy: Float = 0, sx: Float = 0, sy: Float = 0, sxx: Float = 0, syy: Float = 0
    for y in 0..<sh { for x in 0..<sw {
        var xs = flip ? sw - 1 - x : x; xs = (xs + shift) % sw
        let a = ns[y * sw + xs], b = kit[y * sw + x]
        sxy += a * b; sx += a; sy += b; sxx += a * a; syy += b * b } }
    let n = Float(sw * sh)
    return (sxy - sx * sy / n) / sqrt((sxx - sx * sx / n) * (syy - sy * sy / n))
}
var best = (flip: false, shift: 0, r: Float(-2))
for flip in [false, true] { for shift in 0..<sw { let r = corr(flip, shift); if r > best.r { best = (flip, shift, r) } } }
print(String(format: "orientation: flip=%@ shift=%d/512 (=%d px) r=%.3f", best.flip ? "yes" : "no", best.shift, best.shift * 8, best.r))
// apply
var aligned = [Float](repeating: 0, count: W * H * 4)
for y in 0..<H { for x in 0..<W {
    var xs = best.flip ? W - 1 - x : x; xs = (xs + best.shift * 8) % W
    for c in 0..<4 { aligned[(y * W + x) * 4 + c] = nasa[(y * W + xs) * 4 + c] } } }
nasa = aligned
// galactic centre check: RA 266.4, Dec -29 -> u .74, v .661
let gcx = Int(266.4 / 360 * Double(W)), gcy = Int((90 + 29.0) / 180 * Double(H))
var Y = (0..<(W * H)).map { max(0, lum(nasa, $0)) }
let sortedY = Y.sorted()
func pct(_ p: Double) -> Float { sortedY[min(sortedY.count - 1, Int(Double(sortedY.count) * p))] }
var gc: Float = 0; for dy in -20...20 { for dx in -20...20 { gc = max(gc, Y[(gcy + dy) * W + gcx + dx]) } }
print(String(format: "galactic centre lum %.3g vs median %.3g (x%.1f), p99.5 %.3g", gc, pct(0.5), gc / pct(0.5), pct(0.995)))

// --- normalise: p99.5 of luminance -> 1 ---
let norm = pct(0.995)
for i in 0..<(W * H * 4) where i % 4 != 3 { nasa[i] = max(0, nasa[i] / norm) }
Y = Y.map { $0 / norm }

func save(_ name: String, _ add: (Int) -> (Float, Float, Float)) {
    var rgba = [UInt8](repeating: 255, count: W * H * 4)
    for i in 0..<(W * H) {
        let a = add(i)
        // stored m with m*m*1.15 = added display light
        rgba[i * 4] = UInt8(min(255, sqrt(max(0, a.0) / 1.15) * 255 + 0.5))
        rgba[i * 4 + 1] = UInt8(min(255, sqrt(max(0, a.1) / 1.15) * 255 + 0.5))
        rgba[i * 4 + 2] = UInt8(min(255, sqrt(max(0, a.2) / 1.15) * 255 + 0.5))
    }
    let img = CGImage(width: W, height: H, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: W * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: CGDataProvider(data: Data(rgba) as CFData)!,
                      decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let url = URL(fileURLWithPath: "\(dir)/garden-milky-way-\(name).jpg")
    let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary); CGImageDestinationFinalize(d)
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    print(url.lastPathComponent, String(format: "%.2f MB", Double(size) / 1_048_576))
}

// --- NASA natural: the photo, soft knee so the core never clips ---
save("nasa") { i in   // the Milky Way used by the app
    func k(_ x: Float) -> Float { 0.42 * (1 - exp(-1.5 * x)) }
    return (k(nasa[i * 4]), k(nasa[i * 4 + 1]), k(nasa[i * 4 + 2]))
}
