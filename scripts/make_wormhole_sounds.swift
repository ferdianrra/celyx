// Generates the wormhole handover cues into Asterra/Features/Wormhole/Sounds/.
//
//   swiftc -O scripts/make_wormhole_sounds.swift -o /tmp/make_wormhole_sounds && /tmp/make_wormhole_sounds
//
// Cinematic, trailer-style, NOT musical: no clean sine tones above ~250 Hz and no two notes forming an interval.
// 44.1 kHz stereo. Shared send: convolution reverb with a generated 4.2 s IR (white noise · (1−t)^3.4, 12 ms
// fade-in, lowpassed 4.8 kHz, decorrelated L/R), wet gain .6; master gain .85 into a soft compressor
// (−16 dB, 3.5:1). Reverb tails are rendered into each file. All files share one normalisation so the boom
// peaks at −1 dBFS and the others keep their relative levels.
//
// Timeline (iPhone 15, T_LAND ≈ 2172 ms): impact @0, bend @120 → T_LAND, pop @820, swell cut lands on T_LAND
// (the app starts it `swellCut` seconds early), boom @T_LAND, sheet swish @T_LAND+540.

import Accelerate
import Foundation

let sr = 44100.0
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Asterra/Features/Wormhole/Sounds"
let bendLength = 2.052     // T_LAND − 120 ms
let swellCut = 0.476       // 1700 ms → T_LAND: the hard stop ends exactly here

// MARK: Sources

struct Noise {
    var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func white() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53) * 2 - 1
    }
    var brownState = 0.0
    mutating func brown() -> Double { brownState = brownState * 0.997 + white() * 0.06; return brownState }
}

/// RBJ biquad with per-sample cutoff.
struct Biquad {
    enum Kind { case lowpass, highpass, bandpass }
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
    mutating func run(_ kind: Kind, _ x: Double, _ hz: Double, _ q: Double) -> Double {
        let w = 2 * .pi * min(max(hz, 10), sr * 0.45) / sr, cw = cos(w), alpha = sin(w) / (2 * q), a0 = 1 + alpha
        let b0, b1, b2: Double
        switch kind {
        case .lowpass: b0 = (1 - cw) / 2; b1 = 1 - cw; b2 = (1 - cw) / 2
        case .highpass: b0 = (1 + cw) / 2; b1 = -(1 + cw); b2 = (1 + cw) / 2
        case .bandpass: b0 = alpha; b1 = 0; b2 = -alpha
        }
        let y = (b0 * x + b1 * x1 + b2 * x2 - (-2 * cw) * y1 - (1 - alpha) * y2) / a0
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }
}

/// Exponential glide from a to b over `dur` seconds, then hold.
func glide(_ a: Double, _ b: Double, _ t: Double, _ dur: Double) -> Double { a * pow(b / a, min(1, max(0, t / dur))) }

// MARK: Envelopes

/// 8 ms exponential attack, then exponential decay to silence at `dur`.
func hit(_ t: Double, _ dur: Double) -> Double {
    if t < 0 || t >= dur { return 0 }
    let attack = 0.008
    if t < attack { return (1 - exp(-5 * t / attack)) / (1 - exp(-5)) }
    let k = log(1000) / (dur - attack)
    return exp(-k * (t - attack)) * (1 - (t - attack) / (dur - attack) * 0.001)
}
/// Exponential rise to peak at 55 %, then hold.
func pad(_ t: Double, _ dur: Double) -> Double {
    if t < 0 || t >= dur { return 0 }
    let x = t / (dur * 0.55)
    return x >= 1 ? 1 : (exp(4 * x) - 1) / (exp(4) - 1)
}
/// Exponential rise, then a 30 ms linear cut ending exactly at `dur`.
func swellEnv(_ t: Double, _ dur: Double) -> Double {
    if t < 0 || t >= dur { return 0 }
    let rise = (exp(5 * t / dur) - 1) / (exp(5) - 1)
    let cut = 0.030
    return t > dur - cut ? rise * (dur - t) / cut : rise
}

// MARK: Mixing

/// One layer: a mono signal (normalised to peak 1 before `peak`), its reverb send.
struct Layer { var samples: [Double]; var peak: Double; var wet: Double }

func layer(_ dur: Double, peak: Double, wet: Double, normalize: Bool = true, _ f: (Double) -> Double, env: (Double) -> Double) -> Layer {
    var raw = (0..<Int(dur * sr)).map { f(Double($0) / sr) }
    if normalize { let m = raw.map(abs).max() ?? 1; if m > 0 { raw = raw.map { $0 / m } } }
    return Layer(samples: raw.enumerated().map { $1 * env(Double($0) / sr) }, peak: peak, wet: wet)
}

