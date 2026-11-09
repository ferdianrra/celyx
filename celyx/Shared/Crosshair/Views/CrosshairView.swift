//  CrosshairView.swift
//  Crosshair component · Figma "PAI – Celyx", node 922:1567
//
//  Usage:
//      CrosshairView(state: model.crosshairState, label: star.name)
//
//  Change `state` and the view animates there from wherever it currently is.

import SwiftUI

public struct CrosshairView: View {
    public var state: CrosshairState
    public var label: String
    public var soundEnabled: Bool
    public var hapticsEnabled: Bool
    /// Loader in Locking/Validating, "ready" ripple in Enable. Turn off for a static look.
    public var idleLoops: Bool
    /// Draw bigger without blurring (e.g. 3 for a demo). 1 = Figma size.
    public var scale: CGFloat

    /// Canvas size at scale 1. The reticle centre sits at `reticleCenter`; the label hangs below it.
    public static let size = CGSize(width: 120, height: 96)
    public static let reticleCenter = CGPoint(x: 60, y: 38)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var engine = CrosshairEngine()
    @State private var didAppear = false

    public init(
        state: CrosshairState, label: String = "", soundEnabled: Bool = true,
        hapticsEnabled: Bool = true, idleLoops: Bool = true, scale: CGFloat = 1
    ) {
        self.state = state
        self.label = label
        self.soundEnabled = soundEnabled
        self.hapticsEnabled = hapticsEnabled
        self.idleLoops = idleLoops
        self.scale = scale
    }

    public var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, _ in
                let f = engine.frame(at: timeline.date.timeIntervalSinceReferenceDate * 1000)
                ctx.scaleBy(x: scale, y: scale)
                CrosshairRenderer.draw(f, label: label, in: &ctx, center: Self.reticleCenter)
            }
        }
        .frame(width: Self.size.width * scale, height: Self.size.height * scale)
        .allowsHitTesting(false)
        .onAppear {
            syncSettings()
            if !didAppear {
                engine.jump(to: state)
                didAppear = true
            }
            CrosshairFeedback.shared.prepare()
        }
        .onChange(of: state) { _, newValue in
            syncSettings()
            engine.go(to: newValue)
        }
        .onChange(of: reduceMotion) { _, _ in
            syncSettings()
            engine.refreshLoader()
        }
        .onChange(of: idleLoops) { _, _ in
            syncSettings()
            engine.refreshLoader()
        }
        .onChange(of: soundEnabled) { _, _ in syncSettings() }
        .onChange(of: hapticsEnabled) { _, _ in syncSettings() }
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private func syncSettings() {
        engine.reduceMotion = reduceMotion
        engine.idleLoops = idleLoops
        engine.soundEnabled = soundEnabled
        engine.hapticsEnabled = hapticsEnabled
    }

    private var accessibilityText: Text {
        switch state {
        case .default: return Text("Crosshair")
        case .locking: return Text("Locking on")
        case .enable: return Text(label.isEmpty ? "Locked" : "Locked on \(label)")
        case .validating: return Text(label.isEmpty ? "Validating" : "Validating \(label)")
        }
    }
}

// MARK: - Renderer (pure drawing, 1 unit = 1 pt = Figma px)

enum CrosshairRenderer {
    private static let greenRGB = (r: 48.0 / 255, g: 209.0 / 255, b: 88.0 / 255)  // #30D158

    static func color(_ g: Double) -> Color {
        Color(
            red: 1 + (greenRGB.r - 1) * g, green: 1 + (greenRGB.g - 1) * g, blue: 1 + (greenRGB.b - 1) * g
        )
    }

    static func draw(
        _ f: CrosshairFrame, label: String, in ctx: inout GraphicsContext, center c: CGPoint
    ) {
        let col = color(f.green)

        // Ring group (dotted ring + arc), scaled as one so the dots never re-space.
        var ring = ctx
        ring.translateBy(x: c.x, y: c.y)
        ring.scaleBy(x: f.ringScale, y: f.ringScale)

        var dots = ring
        dots.opacity = f.dotOpacity
        dots.stroke(
            Path(ellipseIn: CGRect(x: -14, y: -14, width: 28, height: 28)),
            with: .color(col), style: StrokeStyle(lineWidth: 4, dash: [1, 3]))

        if f.arcLength > 0.05 && f.arcOpacity > 0.001 {
            var arc = ring
            arc.opacity = f.arcOpacity
            arc.stroke(
                arcPath(tail: f.arcTail, length: f.arcLength, radius: 14),
                with: .color(col), style: StrokeStyle(lineWidth: 4, lineCap: .butt, lineJoin: .round))
        }

        // Lock ping.
        if f.pingOpacity > 0.001 {
            var p = ctx
            p.opacity = f.pingOpacity
            let r = f.pingRadius
            p.stroke(
                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                with: .color(color(1)), lineWidth: f.pingWidth)
        }

        // Ticks.
        for t in f.ticks {
            let a = t.angle * .pi / 180
            let dx = cos(a)
            let dy = sin(a)
            var path = Path()
            path.move(to: CGPoint(x: c.x + dx * t.inner, y: c.y + dy * t.inner))
            path.addLine(to: CGPoint(x: c.x + dx * t.outer, y: c.y + dy * t.outer))
            ctx.stroke(path, with: .color(col), style: StrokeStyle(lineWidth: t.width, lineCap: .butt))
        }

        // Label (SF Pro 15/20, tracking -0.23), focus-pulls in.
        if !label.isEmpty && f.labelOpacity > 0.001 {
            var l = ctx
            l.opacity = f.labelOpacity
            if f.labelBlur > 0.05 { l.addFilter(.blur(radius: f.labelBlur)) }
            let text = l.resolve(
                Text(label).font(.system(size: 15)).tracking(-0.23).foregroundColor(.white))
            l.draw(text, at: CGPoint(x: c.x, y: c.y + 24 + f.labelY), anchor: .top)
        }
    }

    /// Trim path on a circle: starts at 12 o'clock + tail, runs clockwise for `length` degrees.
    static func arcPath(tail: Double, length: Double, radius r: Double) -> Path {
        var p = Path()
        let start = (-90 + tail) * .pi / 180
        let sweep = min(360, length) * .pi / 180
        let steps = max(2, Int(length / 3))
        for s in 0...steps {
            let a = start + sweep * Double(s) / Double(steps)
            let pt = CGPoint(x: r * cos(a), y: r * sin(a))
            if s == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}

// MARK: - Demo

/// Drop this anywhere to try every state. Not needed in production.
public struct CrosshairDemoView: View {
    @State private var state: CrosshairState = .default
    public init() {}
    public var body: some View {
        VStack(spacing: 32) {
            Spacer()
            CrosshairView(state: state, label: "Rigel", scale: 3)
            Spacer()
            Picker("State", selection: $state) {
                Text("Default").tag(CrosshairState.default)
                Text("Locking").tag(CrosshairState.locking)
                Text("Enable").tag(CrosshairState.enable)
                Text("Validating").tag(CrosshairState.validating)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
        .background(Color(red: 0.03, green: 0.05, blue: 0.10).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

#Preview { CrosshairDemoView() }

#Preview("Crosshair states") {
    HStack {
        CrosshairView(state: .default, soundEnabled: false, hapticsEnabled: false, idleLoops: false)
        CrosshairView(state: .validating, soundEnabled: false, hapticsEnabled: false, idleLoops: false)
        CrosshairView(
            state: .enable, label: "Sirius", soundEnabled: false, hapticsEnabled: false, idleLoops: false)
    }.background(.black)
        .preferredColorScheme(.dark)
}
