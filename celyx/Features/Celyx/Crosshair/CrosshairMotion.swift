//  CrosshairMotion.swift
//  Crosshair component · Figma "PAI – Celyx", node 922:1567
//
//  The motion engine. Every number here matches the live preview:
//  https://claude.ai/artifact/27QgvtUxUZaAF4LzwKtioe
//  Units: points, milliseconds, degrees (0° = 3 o'clock, positive = clockwise on screen).

import Foundation

// MARK: - State

/// The four Figma variants. Drive this from your aiming / validation logic.
public enum CrosshairState: Int, CaseIterable, Sendable {
    case `default` = 0
    case locking
    case enable
    case validating

    var hasLoader: Bool { self == .locking || self == .validating }

    /// Target values per state (straight from the Figma frames).
    var values: CrosshairValues {
        switch self {
        case .default:
            return .init(ringScale: 1, dotOpacity: 0.40, green: 0, arcLength: 0, arcOpacity: 0.48,
                         tickInner: 12, tickOuter: 20, tickWidth: 2, labelOpacity: 0, labelY: 6, labelBlur: 2.5, tickRotationBase: 0)
        case .locking:
            return .init(ringScale: 1, dotOpacity: 0.40, green: 0, arcLength: 270, arcOpacity: 0.48,
                         tickInner: 16, tickOuter: 24, tickWidth: 2.5, labelOpacity: 0, labelY: 6, labelBlur: 2.5, tickRotationBase: 45)
        case .enable:
            return .init(ringScale: 1, dotOpacity: 0.60, green: 1, arcLength: 360, arcOpacity: 0,
                         tickInner: 12, tickOuter: 20, tickWidth: 2.5, labelOpacity: 1, labelY: 0, labelBlur: 0, tickRotationBase: 0,
                         focusScale: 1.12)
        case .validating:
            return .init(ringScale: 1.25, dotOpacity: 0.60, green: 1, arcLength: 270, arcOpacity: 0.48,
                         tickInner: 15, tickOuter: 25, tickWidth: 2.5, labelOpacity: 1, labelY: 0, labelBlur: 0, tickRotationBase: 45)
        }
    }
}

struct CrosshairValues {
    var ringScale: Double      // dots + arc group. 1.25 = r 17.5 / stroke 5 (Validating)
    var dotOpacity: Double
    var green: Double          // 0 = white, 1 = #30D158
    var arcLength: Double      // degrees of trim, from 12 o'clock clockwise
    var arcOpacity: Double
    var tickInner: Double
    var tickOuter: Double
    var tickWidth: Double
    var labelOpacity: Double
    var labelY: Double
    var labelBlur: Double
    var tickRotationBase: Double  // only (rotation mod 90) matters
    /// Celyx: the whole reticle grows a little while a star is collectible (Enable), label kept clear.
    var focusScale: Double = 1
}

// MARK: - Easing