func fftConvolve(_ a: [Float], _ b: [Float]) -> [Float] {
    let outCount = a.count + b.count - 1
    var log2n = 1; while (1 << log2n) < outCount { log2n += 1 }
    let n = 1 << log2n, half = n / 2
    guard let setup = vDSP_create_fftsetup(vDSP_Length(log2n), FFTRadix(kFFTRadix2)) else { fatalError("fft") }
    defer { vDSP_destroy_fftsetup(setup) }
    func spectrum(_ x: [Float]) -> ([Float], [Float]) {
        var padded = x + [Float](repeating: 0, count: n - x.count)
        var re = [Float](repeating: 0, count: half), im = [Float](repeating: 0, count: half)
        re.withUnsafeMutableBufferPointer { r in im.withUnsafeMutableBufferPointer { i in
            var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
            padded.withUnsafeMutableBytes { p in
                vDSP_ctoz(p.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(half))
            }
            vDSP_fft_zrip(setup, &split, 1, vDSP_Length(log2n), FFTDirection(FFT_FORWARD))
        } }
        return (re, im)
    }
    let (ar, ai) = spectrum(a), (br, bi) = spectrum(b)
    var re = [Float](repeating: 0, count: half), im = [Float](repeating: 0, count: half)
    re[0] = ar[0] * br[0]; im[0] = ai[0] * bi[0]                     // DC and Nyquist are packed in bin 0
    for k in 1..<half {
        re[k] = ar[k] * br[k] - ai[k] * bi[k]
        im[k] = ar[k] * bi[k] + ai[k] * br[k]
    }
    var out = [Float](repeating: 0, count: n)
    re.withUnsafeMutableBufferPointer { r in im.withUnsafeMutableBufferPointer { i in
        var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
        vDSP_fft_zrip(setup, &split, 1, vDSP_Length(log2n), FFTDirection(FFT_INVERSE))
        out.withUnsafeMutableBytes { p in
            vDSP_ztoc(&split, 1, p.bindMemory(to: DSPComplex.self).baseAddress!, 2, vDSP_Length(half))
        }
    } }
    let scale = 1 / Float(4 * n)
    return Array(out[0..<outCount]).map { $0 * scale }
}

/// 4.2 s IR: white noise · (1−t)^3.4, 12 ms fade-in, lowpassed 4.8 kHz, unit energy.
func impulseResponse(seed: UInt64) -> [Float] {
    var noise = Noise(seed), lp = Biquad(), lp2 = Biquad()
    let len = 4.2, count = Int(len * sr)
    var ir = (0..<count).map { i -> Double in
        let t = Double(i) / sr
        let fadeIn = min(1, t / 0.012)
        let x = noise.white() * pow(1 - t / len, 3.4) * fadeIn
        return lp2.run(.lowpass, lp.run(.lowpass, x, 4800, 0.707), 4800, 0.707)
    }
    let energy = sqrt(ir.reduce(0) { $0 + $1 * $1 })
    ir = ir.map { $0 / energy }
    return ir.map(Float.init)
}
let irL = impulseResponse(seed: 0xA11CE), irR = impulseResponse(seed: 0xB0B5EED)

/// Sum layers, add the shared reverb send, master gain + soft compressor. Returns stereo.
func mix(_ layers: [Layer]) -> ([Double], [Double]) {
    let length = layers.map(\.samples.count).max() ?? 0
    var dry = [Double](repeating: 0, count: length), send = [Float](repeating: 0, count: length)
    for l in layers {
        for (i, s) in l.samples.enumerated() {
            dry[i] += s * l.peak * (1 - 0.7 * l.wet)    // "mostly wet" layers are quieter dry
            send[i] += Float(s * l.peak * l.wet)
        }
    }
    let wetL = fftConvolve(send, irL), wetR = fftConvolve(send, irR)
    let total = wetL.count
    var left = [Double](repeating: 0, count: total), right = left
    for i in 0..<total {
        let d = i < length ? dry[i] : 0
        left[i] = 0.85 * (d + 0.6 * Double(wetL[i]))
        right[i] = 0.85 * (d + 0.6 * Double(wetR[i]))
    }
    // Soft compressor: threshold −16 dBFS, ratio 3.5, 3 ms attack, 150 ms release.
    let threshold = -16.0, ratio = 3.5, att = exp(-1 / (0.003 * sr)), rel = exp(-1 / (0.150 * sr))
    var env = 0.0
    for i in 0..<total {
        let level = max(abs(left[i]), abs(right[i]))
        env = level > env ? att * env + (1 - att) * level : rel * env + (1 - rel) * level
        let db = 20 * log10(max(env, 1e-9))
        let gain = db > threshold ? pow(10, (threshold - db) * (1 - 1 / ratio) / 20) : 1
        left[i] *= gain; right[i] *= gain
    }
    // Trim the silent end of the tail.
    var end = total
    while end > 1 && max(abs(left[end - 1]), abs(right[end - 1])) < 3e-5 { end -= 1 }
    let fadeOut = min(Int(0.05 * sr), end)
    for k in 0..<fadeOut { let g = Double(k) / Double(fadeOut); left[end - 1 - k] *= g; right[end - 1 - k] *= g }
    return (Array(left[0..<end]), Array(right[0..<end]))
}

