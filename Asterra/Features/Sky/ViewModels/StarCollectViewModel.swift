import AVFoundation
import Observation

/// Owns target selection, capture verification, feedback, and observation persistence.
@MainActor @Observable
final class StarCollectViewModel {
    /// What sits inside the centre circle right now.
    struct CenterTarget {
        let star: CatalogStar
        /// The actual point of light the camera sees there. Required to collect.
        let detection: CameraStarAnnotation?
        var id: Int { star.id }
    }

    enum Verification: Equatable {
        case idle
        case checking(Int)
        case failed(Int)
    }
    let model: HomeViewModel
    let service: SkyFinderService
    var viewSize: CGSize = .zero
    var errorMessage: String?
    var verification: Verification = .idle
    var capturedItem: GardenCollectionItem?
    let captureRadius: CGFloat = CameraTrackingPolicy.acquisitionRadius
    /// The displayed target stays locked through small aim changes.
    var lockedID: Int?
    let lockRadius = CameraTargetSelection.lockReleaseRadius
    private let allowsTargetSwitch: Bool
    /// A star the user closed with X: skipped until it leaves the lock radius, so a neighbour can be picked.
    var excludedID: Int?
    /// Called after a successful save. Return true when the caller takes over the celebration
    /// (the wormhole handover from Home); the album here is then not opened.
    @ObservationIgnored var onSaved: ((CenterTarget, CollectedStar) -> Bool)?
    var isChecking: Bool { if case .checking = verification { true } else { false } }

    init(model: HomeViewModel, allowsTargetSwitch: Bool = true) {
        self.model = model
        self.allowsTargetSwitch = allowsTargetSwitch
        service = SkyFinderService(
            location: model.location, catalogue: model.stars, alignment: model.cameraAlignment,
            usesContinuousAutoFocus: true)
    }

    private var center: CGPoint { CGPoint(x: viewSize.width / 2, y: viewSize.height / 2) }
    func distance(_ point: CGPoint) -> CGFloat { hypot(point.x - center.x, point.y - center.y) }

    /// Predictions use visibility estimates. A repeatedly observed, identified night-sky
    /// light can still be collected when a cloud or light-pollution estimate disagrees.
    var centerTarget: CenterTarget? {
        if let lockedID, let held = lockedTarget(lockedID) {
            if allowsTargetSwitch, viewSize != .zero, !service.isAdjustingCamera,
                let aimed = aimedObservation(), aimed.id != held.id,
                CameraTargetSelection.shouldSwitchLock(to: aimed.point, from: held.detection?.point, center: center)
            {
                return CenterTarget(star: aimed.star, detection: aimed)
            }
            return held
        }
        guard let target = selectedTarget, target.id != excludedID else { return nil }
        return target
    }

    /// The locked star, if it's still in view within the hold radius.
    private func lockedTarget(_ id: Int) -> CenterTarget? {
        guard service.status == .tracking, viewSize != .zero else { return nil }
        let observations = service.annotations + (service.reacquiredPinnedAnnotation.map { [$0] } ?? [])
            + (service.automaticallyIdentifiedAnnotation.map { [$0] } ?? [])
        if let seen = observations.first(where: { $0.id == id && isInsideLockRadius($0) }) {
            return CenterTarget(star: seen.star, detection: seen)
        }
        if let ready = service.retainedCaptureAnnotation, ready.id == id {
            return CenterTarget(star: ready.star, detection: ready)
        }
        guard service.hasReferenceAlignment else { return nil }
        let tolerance = min(25, max(10, (service.cameraHeadingAccuracy ?? 15) + 5))
        if let body = service.brightBodiesNearAim().first(where: { $0.star.id == id && $0.separation <= tolerance }) {
            return CenterTarget(star: body.star, detection: nil)
        }
        return nil
    }

    /// Is the star the user dismissed still near the centre?
    var excludedIsNear: Bool {
        guard let excludedID else { return false }
        return (service.annotations + (service.reacquiredPinnedAnnotation.map { [$0] } ?? []))
            .contains { $0.id == excludedID && isInsideLockRadius($0) }
            || service.brightBodiesNearAim().contains { $0.star.id == excludedID && $0.separation <= 25 }
    }

    private func aimedObservation() -> CameraStarAnnotation? {
        let automatic = service.automaticallyIdentifiedAnnotation
        if service.alignment.requiresCalibration {
            return automatic.flatMap { $0.id != excludedID && distance($0.point) <= captureRadius ? $0 : nil }
        }
        return aimedObservation(visible: Set(service.viewableObjects.map(\.id)), automatic: automatic)
    }

    private func aimedObservation(visible: Set<Int>, automatic: CameraStarAnnotation?) -> CameraStarAnnotation? {
        let observations = service.annotations + (service.reacquiredPinnedAnnotation.map { [$0] } ?? [])
            + (automatic.map { [$0] } ?? [])
        return observations
            .filter({ annotation in
                let observedAtNight =
                    (service.sunAltitude ?? 90) < -6 && !annotation.star.isSolarDisc
                    && (annotation.sourceDirection?.y ?? -1) > sin(5 * Float.pi / 180)
                return annotation.id != excludedID && (visible.contains(annotation.id) || observedAtNight)
                    && distance(annotation.point) <= captureRadius
            })
            .min(by: { distance($0.point) < distance($1.point) })
    }

