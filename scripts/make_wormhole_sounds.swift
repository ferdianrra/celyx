// Generates the five wormhole handover cues into celyx/Features/Celyx/Wormhole/Sounds/.
//
//   swiftc -O scripts/make_wormhole_sounds.swift -o /tmp/make_wormhole_sounds && /tmp/make_wormhole_sounds
//
// Subtle and cinematic on purpose: glass, sub, air and reverb, no arcade synths.
// Timing: ping @0, bend @120 ms (until T_LAND), pop @820 ms, swell ends exactly on T_LAND, boom @T_LAND.
// `bendLength` / `swellLength` are sized for iPhone 15 (T_LAND ≈ 2176 ms); the app cuts the bend at landing.

import Foundation

let sr = 48000.0
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "celyx/Features/Celyx/Wormhole/Sounds"

// MARK: DSP helpers

struct Noise {
    var state: UInt64 = 0x9E3779B97F4A7C15
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53) * 2 - 1
    }
}
struct OnePole {
    var y = 0.0
    mutating func lowpass(_ x: Double, _ hz: Double) -> Double {
        let a = 1 - exp(-2 * .pi * hz / sr); y += a * (x - y); return y
    }
}
struct Biquad {
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
    mutating func bandpass(_ x: Double, _ hz: Double, _ q: Double) -> Double {
        let w = 2 * .pi * min(hz, sr * 0.45) / sr, alpha = sin(w) / (2 * q), a0 = 1 + alpha
        let b0 = alpha / a0, b2 = -alpha / a0, a1 = -2 * cos(w) / a0, a2 = (1 - alpha) / a0
        let y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }
}
/// Freeverb-style mono reverb.
struct Reverb {
    var combs: [[Double]], ci: [Int], cstore: [Double]
    var alls: [[Double]], ai: [Int]
    let feedback: Double, damp: Double
    init(room: Double, damp: Double) {
        let s = sr / 44100
        combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617].map { [Double](repeating: 0, count: Int(Double($0) * s)) }
        alls = [556, 441, 341, 225].map { [Double](repeating: 0, count: Int(Double($0) * s)) }
        ci = Array(repeating: 0, count: 8); cstore = Array(repeating: 0, count: 8); ai = Array(repeating: 0, count: 4)
        feedback = room; self.damp = damp
    }
    mutating func process(_ x: Double) -> Double {
        var out = 0.0
        for k in 0..<8 {
            let y = combs[k][ci[k]]
            cstore[k] = y * (1 - damp) + cstore[k] * damp
            combs[k][ci[k]] = x * 0.015 + cstore[k] * feedback
            ci[k] = (ci[k] + 1) % combs[k].count
            out += y
        }
        for k in 0..<4 {
            let b = alls[k][ai[k]]
            alls[k][ai[k]] = out + b * 0.5
            out = b - out
            ai[k] = (ai[k] + 1) % alls[k].count
        }
        return out
    }
}

func render(_ seconds: Double, _ f: (Double, Int) -> Double) -> [Double] {
    (0..<Int(seconds * sr)).map { f(Double($0) / sr, $0) }
}
func addReverb(_ x: [Double], wet: Double, room: Double, damp: Double, tone: Double = 6000) -> [Double] {
    var r = Reverb(room: room, damp: damp), lp = OnePole()
    return x.map { s in s + wet * lp.lowpass(r.process(s), tone) }
}
func fade(_ x: [Double], inMs: Double = 1, outMs: Double = 20) -> [Double] {
    let a = Int(inMs / 1000 * sr), b = Int(outMs / 1000 * sr), n = x.count
    return x.enumerated().map { i, s in
        var g = 1.0
        if i < a { g *= Double(i) / Double(max(a, 1)) }
        if i > n - b { g *= Double(n - i) / Double(max(b, 1)) }
        return s * g
    }
}
func normalize(_ x: [Double], peakDB: Double) -> [Double] {
    let peak = x.map(abs).max() ?? 1, target = pow(10, peakDB / 20)
    return x.map { $0 / peak * target }
}
func write(_ name: String, _ x: [Double]) throws {
    var data = Data()
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    data.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + x.count * 2))
    data.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(sr)); u32(UInt32(sr) * 2); u16(2); u16(16)
    data.append(contentsOf: Array("data".utf8)); u32(UInt32(x.count * 2))
    for s in x { u16(UInt16(bitPattern: Int16(max(-1, min(1, s)) * 32767))) }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("wormhole_\(name).wav")
    try data.write(to: url)
    print(String(format: "%@  %.3f s", url.path, Double(x.count) / sr))
}

// MARK: Cues

let bendLength = 2.056       // T_LAND − 120 ms on iPhone 15
let swellLength = 0.476      // 1700 ms → T_LAND on iPhone 15

