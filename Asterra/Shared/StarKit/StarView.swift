//
//  StarView.swift
//  StarKit
//
//  A live, animated star for SwiftUI (iOS 17+). Renders one star from its catalog
//  data with the Metal shader in Star.metal.
//
//      StarView(star: selectedStar)                 // header icon (transparent)
//      StarView(star: selectedStar, mode: .hero)    // big, with space background
//

import SwiftUI
import Combine
import CoreMotion

public enum StarViewMode: Sendable {
    /// Small icon on a colored header or card: transparent background,
    /// no diffraction spikes or starfield. The disk fills ~66% of the frame;
    /// the rest is room for the corona.
    case header
    /// Large showcase: own deep-space background, starfield, diffraction spikes,
    /// tilt response. The disk fills ~54% of the frame.
    case hero
}

@MainActor
public struct StarView: View {
    private let style: StarStyle
    private let mode: StarViewMode
    private let tuning: StarTuning
    private let respondsToTilt: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var sensor = TiltSensor()

    public init(style: StarStyle,
                mode: StarViewMode = .header,
                tuning: StarTuning = .default,
                respondsToTilt: Bool? = nil) {
        self.style = style
        self.mode = mode
        self.tuning = tuning
        self.respondsToTilt = respondsToTilt ?? (mode == .hero)
    }

    public init(star: some StarRenderable,
                mode: StarViewMode = .header,
                tuning: StarTuning = .default,
                respondsToTilt: Bool? = nil) {
        self.init(style: StarStyle(star), mode: mode, tuning: tuning, respondsToTilt: respondsToTilt)
    }

    private var paused: Bool {
        reduceMotion || !isVisible || scenePhase != .active
    }

    public var body: some View {
        // Low Power Mode: drop to ~20 fps. Paused: no frames at all.
        TimelineView(.animation(minimumInterval: lowPower ? 1.0 / 20.0 : nil, paused: paused)) { context in
            // Shared clock (not per-view), so the same star keeps its motion when it
            // moves between screens with matchedGeometryEffect.
            let clock = Float(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1800))
            let t = reduceMotion ? 0 : clock * style.speed * tuning.speed
            GeometryReader { geo in
                Rectangle()
                    .fill(.black)
                    .colorEffect(shader(size: geo.size, time: t))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
        .onAppear {
            isVisible = true
            if respondsToTilt && !reduceMotion { sensor.start() }
        }
        .onDisappear {
            isVisible = false
            sensor.stop()
        }
        .onReceive(NotificationCenter.default
            .publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: RunLoop.main)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private func shader(size: CGSize, time: Float) -> Shader {
        let hero = mode == .hero
        let tilt = respondsToTilt ? sensor.tilt : .zero
        return ShaderLibrary.starSurface(
            .float2(Float(size.width), Float(size.height)),
            .float(time),
            .float2(tilt.x, tilt.y),
            .float3(style.deep.x, style.deep.y, style.deep.z),
            .float3(style.core.x, style.core.y, style.core.z),
            .float3(style.glow.x, style.glow.y, style.glow.z),
            .float(style.turbulence * tuning.turbulence),
            .float(style.corona * tuning.corona * (hero ? 1.0 : 0.7)),
            .float(reduceMotion ? 0 : min(style.pulse * tuning.pulse, 3.0)),
            .float(style.hot),
            .float(style.spotAmount),
            .float(hero ? 1.0 : tuning.sparkle), // diffraction spikes
            .float(hero ? 1.0 : 0.0),        // starfield
            .float(hero ? 1.0 : 0.0),        // opaque background
            .float(hero ? 0.27 : 0.33 * tuning.diskScale), // disk radius (fraction of frame)
            .float(tuning.granulation)
        )
    }
}

// MARK: - Tilt (CoreMotion)

@MainActor
@Observable
final class TiltSensor {
    private(set) var tilt: SIMD2<Float> = .zero
    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let attitude = motion?.attitude else { return }
            let roll = attitude.roll, pitch = attitude.pitch
            MainActor.assumeIsolated { self?.update(roll: roll, pitch: pitch) }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        tilt = .zero
    }

    private func update(roll: Double, pitch: Double) {
        let target = SIMD2<Float>(Float(max(-1, min(1, roll / 0.6))),
                                  Float(max(-1, min(1, (pitch - 0.7) / 0.6))))
        tilt += (target - tilt) * 0.1        // ease
    }
}