    private var selectedTarget: CenterTarget? {
        let automatic = service.automaticallyIdentifiedAnnotation
        if let automatic, automatic.id != excludedID, isInsideLockRadius(automatic) {
            return CenterTarget(star: automatic.star, detection: automatic)
        }
        guard !service.alignment.requiresCalibration, service.status == .tracking else {
            if let ready = service.retainedCaptureAnnotation {
                return CenterTarget(star: ready.star, detection: ready)
            }
            return nil
        }
        guard !service.isAdjustingCamera, viewSize != .zero else { return nil }
        let visible = Set(service.viewableObjects.map(\.id))
        if let seen = aimedObservation(visible: visible, automatic: automatic), isInsideLockRadius(seen) {
            return CenterTarget(star: seen.star, detection: seen)
        }
        if service.isPinnedLightCentered,
            let pin = service.pinnedLight, pin.isIdentified, let star = pin.match?.star,
            let point = service.pinnedLightGuide?.point, distance(point) <= CameraTargetSelection.lockRadius(for: star)
        {
            let live =
                service.reacquiredPinnedAnnotation
                ?? service.annotations.first {
                    $0.id == star.id && distance($0.point) <= captureRadius
                }
            return CenterTarget(
                star: star,
                detection: CameraTargetSelection.captureEvidence(
                    for: star.id, live: live, retained: service.retainedCaptureAnnotation))
        }
        if let ready = service.retainedCaptureAnnotation {
            return CenterTarget(star: ready.star, detection: ready)
        }
        // While returning to an observed pin, a different catalog marker alone
        // must not replace that light or expose an unrelated Collect action.
        if service.pinnedLight != nil { return nil }
        // Sun, Moon and planets: judged by angle, tolerant to the phone compass error.
        // The Collect check then demands the real bright light inside the circle.
        let tolerance = min(25, max(10, (service.cameraHeadingAccuracy ?? 15) + 5))
        if let body = service.brightBodiesNearAim()
            .filter({ $0.star.id != excludedID && visible.contains($0.star.id) && $0.separation <= tolerance })
            .min(by: { $0.separation < $1.separation })
        {
            return CenterTarget(star: body.star, detection: nil)
        }
        // An ordinary star's predicted position is never presented as a detection.
        // The filtered catalog remains available in the separate AR map.
        return nil
    }

    private func isInsideLockRadius(_ annotation: CameraStarAnnotation) -> Bool {
        distance(annotation.point) <= CameraTargetSelection.lockRadius(for: annotation.star)
    }
    private var shownTarget: CenterTarget? { centerTarget }

    func detectStar() {
        verification = .idle
        service.requestDetection()
    }

    // MARK: Actions

    /// Collect the retained recognized frame, or capture fresh optical evidence.
    /// A remembered direction alone never substitutes for a recorded photograph.
    func collect(_ target: CenterTarget) {
        guard !isChecking, capturedItem == nil,
            service.status == .tracking || service.retainedCaptureAnnotation?.id == target.id,
            !service.isAdjustingCamera
        else { return }
        guard let current = centerTarget, current.id == target.id,
            current.detection != nil || (current.star.isSolarDisc && lightIsInCircle(for: current.star))
        else {
            fail(target.id)
            return
        }
        verification = .checking(target.id)
        save(current)
    }

    /// Soft "not this time" cue (sound + two dull taps) instead of the harsh system error buzz,
    /// and mute the crosshair's automatic "back" sound so the two don't stack.
    private func fail(_ id: Int) {
        CrosshairFeedback.shared.suppress(.back, for: 0.6)
        CrosshairFeedback.shared.play(CrosshairSound.fail)
        CrosshairFeedback.shared.play(CrosshairHaptic.fail)
        verification = .failed(id)
    }

    private func save(_ target: CenterTarget) {
        // The confirmed light: a detected source, or the bright source we just measured at the centre.
        let annotation =
            target.detection
            ?? CameraStarAnnotation(star: target.star, point: center, size: CGSize(width: 28, height: 28))
        let detail =
            target.detection?.estimatedSeparation.map {
                String(
                    format:
                        "Our best match is %@, based on direction and brightness. Direction offset: %.1f°.",
                    target.star.title, $0)
            } ?? "Confirmed by direction, time and place, with a bright light seen in the circle."
        let note =
            (service.hasReferenceAlignment
                ? "" : "Uncalibrated catalog estimate; identity not independently confirmed. ") + detail
        guard let draft = service.captureObservation(annotation: annotation, identificationNote: note)
        else {
            fail(target.id)
            return
        }
        do {
            let record = try model.saveCameraObservation(draft, note: "")
            if let onSaved, onSaved(target, record) { return }
            // Celebrate: our own chime + haptic, and mute the crosshair's automatic "back" on the way to Enable.
            CrosshairFeedback.shared.suppress(.back, for: 0.6)
            CrosshairFeedback.shared.play(CrosshairSound.collect)
            CrosshairFeedback.shared.play(CrosshairHaptic.collect)
            verification = .idle
            capturedItem = GardenCollectionItem(star: target.star, record: record)
            service.stop()
        } catch {
            verification = .idle
            errorMessage = error.localizedDescription
        }
    }

    /// Reads the live camera frame: is there really a light inside the circle?
    private func lightIsInCircle(for star: CatalogStar) -> Bool {
        guard let buffer = service.session.currentFrame?.capturedImage, viewSize != .zero,
            CameraSkyContext.permits(CGPoint(x: 0.5, y: 0.5), in: buffer, isDisc: star.isSolarDisc),
            let sample = CenterLightProbe.measure(buffer, viewSize: viewSize, radius: captureRadius)
        else { return false }
        if star.isSun {
            // A saturated disc filling a good part of the circle.
            return sample.peak >= 245 && sample.saturatedFraction >= 0.10
        }
        // A point or disc clearly brighter than the sky right around it.
        return sample.peak >= 60 && sample.peak - sample.surroundingMedian >= 35
    }
}