/// 0 ms: glass ping + soft thump.
func ping() -> [Double] {
    var n = Noise(), lp = OnePole(), phase = 0.0
    let partials: [(Double, Double, Double)] = [(2093, 1, 0.55), (3371, 0.42, 0.34), (5268, 0.22, 0.2), (7190, 0.1, 0.12)]
    let dry = render(1.6) { t, _ in
        var s = 0.0
        for (f, a, tau) in partials { s += a * sin(2 * .pi * f * t + a) * exp(-t / tau) }
        s *= min(1, t / 0.0015) * 0.5
        let f = 48 + 47 * exp(-t / 0.03)
        phase += 2 * .pi * f / sr
        s += 0.9 * sin(phase) * exp(-t / 0.085) * min(1, t / 0.002)
        s += 0.15 * lp.lowpass(n.next(), 1800) * exp(-t / 0.012)
        return s
    }
    return normalize(fade(addReverb(dry, wet: 0.32, room: 0.84, damp: 0.35)), peakDB: -7)
}

/// 120 ms → landing: sub drone ~45 Hz + rumble + soft shimmer pad, swelling and slowly bending down.
func bend() -> [Double] {
    var n = Noise(), lp1 = OnePole(), lp2 = OnePole(), phase = 0.0
    let total = bendLength + 0.25
    let dry = render(total) { t, _ in
        let p = min(1, t / bendLength)
        let env = pow(p, 1.4) * (1 - 0.15 * p) + 0.08
        let f = 46 - 5 * p * p + 0.4 * sin(2 * .pi * 0.8 * t)
        phase += 2 * .pi * f / sr
        var s = 0.75 * sin(phase) + 0.18 * sin(2 * phase + 0.3)
        let brown = lp2.lowpass(lp1.lowpass(n.next(), 160), 90) * 9
        s += 0.35 * brown * (0.6 + 0.4 * sin(2 * .pi * 3.1 * t))
        var pad = 0.0
        for (k, f0) in [659.3, 987.8, 1318.5, 1760.0].enumerated() {
            let detune = 1.6 * Double(k + 1)
            pad += sin(2 * .pi * (f0 - p * 18) * t) + sin(2 * .pi * (f0 + detune - p * 18) * t + 1.1)
        }
        s += 0.022 * pad * smoothstep(0.1, 0.9, p) * (0.7 + 0.3 * sin(2 * .pi * 0.5 * t))
        return s * env * (t > bendLength ? max(0, 1 - (t - bendLength) / 0.25) : 1)
    }
    return normalize(fade(addReverb(dry, wet: 0.25, room: 0.8, damp: 0.5, tone: 3000), inMs: 40, outMs: 30), peakDB: -9)
}

/// 820 ms: glass bloom (soft attack bell cluster) as the hole opens.
func pop() -> [Double] {
    var phase = 0.0
    let partials: [(Double, Double, Double)] = [(1567.98, 1, 0.7), (2349.3, 0.6, 0.55), (3136, 0.38, 0.4), (4698.6, 0.2, 0.28), (6271.9, 0.08, 0.18)]
    let dry = render(2.2) { t, _ in
        let bloom = 1 - exp(-t / 0.022)
        var s = 0.0
        for (f, a, tau) in partials { s += a * sin(2 * .pi * f * t * (1 + 0.002 * exp(-t / 0.2))) * exp(-t / tau) }
        s *= bloom * 0.45
        let f = 85 + 110 * exp(-t / 0.02)
        phase += 2 * .pi * f / sr
        s += 0.45 * sin(phase) * exp(-t / 0.05) * min(1, t / 0.003)
        return s
    }
    return normalize(fade(addReverb(dry, wet: 0.45, room: 0.88, damp: 0.3)), peakDB: -9)
}

/// Reverse whoosh that ends exactly on the landing.
func swell() -> [Double] {
    var n = Noise(), bp = Biquad(), bp2 = Biquad(), phase = 0.0
    let T = swellLength
    return normalize(fade(render(T) { t, _ in
        let p = t / T
        let env = pow(p, 2.6)
        let air = bp.bandpass(n.next(), 350 * pow(12, p), 1.4) + 0.6 * bp2.bandpass(n.next(), 180 * pow(6, p), 0.9)
        phase += 2 * .pi * (55 + 25 * p) / sr
        return env * (0.8 * air + 0.35 * sin(phase))
    }, inMs: 5, outMs: 2.5), peakDB: -8)
}

/// Landing: deep sub hit with a long reverb tail.
func boom() -> [Double] {
    var n = Noise(), lp = OnePole(), lp2 = OnePole(), phase = 0.0
    let dry = render(4.5) { t, _ in
        let f = 30 + 34 * exp(-t / 0.16)
        phase += 2 * .pi * f / sr
        var s = tanh(1.6 * sin(phase)) * exp(-t / 0.75) * min(1, t / 0.003)
        s += 0.55 * lp2.lowpass(lp.lowpass(n.next(), 500), 260) * 4 * exp(-t / 0.06)
        return s
    }
    return normalize(fade(addReverb(dry, wet: 0.55, room: 0.92, damp: 0.55, tone: 1400), outMs: 400), peakDB: -1.5)
}

func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double { let t = max(0, min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t) }

try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
try write("ping", ping())
try write("bend", bend())
try write("pop", pop())
try write("swell", swell())
try write("boom", boom())
