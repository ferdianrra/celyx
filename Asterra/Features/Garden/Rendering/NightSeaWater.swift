//  NightSeaWater.swift
//  Touching the Night Sea: taps drop a stone where the finger's ray meets the water, drags trail a finger
//  through it. The renderer drains the queued drops into its ripple simulation every frame.

import AVFoundation
import CoreHaptics
import simd
import UIKit

@MainActor
final class NightSeaWater {
    static let shared = NightSeaWater()

    /// Metres of water the ripple field covers (centred on the viewer); must match RIPPLE_SPAN in the shader.
    static let span = 96.0
    /// Eye height above the water (metres); must match EYE_HEIGHT in the shader.
    static let eyeHeight = 6.0

    struct Drop { var position: SIMD2<Double>; var radius: Double; var height: Double }
    private(set) var pending: [Drop] = []

    private var engine: CHHapticEngine?
    private var plip: [AVAudioPlayer] = []
    private var lastFeedback: CFTimeInterval = 0
    private var lastTrail: (position: SIMD2<Double>, time: CFTimeInterval)?

    private init() {}

    /// Where a look direction [east, north, up] meets the water plane, if it's on the water and inside the field.
    static func waterPoint(_ direction: SIMD3<Double>) -> SIMD2<Double>? {
        guard direction.z < -0.004 else { return nil }
        let p = SIMD2(direction.x,direction.y)*(eyeHeight / -direction.z)
        return abs(p.x) < span/2-1 && abs(p.y) < span/2-1 ? p : nil
    }

    /// A tap: one clean drop (a ring ~0.5–1 m wide), with a soft haptic and a tiny "plip".
    func tap(at point: SIMD2<Double>) {
        pending.append(Drop(position:point,radius:0.45,height:0.06))
        feedback()
    }

    /// A finger trailing through the water: small, frequent disturbances (no sound).
    func trail(at point: SIMD2<Double>) {
        let now = CACurrentMediaTime()
        if let last = lastTrail, now-last.time < 0.035 || simd_distance(last.position,point) < 0.35 { return }
        lastTrail = (point,now)
        pending.append(Drop(position:point,radius:0.35,height:0.012))
    }
    func endTrail() { lastTrail = nil }

    func drain() -> [Drop] { defer { pending.removeAll() }; return pending }

    // MARK: Feedback

    private func feedback() {
        let now = CACurrentMediaTime()
        guard now-lastFeedback > 0.15 else { return }
        lastFeedback = now
        prepare()
        if let player = plip.first(where:{ !$0.isPlaying }) ?? plip.first {
            player.currentTime = 0; player.play()
        }
        if let engine, let pattern = try? CHHapticPattern(events:[CHHapticEvent(eventType:.hapticTransient,parameters:[
            .init(parameterID:.hapticIntensity,value:0.3),.init(parameterID:.hapticSharpness,value:0.15)],relativeTime:0)],parameters:[]) {
            try? engine.start()
            try? engine.makePlayer(with:pattern).start(atTime:CHHapticTimeImmediate)
        } else {
            UIImpactFeedbackGenerator(style:.soft).impactOccurred(intensity:0.3)
        }
    }

    private func prepare() {
        guard plip.isEmpty else { return }
        CrosshairFeedback.shared.prepare()   // shares its .ambient session: follows the Silent switch
        if let url = Bundle.main.url(forResource:"water_plip",withExtension:"wav") {
            plip = (0..<3).compactMap { _ in
                let p = try? AVAudioPlayer(contentsOf:url); p?.prepareToPlay(); return p
            }
        }
        if CHHapticEngine.capabilitiesForHardware().supportsHaptics, let engine = try? CHHapticEngine() {
            engine.isAutoShutdownEnabled = true
            engine.resetHandler = { [weak engine] in try? engine?.start() }
            self.engine = engine
        }
    }
}
