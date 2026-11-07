// Soft replacements for two crosshair cues (the originals stay in crosshair/Crosshair-Xcode.zip).
//
//   swiftc -O scripts/make_crosshair_soft_sounds.swift -o /tmp/soft && /tmp/soft
//
// crosshair_validate.wav: was a sharp, bright hit right on the "Collect this star" tap (read as a slap).
//   Now a non-percussive "breath-in": filtered-noise riser (bandpass 500 Hz → 2.5 kHz, Q 0.8, 450 ms
//   exponential rise, gentle 80 ms tail) plus a very soft low bloom (90 → 70 Hz, 300 ms, 40 ms attack),
//   a little reverb, peak ≈ −24 dBFS. No transient: every attack is ≥ 25 ms.
// crosshair_release.wav: the unlock (Enable → Default). One soft rounded tone gliding 330 → 220 Hz with an
//   octave below for body, 18 ms raised-cosine attack, gone by 220 ms, no noise at all, peak ≈ −32 dBFS.
// 48 kHz mono 16-bit, like the other crosshair sounds.

import Foundation

let sr = 48000.0
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "celyx/Features/Celyx/Crosshair/Sounds"

struct Noise {
    var state: UInt64
    mutating func white() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53) * 2 - 1
    }
}
struct Bandpass {
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
    mutating func run(_ x: Double, _ hz: Double, _ q: Double) -> Double {
        let w = 2 * .pi * min(hz, sr * 0.45) / sr, alpha = sin(w) / (2 * q), a0 = 1 + alpha
        let y = (alpha * x - alpha * x2 + 2 * cos(w) * y1 - (1 - alpha) * y2) / a0
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }
}
func glide(_ a: Double, _ b: Double, _ t: Double, _ d: Double) -> Double { a * pow(b / a, min(1, max(0, t / d))) }

/// Small, dark reverb: direct convolution with a short decaying-noise IR.
func reverb(_ x: [Double], wet: Double, length: Double = 0.5) -> [Double] {
    var n = Noise(state: 99), lp = 0.0
    let irCount = Int(length * sr)
    let ir = (0..<irCount).map { i -> Double in
        let t = Double(i) / sr
        lp += 0.25 * (n.white() - lp)
        return lp * pow(1 - t / length, 3) * min(1, t / 0.01)
    }
    let energy = sqrt(ir.reduce(0) { $0 + $1 * $1 })
    var out = x + [Double](repeating: 0, count: irCount)
    for (i, s) in x.enumerated() where s != 0 {
        for j in stride(from: 0, to: irCount, by: 1) { out[i + j] += s * ir[j] / energy * wet }
    }
    return out
}

func write(_ name: String, _ x: [Double], peakDB: Double) throws {
    let peak = x.map(abs).max() ?? 1, scale = pow(10, peakDB / 20) / peak
    var data = Data()
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    data.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + x.count * 2))
    data.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(sr)); u32(UInt32(sr) * 2); u16(2); u16(16)
    data.append(contentsOf: Array("data".utf8)); u32(UInt32(x.count * 2))
    for s in x { u16(UInt16(bitPattern: Int16(max(-1, min(1, s * scale)) * 32767))) }
    try data.write(to: URL(fileURLWithPath: outDir).appendingPathComponent("\(name).wav"))
    print(String(format: "%@.wav  %.3f s  peak %.1f dBFS", name, Double(x.count) / sr, peakDB))
}

/// Breath-in: 450 ms exponential rise, then an 80 ms tail. Plus a soft low bloom.
func validate() -> [Double] {
    var n = Noise(state: 7), bp = Bandpass(), bp2 = Bandpass(), phase = 0.0
    let rise = 0.45, tail = 0.08
    let dry = (0..<Int((rise + tail) * sr)).map { i -> Double in
        let t = Double(i) / sr
        let env = t < rise ? (exp(3.2 * t / rise) - 1) / (exp(3.2) - 1) * min(1, t / 0.025)
                           : pow(1 - (t - rise) / tail, 2)
        let hz = glide(500, 2500, t, rise)
        var s = env * (bp.run(n.white(), hz, 0.8) + 0.5 * bp2.run(n.white(), hz * 0.6, 0.8))
        if t < 0.3 {
            phase += 2 * .pi * glide(90, 70, t, 0.3) / sr
            let bloom = min(1, t / 0.04) * sin(.pi * min(1, t / 0.3))
            s += 0.10 * sin(phase) * bloom
        }
        return s
    }
    return reverb(dry, wet: 0.25)
}

/// Unlock: a single soft rounded tone, NO noise (on a phone speaker any short noise burst reads as a slap).
/// 330 → 220 Hz over 150 ms, raised-cosine attack 18 ms, exponential decay to silence by 220 ms, plus an
/// octave below (165 → 110 Hz) at −10 dB for body; gentle 2 kHz lowpass, tiny reverb (~150 ms, 15 % wet).
func release() -> [Double] {
    var p1 = 0.0, p2 = 0.0, lp1 = 0.0, lp2 = 0.0
    let total = 0.22, attack = 0.018
    let a = 1 - exp(-2 * .pi * 2000 / sr)
    let dry = (0..<Int(total * sr)).map { i -> Double in
        let t = Double(i) / sr
        let rise = t < attack ? 0.5 - 0.5 * cos(.pi * t / attack) : 1
        let decay = t < attack ? 1 : exp(-5.5 * (t - attack) / (total - attack)) * (1 - (t - attack) / (total - attack))
        p1 += 2 * .pi * glide(330, 220, t, 0.15) / sr
        p2 += 2 * .pi * glide(165, 110, t, 0.15) / sr
        let x = rise * decay * (sin(p1) + pow(10, -10.0 / 20) * sin(p2))
        lp1 += a * (x - lp1); lp2 += a * (lp1 - lp2)
        return lp2
    }
    return reverb(dry, wet: 0.15, length: 0.15)
}

try write("crosshair_validate", validate(), peakDB: -24)
try write("crosshair_release", release(), peakDB: -32)