/// CSS-style cubic-bezier(x1, y1, x2, y2).
public struct CubicBezier: Sendable {
    public let x1, y1, x2, y2: Double
    public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) { self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2 }

    public func callAsFunction(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        let cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx
        let cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by
        func sx(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
        func sy(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }
        func dx(_ t: Double) -> Double { (3 * ax * t + 2 * bx) * t + cx }
        var t = x
        for _ in 0..<8 {
            let e = sx(t) - x
            if abs(e) < 1e-6 { return sy(t) }
            let d = dx(t)
            if abs(d) < 1e-6 { break }
            t -= e / d
        }
        var lo = 0.0, hi = 1.0
        t = x
        for _ in 0..<40 {
            let v = sx(t)
            if abs(v - x) < 1e-6 { break }
            if x > v { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return sy(t)
    }
}

public enum CrosshairEase {
    /// Signature in-out. Slow lift-off, fast middle, long soft landing.
    public static let flow = CubicBezier(0.65, 0, 0.15, 1)
    /// Arrivals and text. Quint-out, no bounce.
    public static let glide = CubicBezier(0.22, 1, 0.36, 1)
    /// Geometry that lands with a small overshoot.
    public static let settle = CubicBezier(0.34, 1.35, 0.64, 1)
    /// The lock: pulls back a hair, snaps through, overshoots.
    public static let anticipate = CubicBezier(0.68, -0.35, 0.27, 1.35)
    /// Things leaving or closing. Expo-in.
    public static let exit = CubicBezier(0.7, 0, 0.84, 0)
    /// Loader trim end / trim start.
    public static let loaderHead = CubicBezier(0.4, 0, 0.2, 1)
    public static let loaderTail = CubicBezier(0.8, 0, 0.6, 1)
    public static let linear = CubicBezier(0, 0, 1, 1)
    /// Celyx: spring-like pop (≈ response .32 s, damping .62: one small overshoot).
    public static let pop = CubicBezier(0.34, 1.56, 0.64, 1)
}

// MARK: - Choreography (the transition table)

enum TrackKey: Hashable {
    case tickRotate, tickRadius, tickWidth, ringScale, ringOpacity, color
    case arcTrim, arcOpacity, label, ping, tickDip, tickPunch
    case focus
}

struct Track {
    var delay: Double       // ms
    var duration: Double    // ms
    var ease: CubicBezier
    var stagger: Double = 0 // ms per tick (tick 0 = 12 o'clock, then clockwise)
}

struct CrosshairTransition {
    var name: String
    var tracks: [TrackKey: Track]
    var haptic: CrosshairHaptic?
    var hapticAt: Double = 0     // ms
    var sound: CrosshairSound?
    var soundAt: Double = 0      // ms

    /// Tracks that are not listed move with this (same as the preview).
    var fallbackTrack: Track {
        var m = 0.0
        for (k, t) in tracks where k != .ping && k != .tickPunch { m = max(m, t.delay + t.duration) }
        return Track(delay: 0, duration: max(120, m), ease: CrosshairEase.flow)
    }
    func track(_ k: TrackKey) -> Track { tracks[k] ?? fallbackTrack }
}

enum CrosshairChoreography {
    private static func t(_ d: Double, _ dur: Double, _ e: CubicBezier, _ s: Double = 0) -> Track {
        Track(delay: d, duration: dur, ease: e, stagger: s)
    }
    private typealias E = CrosshairEase

    static func transition(from: CrosshairState, to: CrosshairState, reduceMotion: Bool) -> CrosshairTransition? {
        if from == to { return nil }
        if reduceMotion {
            let lin = t(0, 120, E.linear)
            let keys: [TrackKey] = [.tickRotate, .tickRadius, .tickWidth, .ringScale, .ringOpacity, .color, .arcTrim, .arcOpacity, .label]
            return CrosshairTransition(name: "Reduced motion", tracks: Dictionary(uniqueKeysWithValues: keys.map { ($0, lin) }))
        }
        switch (from, to) {
        case (.default, .locking):   // Acquire
            return CrosshairTransition(name: "Acquire", tracks: [
                .tickDip: t(0, 270, E.settle, 14), .tickRotate: t(20, 220, E.flow, 14), .tickRadius: t(20, 250, E.settle, 14),
                .tickWidth: t(0, 270, E.flow), .arcTrim: t(10, 300, E.flow),
            ], haptic: .acquire, hapticAt: 0, sound: .acquire, soundAt: 0)

        case (.locking, .enable):    // Lock
            return CrosshairTransition(name: "Lock", tracks: [
                .arcTrim: t(0, 190, E.exit), .arcOpacity: t(180, 240, E.glide), .color: t(150, 320, E.flow), .ringOpacity: t(150, 320, E.flow),
                .tickRotate: t(70, 450, E.anticipate, 16), .tickRadius: t(70, 450, E.anticipate, 16), .tickPunch: t(200, 380, E.glide, 16),
                .tickWidth: t(140, 320, E.glide), .label: t(260, 490, E.glide), .ping: t(190, 700, E.glide),
                .focus: t(190, 420, E.pop),
            ], haptic: .lock, hapticAt: 190, sound: .lock, soundAt: 190)

        case (.enable, .validating): // Validate
            return CrosshairTransition(name: "Validate", tracks: [
                .ringScale: t(0, 430, E.settle), .arcOpacity: t(40, 80, E.linear), .arcTrim: t(40, 400, E.flow),
                .tickDip: t(0, 310, E.settle, 16), .tickRotate: t(30, 240, E.flow, 16), .tickRadius: t(30, 320, E.settle, 16),
                .tickWidth: t(0, 320, E.flow),
            ], haptic: .validate, hapticAt: 0, sound: .validate, soundAt: 0)

        case (.validating, .enable): // Back to ready
            return CrosshairTransition(name: "Back to ready", tracks: [
                .arcTrim: t(0, 320, E.flow), .arcOpacity: t(270, 110, E.linear), .ringScale: t(50, 380, E.flow),
                .tickDip: t(0, 300, E.settle, 14), .tickRotate: t(30, 240, E.flow, 14), .tickRadius: t(30, 300, E.flow, 14),
            ], sound: .back)

        case (.locking, .default):   // Lose
            return CrosshairTransition(name: "Lose", tracks: [
                .arcTrim: t(0, 320, E.flow), .tickDip: t(0, 300, E.settle, 14), .tickRotate: t(30, 240, E.flow, 14),
                .tickRadius: t(30, 300, E.flow, 14), .tickWidth: t(0, 300, E.flow),
            ])   // Celyx: leaving a target is silent

        case (.enable, .default):    // Release: the lock in reverse (ticks spin back −90°, retract and fire out)
            return CrosshairTransition(name: "Release", tracks: [
                .label: t(0, 160, E.exit), .tickRotate: t(0, 340, E.flow, 10), .tickRadius: t(0, 340, E.flow, 10),
                .tickDip: t(0, 300, E.settle, 14), .color: t(0, 220, E.flow), .ringOpacity: t(0, 220, E.flow),
                .tickWidth: t(0, 300, E.flow), .ringScale: t(0, 340, E.flow), .focus: t(0, 340, E.flow),
            ], haptic: .release, hapticAt: 0)   // Celyx: silent, just a whisper of a haptic

        case (.enable, .locking):    // Slip
            return CrosshairTransition(name: "Slip", tracks: [
                .label: t(0, 270, E.exit), .color: t(0, 320, E.flow), .ringOpacity: t(0, 320, E.flow),
                .tickDip: t(0, 270, E.settle, 14), .tickRotate: t(20, 220, E.flow, 14), .tickRadius: t(20, 270, E.settle, 14),
                .arcOpacity: t(0, 80, E.linear), .arcTrim: t(50, 320, E.flow),
            ], sound: .back)

        case (.validating, .default): // Cancel
            return CrosshairTransition(name: "Cancel", tracks: [
                .arcTrim: t(0, 320, E.flow), .ringScale: t(0, 380, E.flow), .label: t(0, 270, E.exit),
                .color: t(50, 350, E.flow), .ringOpacity: t(50, 350, E.flow),
                .tickDip: t(0, 300, E.settle, 14), .tickRotate: t(30, 240, E.flow, 14), .tickRadius: t(30, 300, E.flow, 14),
                .tickWidth: t(0, 350, E.flow),
            ])   // Celyx: silent

        default:                      // Morph: any other jump
            var tr: [TrackKey: Track] = [
                .tickRotate: t(30, 270, E.flow, 14), .tickRadius: t(0, 400, E.settle, 16), .tickWidth: t(0, 400, E.settle),
                .ringScale: t(0, 400, E.settle), .ringOpacity: t(0, 400, E.flow), .color: t(0, 400, E.flow),
                .arcTrim: t(0, 400, E.flow), .arcOpacity: t(0, 80, E.linear), .label: t(0, 400, E.flow),
                .tickDip: t(0, 310, E.settle, 14),
            ]
            if to == .enable {
                tr[.arcTrim] = t(0, 190, E.exit); tr[.arcOpacity] = t(180, 240, E.glide); tr[.ping] = t(190, 700, E.glide)
                tr[.tickPunch] = t(200, 380, E.glide, 16); tr[.label] = t(220, 490, E.glide); tr[.focus] = t(190, 420, E.pop)
                return CrosshairTransition(name: "Morph", tracks: tr, haptic: .lock, hapticAt: 190, sound: .lock, soundAt: 190)
            }
            let s: CrosshairSound? = to == .locking ? .acquire : (to == .validating ? .validate : nil)   // Celyx: Default is silent
            return CrosshairTransition(name: "Morph", tracks: tr, sound: s)
        }
    }
}

// MARK: - Tunables for the living ticks and loader

enum CrosshairTuning {
    // Loader = two trim paths chasing (head on loaderHead, tail on loaderTail).
    static let loaderCycleLocking = 1600.0      // ms per cycle
    static let loaderCycleValidating = 1300.0
    static let loaderMinLength = 24.0           // degrees
    static let loaderMaxLength = 270.0
    static let loaderDrift = 130.0              // extra degrees per cycle
    static let loaderFadeIn = 650.0             // ms, Flow, starts 100 ms before the arc finishes drawing

    // Tick retract-and-fire (every transition).
    static let dipDepth = 0.85                  // tick shrinks to 15 % of its length, anchored at the inner end
    static let dipAttackShare = 0.35            // first 35 % on Exit, rest on Settle

    // Lock impact squash.
    static let punchSquash = 0.22               // 22 % shorter
    static let punchThicken = 1.4               // +1.4 pt wider
    static let punchAttackShare = 0.15

    // Idle tick life.
    static let kickAmp = 3.0, kickAttack = 60.0, kickDecay = 430.0           // loader head passes a tick
    static let readyAmp = -2.4, readyAttack = 80.0, readyDecay = 480.0       // Enable "ready" ripple
    static let readyPeriod = 2400.0, readyFirst = 1100.0, readyStagger = 55.0

    // Motion smear while ticks rotate fast.
    static let smearFullAt = 700.0              // deg/s
    static let smearLength = 3.5                // pt added to the outer end
    static let smearThin = 0.3                  // 30 % thinner

    // Lock ping ring.
    static let pingFromRadius = 14.0, pingToRadius = 26.0
    static let pingFromWidth = 2.2, pingToWidth = 0.5, pingOpacity = 0.6
}

// MARK: - Engine

struct Tween {
    var value: Double
    var from: Double
    var to: Double
    var start: Double = 0
    var duration: Double = 1
    var ease: CubicBezier = CrosshairEase.linear

    init(_ v: Double) { value = v; from = v; to = v }

    mutating func set(_ v: Double) { value = v; from = v; to = v; start = 0; duration = 1 }
    mutating func retarget(_ target: Double, _ track: Track, extraDelay: Double = 0, now: Double) {
        from = value; to = target
        start = now + track.delay + extraDelay
        duration = max(1, track.duration)
        ease = track.ease
    }
    mutating func update(_ now: Double) {
        if now < start { value = from } else { value = from + (to - from) * ease(min(1, (now - start) / duration)) }
    }
}

struct Envelope { var start: Double = -1e12; var duration: Double = 1 }
struct Kick { var start: Double = -1e12; var attack: Double = 1; var decay: Double = 1; var amp: Double = 0 }

/// Everything the renderer needs for one frame.
struct CrosshairFrame {
    struct Tick { var angle: Double; var inner: Double; var outer: Double; var width: Double }
    var ringScale: Double
    var dotOpacity: Double
    var green: Double
    var arcTail: Double
    var arcLength: Double
    var arcOpacity: Double
    var ticks: [Tick]
    var labelOpacity: Double
    var labelY: Double
    var labelBlur: Double
    var pingRadius: Double
    var pingWidth: Double
    var pingOpacity: Double
    var focusScale: Double = 1
}

final class CrosshairEngine {
    private(set) var current: CrosshairState = .default
    var reduceMotion = false
    var idleLoops = true
    var soundEnabled = true
    var hapticsEnabled = true

    // Animated properties
    private var ringScale = Tween(1), dotOpacity = Tween(0.4), green = Tween(0), focusScale = Tween(1)
    private var arcTail = Tween(0), arcLength = Tween(0), arcOpacity = Tween(0.48)
    private var tickWidth = Tween(2)
    private var labelOpacity = Tween(0), labelY = Tween(6), labelBlur = Tween(2.5)
    private var loaderWeight = Tween(0)
    private var tickRot = [Tween](repeating: Tween(0), count: 4)
    private var tickIn = [Tween](repeating: Tween(12), count: 4)
    private var tickOut = [Tween](repeating: Tween(20), count: 4)

    // One-shot envelopes
    private var dip = [Envelope](repeating: Envelope(), count: 4)
    private var punch = [Envelope](repeating: Envelope(), count: 4)
    private var kick = [Kick](repeating: Kick(), count: 4)
    private var ping = Envelope()

    // Loader + bookkeeping
    private var loaderOn = false, loaderClock = 0.0, loaderStart = 0.0, loaderOffset = 0.0, loaderCycle = 1600.0
    private var renderedTail = 0.0, renderedLength = 0.0
    private var prevHead: Double?
    private var prevRot = [0.0, 0.0, 0.0, 0.0]
    private var lastNow: Double?
    private var readyClock = 0.0, readyNext = CrosshairTuning.readyFirst
    private var pending: [DispatchWorkItem] = []
    /// Celyx: hovering on the edge of a star must not machine-gun the lock cue.
    private var lastLockCue = -1e12

    private static let loaderMaxDiff: Double = {
        var m = 0.0
        for i in 0...200 { let p = Double(i) / 200; m = max(m, CrosshairEase.loaderHead(p) - CrosshairEase.loaderTail(p)) }
        return m
    }()

    static func nowMs() -> Double { Date().timeIntervalSinceReferenceDate * 1000 }

    // MARK: Loader math
    private static func loaderTailRaw(_ p: Double) -> Double {
        let n = floor(p)
        return 360 * (n + CrosshairEase.loaderTail(p - n)) + CrosshairTuning.loaderDrift * (p - 0.5)
    }
    private static func loaderLength(_ p: Double) -> Double {
        let f = p - floor(p)
        let d = (CrosshairEase.loaderHead(f) - CrosshairEase.loaderTail(f)) / loaderMaxDiff
        return CrosshairTuning.loaderMinLength + d * (CrosshairTuning.loaderMaxLength - CrosshairTuning.loaderMinLength)
    }

    // MARK: State changes

    /// Snap to a state with no animation (first appearance).
    func jump(to state: CrosshairState) {
        current = state
        let v = state.values
        ringScale.set(v.ringScale); dotOpacity.set(v.dotOpacity); green.set(v.green); focusScale.set(v.focusScale)
        arcTail.set(0); arcLength.set(v.arcLength); arcOpacity.set(v.arcOpacity)
        tickWidth.set(v.tickWidth); labelOpacity.set(v.labelOpacity); labelY.set(v.labelY); labelBlur.set(v.labelBlur)
        for i in 0..<4 { tickRot[i].set(v.tickRotationBase); tickIn[i].set(v.tickInner); tickOut[i].set(v.tickOuter); prevRot[i] = v.tickRotationBase }
        renderedTail = 0; renderedLength = v.arcLength
        loaderOn = false
        startLoader(after: 0, now: Self.nowMs())
    }

    /// Animate to a new state from wherever everything is right now (interruptible).
    func go(to target: CrosshairState) {
        guard target != current else { return }
        let now = Self.nowMs()
        let from = current
        current = target
        guard let tr = CrosshairChoreography.transition(from: from, to: target, reduceMotion: reduceMotion) else { return }

        // Freeze the live arc (including the loader) so we animate from what's on screen.
        let visible = arcOpacity.value > 0.02 && renderedLength > 0.5 && renderedLength < 359.5
        arcTail.set(renderedTail); arcLength.set(renderedLength); loaderWeight.set(0); loaderOn = false

        let v = target.values
        let rot = tr.track(.tickRotate), rad = tr.track(.tickRadius)
        for i in 0..<4 {
            let s = Double(i)
            tickRot[i].retarget(targetRotation(tickRot[i].value, from: from, to: target), rot, extraDelay: s * rot.stagger, now: now)
            tickIn[i].retarget(v.tickInner, rad, extraDelay: s * rad.stagger, now: now)
            tickOut[i].retarget(v.tickOuter, rad, extraDelay: s * rad.stagger, now: now)
        }
        tickWidth.retarget(v.tickWidth, tr.track(.tickWidth), now: now)
        ringScale.retarget(v.ringScale, tr.track(.ringScale), now: now)
        focusScale.retarget(v.focusScale, tr.track(.focus), now: now)
        dotOpacity.retarget(v.dotOpacity, tr.track(.ringOpacity), now: now)
        green.retarget(v.green, tr.track(.color), now: now)
        arcOpacity.retarget(v.arcOpacity, tr.track(.arcOpacity), now: now)
        let lab = tr.track(.label)
        labelOpacity.retarget(v.labelOpacity, lab, now: now)
        labelY.retarget(v.labelY, lab, now: now)
        labelBlur.retarget(v.labelBlur, lab, now: now)

        // Arc trim: zip away, close, or draw on.
        let at = tr.track(.arcTrim)
        let tailTarget: Double, lengthTarget: Double
        if v.arcLength == 0 {
            tailTarget = renderedTail + renderedLength; lengthTarget = 0              // tail catches head
        } else if v.arcLength >= 360 {
            tailTarget = renderedTail + (visible ? 60 : 0); lengthTarget = 360       // close the circle
        } else {
            if visible { tailTarget = ceil((renderedTail - 1e-6) / 360) * 360 }      // swing forward to 12 o'clock
            else { arcTail.set(0); arcLength.set(0); tailTarget = 0 }                // draw on from 12 o'clock
            lengthTarget = v.arcLength
        }
        arcTail.retarget(tailTarget, at, now: now)
        arcLength.retarget(lengthTarget, at, now: now)
        startLoader(after: at.delay + at.duration, now: now)

        if !reduceMotion {
            if let d = tr.tracks[.tickDip] { for i in 0..<4 { dip[i] = Envelope(start: now + d.delay + Double(i) * d.stagger, duration: d.duration) } }
            if let p = tr.tracks[.tickPunch] { for i in 0..<4 { punch[i] = Envelope(start: now + p.delay + Double(i) * p.stagger, duration: p.duration) } }
            if let p = tr.tracks[.ping] { ping = Envelope(start: now + p.delay, duration: p.duration) }
        }
        readyClock = 0; readyNext = CrosshairTuning.readyFirst

        // Haptics + sound, timed to the motion.
        pending.forEach { $0.cancel() }; pending.removeAll()
        var snd = soundEnabled, hap = hapticsEnabled
        if target == .enable {
            // At most one lock sound (and haptic) per 600 ms.
            if now - lastLockCue < 600 { snd = false; hap = false } else { lastLockCue = now }
        }
        if let h = tr.haptic, hap { schedule(after: tr.hapticAt) { CrosshairFeedback.shared.play(h) } }
        if let s = tr.sound, snd { schedule(after: tr.soundAt) { CrosshairFeedback.shared.play(s) } }
    }

    func refreshLoader() {
        // Call after toggling idleLoops / reduceMotion: hand over smoothly from the live arc.
        let now = Self.nowMs()
        arcTail.set(renderedTail); arcLength.set(renderedLength); loaderWeight.set(0); loaderOn = false
        guard current.hasLoader else { return }
        if idleLoops && !reduceMotion {
            startLoader(after: 0, now: now)
            loaderOffset = renderedTail - Self.loaderTailRaw(0.5)
        } else {
            let tr = Track(delay: 0, duration: 500, ease: CrosshairEase.flow)
            arcTail.retarget(ceil((renderedTail - 1e-6) / 360) * 360, tr, now: now)
            arcLength.retarget(current.values.arcLength, tr, now: now)
        }
    }

    private func schedule(after ms: Double, _ block: @escaping @Sendable () -> Void) {
        let item = DispatchWorkItem(block: block)
        pending.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + ms / 1000, execute: item)
    }

    private func targetRotation(_ cur: Double, from: CrosshairState, to: CrosshairState) -> Double {
        let base = to.values.tickRotationBase
        // Release spins back a full quarter turn (reverse of the lock) even though both rest at 0°.
        if from == .enable && to == .default { return base + floor((cur - base - 1e-6) / 90) * 90 }
        if to.rawValue > from.rawValue { return base + ceil((cur - base - 1e-6) / 90) * 90 }   // forward = clockwise
        return base + floor((cur - base + 1e-6) / 90) * 90                                      // back = counter-clockwise
    }

    private func startLoader(after delay: Double, now: Double) {
        guard current.hasLoader, idleLoops, !reduceMotion else { loaderOn = false; return }
        loaderOn = true
        loaderClock = 0
        loaderStart = delay
        loaderCycle = current == .locking ? CrosshairTuning.loaderCycleLocking : CrosshairTuning.loaderCycleValidating
        loaderOffset = arcTail.to - Self.loaderTailRaw(0.5)   // phase 0.5 = 270° with tail at the target angle
        loaderWeight.set(0)
        loaderWeight.retarget(1, Track(delay: max(0, delay - 100), duration: CrosshairTuning.loaderFadeIn, ease: CrosshairEase.flow), now: now)
    }

    // MARK: Envelopes
    private func dipEnv(_ t: Double, _ d: Double) -> Double {
        if t < 0 || t > d { return 0 }
        let a = CrosshairTuning.dipAttackShare * d
        return t < a ? CrosshairEase.exit(t / a) : 1 - CrosshairEase.settle((t - a) / (d - a))
    }
    private func punchEnv(_ t: Double, _ d: Double) -> Double {
        if t < 0 || t > d { return 0 }
        let a = CrosshairTuning.punchAttackShare * d
        return t < a ? 1 - pow(1 - t / a, 3) : pow(1 - (t - a) / (d - a), 2)
    }
    private func kickEnv(_ k: Kick, _ now: Double) -> Double {
        let t = now - k.start
        if k.amp == 0 || t < 0 || t > k.attack + k.decay { return 0 }
        let e = t < k.attack ? 1 - pow(1 - t / k.attack, 3) : pow(1 - (t - k.attack) / k.decay, 3)
        return e * k.amp
    }

    // MARK: Frame
    func frame(at now: Double) -> CrosshairFrame {
        let dt = lastNow.map { min(50, max(1, now - $0)) } ?? 16
        lastNow = now

        ringScale.update(now); dotOpacity.update(now); green.update(now); focusScale.update(now)
        arcTail.update(now); arcLength.update(now); arcOpacity.update(now)
        tickWidth.update(now); labelOpacity.update(now); labelY.update(now); labelBlur.update(now); loaderWeight.update(now)
        for i in 0..<4 { tickRot[i].update(now); tickIn[i].update(now); tickOut[i].update(now) }

        // Loader: two trim paths chasing.
        var lTail = arcTail.value, lLen = arcLength.value
        if loaderOn {
            loaderClock += dt
            let p = 0.5 + max(0, loaderClock - loaderStart) / loaderCycle
            lTail = loaderOffset + Self.loaderTailRaw(p)
            lLen = Self.loaderLength(p)
        }
        let w = loaderOn ? min(1, max(0, loaderWeight.value)) : 0
        renderedTail = arcTail.value + (lTail - arcTail.value) * w
        renderedLength = arcLength.value + (lLen - arcLength.value) * w

        // Enable: "ready" ripple.
        if idleLoops && !reduceMotion && current == .enable {
            readyClock += dt
            if readyClock >= readyNext {
                readyNext += CrosshairTuning.readyPeriod
                for i in 0..<4 {
                    kick[i] = Kick(start: now + Double(i) * CrosshairTuning.readyStagger, attack: CrosshairTuning.readyAttack,
                                   decay: CrosshairTuning.readyDecay, amp: CrosshairTuning.readyAmp)
                    if soundEnabled { schedule(after: Double(i) * CrosshairTuning.readyStagger) { CrosshairFeedback.shared.play(.ready) } }
                }
            }
        }
        // Loader head passes a tick: that tick kicks out.
        let head = -90 + renderedTail + renderedLength
        if loaderOn, w > 0.6, !reduceMotion, let ph = prevHead {
            let step = head - ph
            if step > 0 && step < 180 {
                for i in 0..<4 {
                    let td = tickRot[i].value + Double(i) * 90
                    var d0 = (td - ph).truncatingRemainder(dividingBy: 360)
                    if d0 < 0 { d0 += 360 }
                    if d0 > 0 && d0 <= step {
                        kick[i] = Kick(start: now, attack: CrosshairTuning.kickAttack, decay: CrosshairTuning.kickDecay, amp: CrosshairTuning.kickAmp)
                        // Celyx: no ratchet clicks while validating (the soft breath-in carries it).
                        if soundEnabled && current != .validating { let k = i; DispatchQueue.main.async { CrosshairFeedback.shared.playKick(k) } }
                    }
                }
            }
        }
        prevHead = head

        // Ticks: rotation + retract/fire + squash + kick + smear.
        var ticks: [CrosshairFrame.Tick] = []
        ticks.reserveCapacity(4)
        for i in 0..<4 {
            let rot = tickRot[i].value
            let vel = abs(rot - prevRot[i]) / (dt / 1000)
            prevRot[i] = rot
            let smear = reduceMotion ? 0 : min(1, vel / CrosshairTuning.smearFullAt)
            let dE = dipEnv(now - dip[i].start, dip[i].duration)
            let pE = punchEnv(now - punch[i].start, punch[i].duration)
            let kE = kickEnv(kick[i], now)
            let inner = tickIn[i].value + kE
            let len = (tickOut[i].value - tickIn[i].value) * (1 - CrosshairTuning.dipDepth * dE) * (1 - CrosshairTuning.punchSquash * pE)
            let width = tickWidth.value * (1 - CrosshairTuning.smearThin * smear) + CrosshairTuning.punchThicken * pE
                + 0.5 * max(0, kE) / CrosshairTuning.kickAmp
            ticks.append(.init(angle: rot + Double(i) * 90, inner: inner,
                               outer: inner + max(0.3, len) + smear * CrosshairTuning.smearLength, width: width))
        }

        // Ping.
        var pr = 0.0, pw = 0.0, po = 0.0
        let pt = now - ping.start
        if pt >= 0 && pt < ping.duration {
            let u = pt / ping.duration, e = CrosshairEase.glide(u)
            pr = CrosshairTuning.pingFromRadius + (CrosshairTuning.pingToRadius - CrosshairTuning.pingFromRadius) * e
            pw = CrosshairTuning.pingFromWidth + (CrosshairTuning.pingToWidth - CrosshairTuning.pingFromWidth) * e
            po = CrosshairTuning.pingOpacity * pow(1 - u, 1.4)
        }

        return CrosshairFrame(
            ringScale: ringScale.value, dotOpacity: dotOpacity.value, green: min(1, max(0, green.value)),
            arcTail: renderedTail, arcLength: min(360, max(0, renderedLength)), arcOpacity: max(0, arcOpacity.value),
            ticks: ticks,
            labelOpacity: min(1, max(0, labelOpacity.value)), labelY: labelY.value, labelBlur: max(0, labelBlur.value),
            pingRadius: pr, pingWidth: pw, pingOpacity: po, focusScale: focusScale.value)
    }
}
