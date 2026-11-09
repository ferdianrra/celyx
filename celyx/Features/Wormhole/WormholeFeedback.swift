//  WormholeFeedback.swift
//  Sound + Core Haptics score for the wormhole handover. Everything is scheduled once, at the collect
//  success (tt = 0), against the audio/haptic clocks, so the landing hit lands exactly on T_LAND.

import AVFoundation
import CoreHaptics
import UIKit

final class WormholeFeedback {
    static let shared = WormholeFeedback()

    enum Cue: String, CaseIterable { case ping, bend, pop, swell, boom, sheet, shutter }
    /// The swell's hard stop sits this far into its file (a reverb tail follows); it must land on T_LAND.
    static let swellCut = 0.476

    var volume: Float = 0.9
    private var players: [Cue: AVAudioPlayer] = [:]
    private var engine: CHHapticEngine?
    private var prepared = false

    private init() {}

    /// Pre-loads every cue (so the boom has no latency) and starts the haptic engine.
    func prepare() {
        guard !prepared else { return }
        prepared = true
        CrosshairFeedback.shared.prepare()   // shares its .ambient audio session
        // Same app-wide session as the crosshair (.ambient: follows the Silent switch on purpose); make sure it's active.
        try? AVAudioSession.sharedInstance().setActive(true)
        for cue in Cue.allCases {
            guard let url = Bundle.main.url(forResource:"wormhole_\(cue.rawValue)",withExtension:"wav"),
                  let player = try? AVAudioPlayer(contentsOf:url) else {
                #if DEBUG
                print("[Wormhole] missing or unreadable sound: wormhole_\(cue.rawValue).wav")
                #endif
                continue
            }
            player.prepareToPlay()
            players[cue] = player
        }
        if CHHapticEngine.capabilitiesForHardware().supportsHaptics, let engine = try? CHHapticEngine() {
            engine.isAutoShutdownEnabled = false
            engine.resetHandler = { [weak engine] in try? engine?.start() }
            try? engine.start()
            self.engine = engine
        }
    }

    /// Plays the full score. `landing` = T_LAND in ms.
    func play(landing: Double,sound: Bool = true,haptics: Bool = true) {
        prepare()
        let TL = landing/1000
        if sound { playSounds(TL) }
        if haptics { playHaptics(TL) }
    }

    /// Capture cue ("cekrek"): mechanical shutter clicks + a rigid haptic transient. Follows silent mode.
    func playShutter() {
        prepare()
        if let player = players[.shutter] {
            player.stop(); player.currentTime = 0; player.volume = volume; player.play()
        }
        if let engine, let pattern = try? CHHapticPattern(events:[CHHapticEvent(eventType:.hapticTransient,parameters:[
            .init(parameterID:.hapticIntensity,value:0.9),.init(parameterID:.hapticSharpness,value:0.9)],relativeTime:0)],parameters:[]) {
            try? engine.start()
            try? engine.makePlayer(with:pattern).start(atTime:CHHapticTimeImmediate)
        } else {
            UIImpactFeedbackGenerator(style:.rigid).impactOccurred(intensity:0.9)
        }
    }

    func stop() {
        players.values.forEach { $0.stop() }
        engine?.stop(completionHandler:nil)
        prepared = false
        players = [:]; engine = nil
    }

    // MARK: Sound

    private func playSounds(_ TL: Double) {
        guard let anyPlayer = players.values.first else { return }
        let now = anyPlayer.deviceCurrentTime+0.02
        func start(_ cue: Cue,at t: Double) {
            guard let player = players[cue] else { return }
            player.stop()
            player.currentTime = 0
            player.volume = volume
            player.play(atTime:now+max(0,t))
        }
        let k = 1/WormholeTimeline.pace   // run-up cues follow the faster timeline
        start(.ping,at:0)
        start(.bend,at:0.12*k)
        start(.pop,at:0.82*k)
        // The bend tail was timed for the slower run-up: duck it out right at T_LAND.
        DispatchQueue.main.asyncAfter(deadline:.now()+max(0,TL-0.12)) { [weak self] in
            self?.players[.bend]?.setVolume(0,fadeDuration:0.18)
        }
        start(.swell,at:TL-Self.swellCut)   // its hard stop lands exactly on T_LAND
        start(.boom,at:TL)
        start(.sheet,at:TL+(WormholeTimeline.crossDelay+WormholeTimeline.sheetDelay)/1000)
    }

    // MARK: Haptics

    private func playHaptics(_ TL: Double) {
        guard let engine else {
            DispatchQueue.main.asyncAfter(deadline:.now()+TL) {
                UIImpactFeedbackGenerator(style:.heavy).impactOccurred()
            }
            return
        }
        func transient(_ t: Double,_ i: Float,_ s: Float) -> CHHapticEvent {
            CHHapticEvent(eventType:.hapticTransient,parameters:[.init(parameterID:.hapticIntensity,value:i),.init(parameterID:.hapticSharpness,value:s)],relativeTime:t)
        }
        func continuous(_ t: Double,_ d: Double,_ i: Float,_ s: Float) -> CHHapticEvent {
            CHHapticEvent(eventType:.hapticContinuous,parameters:[.init(parameterID:.hapticIntensity,value:i),.init(parameterID:.hapticSharpness,value:s)],relativeTime:t,duration:d)
        }
        func curve(_ id: CHHapticDynamicParameter.ID,_ t: Double,_ d: Double,_ from: Float,_ to: Float) -> CHHapticParameterCurve {
            CHHapticParameterCurve(parameterID:id,controlPoints:[.init(relativeTime:0,value:from),.init(relativeTime:d,value:to)],relativeTime:t)
        }
        // Each continuous layer gets its own player, so its curves never dim the transients.
        let k = 1/WormholeTimeline.pace
        let swellStart = 1.7*k
        let swellDuration = max(0.05,TL-swellStart)
        let patterns: [CHHapticPattern?] = [
            try? CHHapticPattern(events:[transient(0,0.8,0.9),transient(0.82*k,0.75,0.55),transient(TL,1,0.2),transient(TL+0.54,0.45,0.8)],parameters:[]),
            try? CHHapticPattern(events:[continuous(0.12*k,0.7*k,0.7,0.1)],parameterCurves:[curve(.hapticIntensityControl,0.12*k,0.7*k,0.25,1)]),
            try? CHHapticPattern(events:[continuous(swellStart,swellDuration,1,0.25)],parameterCurves:[
                curve(.hapticIntensityControl,swellStart,swellDuration,0.1,1),curve(.hapticSharpnessControl,swellStart,swellDuration,-0.2,0.3)]),
            try? CHHapticPattern(events:[continuous(TL+0.02,0.6,0.6,0.08)],parameterCurves:[curve(.hapticIntensityControl,TL+0.02,0.6,1,0)]),
        ]
        do {
            try engine.start()
            let at = engine.currentTime+0.02
            for pattern in patterns.compactMap({ $0 }) {
                try engine.makePlayer(with:pattern).start(atTime:at)
            }
        } catch {
            DispatchQueue.main.asyncAfter(deadline:.now()+TL) {
                UIImpactFeedbackGenerator(style:.heavy).impactOccurred()
            }
        }
    }
}
