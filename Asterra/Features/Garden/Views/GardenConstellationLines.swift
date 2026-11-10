import SwiftUI

/// Soft starlight threads; individual stars quietly send light toward their collected neighbors.
struct GardenConstellationLines: View {
    let connections: [GardenConstellationConnection]
    let positions: [Int: CGPoint]
    var isActive = true

    @State private var knownIDs: Set<String>?
    @State private var revealStarts: [String: Date] = [:]
    @State private var animationRevision = 0
    @State private var sweeps: [GardenConstellationSweepScheduler.Sweep] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let duration = 0.9

    private func shimmerTaskID(for visible: [GardenConstellationConnection]) -> String {
        "\(isActive):\(reduceMotion):" + visible.map(\.id).joined(separator: ",")
    }

    var body: some View {
        GeometryReader { geometry in
            let visible = GardenConstellationConnection.visible(connections, positions: positions, size: geometry.size)
            TimelineView(.animation(minimumInterval: 1.0 / 30,
                paused: !isActive || reduceMotion || (revealStarts.isEmpty && (sweeps.isEmpty || visible.isEmpty)))) { timeline in
                Canvas { context, size in
                    context.clip(to: Path(CGRect(origin: .zero, size: size)))
                    for connection in connections {
                        guard let start = positions[connection.startID], let end = positions[connection.endID] else { continue }
                        let dx = end.x - start.x, dy = end.y - start.y
                        let length = hypot(dx, dy)
                        guard length > 16 else { continue }
                        let inset = 7.0 / length
                        let from = CGPoint(x: start.x + dx * inset, y: start.y + dy * inset)
                        let to = CGPoint(x: end.x - dx * inset, y: end.y - dy * inset)
                        let elapsed = revealStarts[connection.id].map { timeline.date.timeIntervalSince($0) }
                        let t = reduceMotion ? 1 : min(1, max(0, (elapsed ?? duration) / duration))
                        let progress = t * t * (3 - 2 * t)
                        var path = Path()
                        path.move(to: from)
                        path.addLine(to: CGPoint(x: from.x + (to.x - from.x) * progress,
                                                y: from.y + (to.y - from.y) * progress))
                        let fade = min(1, t * 4)
                        let starlight = Color(red: 0.62, green: 0.77, blue: 1)
                        // A diffuse halo behind a fine core, keeping stars brighter than their threads.
                        var halo = context
                        halo.addFilter(.blur(radius: 2))
                        halo.stroke(path, with: .color(starlight.opacity(0.11 * fade)),
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        context.stroke(path, with: .linearGradient(
                            Gradient(colors: [starlight.opacity(0.22 * fade), .white.opacity(0.30 * fade),
                                              starlight.opacity(0.22 * fade)]), startPoint: from, endPoint: to),
                            style: StrokeStyle(lineWidth: 0.8, lineCap: .round))

                        if !reduceMotion, t >= 1, let sweep = sweeps.first(where: { $0.connectionID == connection.id }) {
                            let origin = sweep.sourceID == connection.startID ? from : to
                            let destination = sweep.sourceID == connection.startID ? to : from
                            let phase = (timeline.date.timeIntervalSinceReferenceDate - sweep.startedAt)
                                / GardenConstellationSweepScheduler.duration
                            if phase >= 0, phase < 1 {
                                let travel = phase * phase * (3 - 2 * phase)
                                let tail = max(0, travel - 0.18), head = min(1, travel + 0.05)
                                let a = CGPoint(x: origin.x + (destination.x - origin.x) * tail,
                                                y: origin.y + (destination.y - origin.y) * tail)
                                let b = CGPoint(x: origin.x + (destination.x - origin.x) * head,
                                                y: origin.y + (destination.y - origin.y) * head)
                                let strength = sin(phase * .pi)
                                var glimmer = Path()
                                glimmer.move(to: a); glimmer.addLine(to: b)
                                let light = Gradient(colors: [.clear, starlight.opacity(0.35 * strength),
                                                              .white.opacity(0.65 * strength), .clear])
                                var glow = context
                                glow.addFilter(.blur(radius: 3))
                                glow.stroke(glimmer, with: .linearGradient(light, startPoint: a, endPoint: b),
                                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                context.stroke(glimmer, with: .linearGradient(light, startPoint: a, endPoint: b),
                                               style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                            }
                        }
                    }
                }
            }
            .task(id: shimmerTaskID(for: visible)) {
                sweeps = []
                guard isActive, !reduceMotion, !visible.isEmpty else { return }
                var scheduler = GardenConstellationSweepScheduler(
                    connections: visible, start: Date().timeIntervalSinceReferenceDate)
                while !Task.isCancelled {
                    let now = Date().timeIntervalSinceReferenceDate
                    scheduler.update(at: now)
                    sweeps = scheduler.active
                    let delay = max(0.01, scheduler.nextUpdate(after: now) - now)
                    do { try await Task.sleep(for: .seconds(delay)) } catch {
                        sweeps = []
                        return
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: connections.map(\.id), initial: true) { _, ids in
            let current = Set(ids)
            defer { knownIDs = current }
            guard let knownIDs else { return } // Existing collections do not replay on launch.
            revealStarts = revealStarts.filter { current.contains($0.key) }
            let added = current.subtracting(knownIDs)
            guard !reduceMotion, !added.isEmpty else { return }
            for id in added { revealStarts[id] = Date() }
            animationRevision += 1
        }
        .task(id: animationRevision) {
            guard !revealStarts.isEmpty else { return }
            do { try await Task.sleep(for: .seconds(duration)) } catch { return }
            revealStarts = [:]
        }
    }
}