// MARK: Cues

/// t0 "impact": sub sweep 140→58 Hz + a tiny bandpassed air tick. No chime.
func impact() -> ([Double], [Double]) {
    var phase = 0.0, n = Noise(11), bp = Biquad()
    return mix([
        layer(0.6, peak: 0.32, wet: 0.2, { t in phase += 2 * .pi * glide(140, 58, t, 0.2) / sr; return sin(phase) }, env: { hit($0, 0.6) }),
        layer(0.06, peak: 0.04, wet: 0.8, { t in bp.run(.bandpass, n.white(), glide(3000, 1200, t, 0.06), 1.2) }, env: { hit($0, 0.06) }),
    ])
}

/// 120 ms → T_LAND "bend": sub 34→49 Hz, brown rumble opening 80→520 Hz, a dark moving air texture.
func bend() -> ([Double], [Double]) {
    var phase = 0.0, n = Noise(22), n2 = Noise(23), lp = Biquad(), bpA = Biquad(), bpB = Biquad()
    let d = bendLength
    let endFade = { (t: Double) -> Double in t > d - 0.06 ? max(0, (d - t) / 0.06) : 1 }
    return mix([
        layer(d, peak: 0.30, wet: 0.15, { t in phase += 2 * .pi * glide(34, 49, t, d) / sr; return sin(phase) }, env: { pad($0, d) * endFade($0) }),
        layer(d, peak: 0.20, wet: 0.25, { t in lp.run(.lowpass, n.brown(), glide(80, 520, t, d), 0.8) }, env: { pad($0, d) * endFade($0) }),
        layer(d, peak: 0.02, wet: 0.85, { t in
            let w = n2.white()
            return bpA.run(.bandpass, w, 400 * (1 + 0.3 * sin(2 * .pi * 0.35 * t)), 6)
                 + bpB.run(.bandpass, w, 1100 * (1 + 0.3 * sin(2 * .pi * 0.46 * t + 1.7)), 6)
        }, env: { pad($0, d) * endFade($0) }),
    ])
}

/// 820 ms "pop": a whump (118→52 Hz), a brown puff closing 900→150 Hz, a soft reversed-air flutter.
func pop() -> ([Double], [Double]) {
    var phase = 0.0, n = Noise(33), n2 = Noise(34), lp = Biquad(), bp = Biquad()
    return mix([
        layer(0.42, peak: 0.28, wet: 0.2, { t in phase += 2 * .pi * glide(118, 52, t, 0.42) / sr; return sin(phase) }, env: { hit($0, 0.42) }),
        layer(0.35, peak: 0.12, wet: 0.3, { t in lp.run(.lowpass, n.brown(), glide(900, 150, t, 0.35), 0.707) }, env: { hit($0, 0.35) }),
        layer(0.22, peak: 0.05, wet: 0.5, { t in
            bp.run(.bandpass, n2.white(), glide(2600, 700, t, 0.22), 1.4) * (0.75 + 0.25 * sin(2 * .pi * 19 * t))
        }, env: { t in swellEnv(t, 0.22) }),
    ])
}

/// "swell": noise opening 280→5200 Hz plus a 55→110 Hz triangle, exponential rise into a hard 30 ms stop.
/// The stop ends at `swellCut` (sample-exact); only the reverb tail follows.
func swell() -> ([Double], [Double]) {
    var n = Noise(44), bp = Biquad(), phase = 0.0
    let d = swellCut
    return mix([
        layer(d, peak: 0.20, wet: 0.35, { t in bp.run(.bandpass, n.white(), glide(280, 5200, t, d), 0.9) }, env: { swellEnv($0, d) }),
        layer(d, peak: 0.10, wet: 0.2, { t in
            phase += glide(55, 110, t, d) / sr
            let x = phase - floor(phase)
            return 4 * abs(x - 0.5) - 1                                   // triangle
        }, env: { swellEnv($0, d) }),
    ])
}

