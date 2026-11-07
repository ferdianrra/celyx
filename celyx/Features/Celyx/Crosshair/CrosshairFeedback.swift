//  CrosshairFeedback.swift
//  Haptics (Core Haptics, with a UIKit fallback) and sound effects for the crosshair.
//
//  Sounds: add the files in Sounds/ to the app target (Copy Bundle Resources).
//  Missing files are skipped silently, so the view still works without them.

import AVFoundation
import CoreHaptics
import UIKit

public enum CrosshairHaptic: Sendable { case acquire, lock, validate, fail, collect }

public enum CrosshairSound: String, CaseIterable, Sendable {
    case acquire, lock, validate, back, release, ready
    case fail                          // Celyx addition: validation didn't find the light
    case collect                       // Celyx addition: collected! (rising arpeggio + crystal chime)
    case kick0, kick1, kick2, kick3   // loader ratchet, one pitch per tick
}

public final class CrosshairFeedback: @unchecked Sendable {
    public static let shared = CrosshairFeedback()

    /// Global volume for all crosshair sounds (0–1).
    public var volume: Float = 0.9
    /// Set false if your app manages AVAudioSession itself.
    public var configuresAudioSession = true

    private var hapticEngine: CHHapticEngine?
    private var players: [CrosshairSound: [AVAudioPlayer]] = [:]
    private var prepared = false
    private var suppressed: [CrosshairSound: Date] = [:]

    private init() {}

    /// Called automatically when a CrosshairView appears. Safe to call more than once.
    public func prepare() {
        guard !prepared else { return }
        prepared = true
        if configuresAudioSession {
            // .ambient = respects the silent switch and doesn't stop the user's music.
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        }
        for s in CrosshairSound.allCases {
            guard let url = Bundle.main.url(forResource: "crosshair_\(s.rawValue)", withExtension: "wav") else { continue }
            let count = s.rawValue.hasPrefix("kick") || s == .ready ? 3 : 2   // small pool so rapid hits can overlap
            players[s] = (0..<count).compactMap { _ in
                let p = try? AVAudioPlayer(contentsOf: url)
                p?.prepareToPlay()
                return p
            }
        }
        if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            do {
                let engine = try CHHapticEngine()
                engine.isAutoShutdownEnabled = true
                engine.resetHandler = { [weak engine] in try? engine?.start() }
                try engine.start()
                hapticEngine = engine
            } catch { hapticEngine = nil }
        }
    }

    // MARK: Sound

    /// Skip `sound` if it is triggered within the next `seconds` (e.g. the automatic "back" when a failure plays its own cue).
    public func suppress(_ sound: CrosshairSound, for seconds: TimeInterval) {
        suppressed[sound] = Date().addingTimeInterval(seconds)
    }

    public func play(_ sound: CrosshairSound) {
        if let until = suppressed[sound], Date() < until { return }
        guard let pool = players[sound], !pool.isEmpty else { return }
        let p = pool.first(where: { !$0.isPlaying }) ?? pool[0]
        p.volume = volume
        p.currentTime = 0
        p.play()
    }

    func playKick(_ tick: Int) {
        play([CrosshairSound.kick0, .kick1, .kick2, .kick3][max(0, min(3, tick))])
    }

    // MARK: Haptics

    public func play(_ haptic: CrosshairHaptic) {
        guard let engine = hapticEngine else { fallback(haptic); return }
        do {
            let pattern = try CHHapticPattern(events: events(for: haptic), parameterCurves: curves(for: haptic))
            let player = try engine.makePlayer(with: pattern)
            try engine.start()
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            fallback(haptic)
        }
    }

    private func transient(_ t: TimeInterval, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: t)
    }

    private func continuous(_ t: TimeInterval, _ d: TimeInterval, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: t, duration: d)
    }

    private func events(for h: CrosshairHaptic) -> [CHHapticEvent] {
        switch h {
        case .acquire:  // soft selection tick
            return [transient(0, 0.45, 0.6)]
        case .lock:     // "ka-chunk": hard hit, body, and a bright second click
            return [transient(0, 1.0, 0.85), continuous(0, 0.08, 0.35, 0.15), transient(0.045, 0.5, 1.0)]
        case .validate: // Celyx: a soft swell with the breath-in, no tap
            return [continuous(0, 0.5, 0.4, 0.15)]
        case .fail:     // "not this time": two soft, dull taps that step down, matching the falling two-note sound
            return [transient(0, 0.5, 0.25), transient(0.125, 0.32, 0.1)]
        case .collect:  // rising taps on each arpeggio note, then a firm bright "ting" with a short shimmer
            return [transient(0.035, 0.35, 0.5), transient(0.09, 0.45, 0.6), transient(0.145, 0.55, 0.7),
                    transient(0.20, 0.65, 0.8), transient(0.255, 1.0, 0.9), continuous(0.255, 0.35, 0.35, 0.8)]
        }
    }

    private func curves(for h: CrosshairHaptic) -> [CHHapticParameterCurve] {
        switch h {
        case .validate:
            return [CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
                .init(relativeTime: 0, value: 0.1), .init(relativeTime: 0.42, value: 1), .init(relativeTime: 0.5, value: 0),
            ], relativeTime: 0)]
        case .collect:  // let the chime's shimmer fade out
            return [CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
                .init(relativeTime: 0, value: 1), .init(relativeTime: 0.255, value: 1), .init(relativeTime: 0.6, value: 0),
            ], relativeTime: 0)]
        default:
            return []
        }
    }

    private func fallback(_ h: CrosshairHaptic) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                switch h {
                case .acquire: UISelectionFeedbackGenerator().selectionChanged()
                case .lock: UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                case .validate: UIImpactFeedbackGenerator(style: .light).impactOccurred()
                case .fail: UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
                case .collect: UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        }
    }
}
