import QuartzCore

// SwiftUI animations don't interpolate uniforms sent to MTKView. Tick the camera
// explicitly at display refresh so the Metal panorama and SwiftUI overlay stay together.
@MainActor
final class SkyCameraFlight: NSObject {
    private var link: CADisplayLink?
    private var startedAt: CFTimeInterval = 0
    private var duration: Double = 1
    private var update: ((Double) -> Void)?
    private var completion: (() -> Void)?

    func start(duration: Double, update: @escaping (Double) -> Void, completion: @escaping () -> Void) {
        cancel()
        self.duration = duration; self.update = update; self.completion = completion
        startedAt = CACurrentMediaTime()
        update(0)
        let link = CADisplayLink(target:self,selector:#selector(tick(_:)))
        link.add(to:.main,forMode:.common)
        self.link = link
    }
    @objc private func tick(_ link: CADisplayLink) {
        let progress = min(1,max(0,(CACurrentMediaTime()-startedAt)/duration))
        update?(progress)
        if progress >= 1 { complete() }
    }
    func finish() {
        guard link != nil else { return }
        update?(1); complete()
    }
    private func complete() {
        let action = completion
        cancel()
        action?()
    }
    func cancel() {
        link?.invalidate(); link = nil; update = nil; completion = nil
    }
}