/// T_LAND "boom": sub 92→29 Hz, triangle 184→58 Hz, brown body closing 1600→110 Hz, high air tail.
func boom() -> ([Double], [Double]) {
    var p1 = 0.0, p2 = 0.0, n = Noise(55), n2 = Noise(56), lp = Biquad(), hp = Biquad()
    return mix([
        layer(1.6, peak: 0.95, wet: 0.35, { t in p1 += 2 * .pi * glide(92, 29, t, 1.6) / sr; return sin(p1) }, env: { hit($0, 1.6) }),
        layer(0.55, peak: 0.22, wet: 0.2, { t in
            p2 += glide(184, 58, t, 0.55) / sr
            let x = p2 - floor(p2); return 4 * abs(x - 0.5) - 1
        }, env: { hit($0, 0.55) }),
        layer(1.0, peak: 0.45, wet: 0.5, { t in lp.run(.lowpass, n.brown(), glide(1600, 110, t, 1.0), 0.707) }, env: { hit($0, 1.0) }),
        layer(2.6, peak: 0.03, wet: 0.85, { t in hp.run(.highpass, n2.white(), glide(7000, 2600, t, 2.6), 0.707) }, env: { hit($0, 2.6) }),
    ])
}

/// Sheet arrives: a soft swish (no sine).
func sheet() -> ([Double], [Double]) {
    var n = Noise(66), bp = Biquad()
    return mix([
        layer(0.38, peak: 0.05, wet: 0.4, { t in bp.run(.bandpass, n.white(), glide(1900, 520, t, 0.38), 1.3) }, env: { hit($0, 0.38) }),
    ])
}

/// Capture cue ("cekrek"): two very short bandpassed-noise clicks (2.5 kHz, then 1.2 kHz 35 ms later)
/// and a tiny low thump. Mechanical, not tonal: no sine above 250 Hz.
func shutter() -> ([Double], [Double]) {
    var n1 = Noise(77), n2 = Noise(78), bp1 = Biquad(), bp2 = Biquad(), phase = 0.0
    let click2 = 0.035
    return mix([
        layer(0.03, peak: 0.16, wet: 0.12, { _ in bp1.run(.bandpass, n1.white(), 2500, 2.2) }, env: { hit($0, 0.025) }),
        layer(click2 + 0.03, peak: 0.12, wet: 0.12, { _ in bp2.run(.bandpass, n2.white(), 1200, 2.2) }, env: { hit($0 - click2, 0.028) }),
        layer(0.09, peak: 0.14, wet: 0.08, { t in phase += 2 * .pi * glide(90, 55, t, 0.06) / sr; return sin(phase) }, env: { hit($0, 0.09) }),
    ])
}

// MARK: Output

func write(_ name: String, _ stereo: ([Double], [Double]), scale: Double) throws {
    let (l, r) = stereo
    var data = Data()
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    let frames = l.count
    data.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + frames * 4))
    data.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(2); u32(UInt32(sr)); u32(UInt32(sr) * 4); u16(4); u16(16)
    data.append(contentsOf: Array("data".utf8)); u32(UInt32(frames * 4))
    func pcm(_ x: Double) -> UInt16 { UInt16(bitPattern: Int16(max(-1, min(1, x * scale)) * 32767)) }
    for i in 0..<frames { u16(pcm(l[i])); u16(pcm(r[i])) }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("wormhole_\(name).wav")
    try data.write(to: url)
    let peak = 20 * log10((zip(l, r).map { max(abs($0), abs($1)) }.max() ?? 0) * scale)
    print(String(format: "%@  %.3f s  peak %.1f dBFS", url.lastPathComponent, Double(frames) / sr, peak))
}

// Sanity check of the FFT convolution scaling.
let check = fftConvolve([1, 0, 0], [0.5, 0.25])
precondition(abs(check[0] - 0.5) < 1e-4 && abs(check[1] - 0.25) < 1e-4, "FFT convolution scale is off: \(check)")

try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let cues: [(String, ([Double], [Double]))] = [("ping", impact()), ("bend", bend()), ("pop", pop()), ("swell", swell()), ("boom", boom()), ("sheet", sheet()), ("shutter", shutter())]
let boomPeak = cues.first { $0.0 == "boom" }!.1
let scale = pow(10, -1.0 / 20) / (zip(boomPeak.0, boomPeak.1).map { max(abs($0), abs($1)) }.max() ?? 1)
for (name, stereo) in cues { try write(name, stereo, scale: scale) }
