import ARKit
import Observation
import simd

/// Owns calibration targets, sensor samples, reference validation, and saved corrections.
@MainActor @Observable
final class SkyCalibrationViewModel {
    enum Mode { case reference, pattern }
    enum PreviewState { case reference, pattern, matching, saved, singleLight, catalogAR }
    enum Outcome: Equatable {
        case none
        case saved(String)
        case failed(String)
    }
    struct Target: Identifiable, Equatable {
        let id: Int
        let name: String
        let direction: SIMD3<Double>
        let isDisc: Bool
        var azimuth: Double { atan2(direction.x, direction.y) }
        var altitude: Double { asin(min(1, max(-1, direction.z))) }
    }
    let catalogue: [CatalogStar]
    let previewState: PreviewState?
    let engine: SkyPatternCalibrationService
    var motion: MotionService?
    var location: ObserverLocation?
    var attitude: simd_double3x3?
    var attitudeDate: Date?
    var motionMessage: String?
    var targets: [Target] = []
    var selectedID: Int?
    var mode: Mode = .reference
    var choseMode = false
    var outcome: Outcome = .none
    var cameraDenied = false
    var showsCandidates = false
    var showsCandidateAR = false
    var selectedFromCatalog = false
    var confirmsSingleIdentity = false

    init(
        catalogue: [CatalogStar], alignment: CameraSkyAlignment? = nil,
        preview: PreviewState? = nil, opensCatalog: Bool = false,
        initialLocation: ObserverLocation? = nil
    ) {
        self.catalogue = catalogue
        previewState = preview
        let shared =
            alignment ?? (preview == nil ? CameraSkyAlignment() : AppPreviewData.model.cameraAlignment)
        let engine = SkyPatternCalibrationService(
            catalogue: catalogue, alignment: shared, preview: preview != nil || AppPreviewData.isRunning)
        self.engine = engine
        location = initialLocation
        if let initialLocation {
            engine.location = initialLocation
            engine.refreshCatalog()
        }
        engine.isBrowsing = opensCatalog
        showsCandidates = opensCatalog
        showsCandidateAR = preview == .catalogAR
        mode = preview == nil || preview == .reference ? .reference : .pattern
        if preview != nil {
            targets = [
                .init(id: CatalogStar.sun.id, name: "Sun", direction: SIMD3(0.6, 0, 0.8), isDisc: true)
            ]
        }
        if preview == .saved { outcome = .saved("Pattern confirmed with 4 stars · fit RMS 0.12°") }
    }
    var target: Target? {
        if let candidate = engine.candidates.first(where: { $0.id == selectedID }) {
            let d = candidate.direction
            return Target(
                id: candidate.id, name: candidate.star.title,
                direction: SIMD3(Double(d.x), Double(-d.z), Double(d.y)), isDisc: false)
        }
        return targets.first(where: { $0.id == selectedID }) ?? targets.first
    }
    var referenceTargets: [Target] {
        guard let target, !targets.contains(where: { $0.id == target.id }) else { return targets }
        return [target] + targets
    }
    var progress: Double { previewState == .matching ? 0.55 : engine.progress }
    var saved: Bool { if case .saved = outcome { true } else { false } }
    func chooseCandidate(_ candidate: CalibrationCandidate) {
        selectedID = candidate.id
        engine.selectedCatalogID = candidate.id
        selectedFromCatalog = true
        choseMode = true
        mode = .reference
        outcome = .none
        engine.patternEnabled = false
        showsCandidateAR = false
        showsCandidates = false
    }
    var instruction: String {
        if cameraDenied { return "Allow camera access in Settings to calibrate." }
        if saved {
            return "Direction correction saved. Check another part of the sky before collecting."
        }
        if mode == .pattern {
            return
                "Put a real light in the circle. If only one is visible, choose its possible identity from Calibration Stars and confirm it. If more are visible, the app also checks their relative positions."
        }
        guard location != nil || previewState != nil else { return "Finding your location…" }
        guard let target else {
            return "No suitable bright reference is above the horizon. Use the star-pattern method."
        }
        return
            "If you can recognize \(target.name), aim at its real light and hold steady. The direction below is an estimate until you confirm the object."
    }
    func choose(_ value: Mode) {
        choseMode = true
        mode = value
        outcome = .none
        engine.patternEnabled = value == .pattern
    }
    func start() async {
        guard previewState == nil else { return }
        if AppPreviewData.isRunning {
            targets = [
                .init(id: CatalogStar.sun.id, name: "Sun", direction: SIMD3(0.6, 0, 0.8), isDisc: true)
            ]
            return
        }
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: granted = true
        case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
        default: granted = false
        }
        guard granted else {
            cameraDenied = true
            return
        }
        engine.start()
        let service = motion ?? MotionService()
        motion = service
        service.onLocation = { [weak self] fix in
            guard let self else { return }
            self.location = fix
            self.engine.location = fix
            self.refreshTargets()
        }
        service.onCalibration = { [weak self] ready, _, message, _ in
            self?.motionMessage = ready ? nil : message
        }
        service.onAttitude = { [weak self] value in
            self?.attitude = value
            self?.attitudeDate = Date()
        }
        service.start { _, _, _ in }
    }
    func stop(preservingAlignment: Bool) {
        engine.stop(preservingAlignment: saved && preservingAlignment)
        motion?.stop()
    }
    func arAim() -> (azimuth: Double, altitude: Double)? {
        guard let frame = engine.session.currentFrame, case .normal = frame.camera.trackingState else {
            return nil
        }
        let d = -frame.camera.transform.columns.2
        return (atan2(Double(d.x), Double(-d.z)), asin(min(1, max(-1, Double(d.y)))))
    }
    func motionAim() -> Double? {
        guard let attitude, let attitudeDate, abs(attitudeDate.timeIntervalSinceNow) < 0.5 else {
            return nil
        }
        let d = -attitude.columns.2
        return atan2(d.x, d.y)
    }
    func refreshTargets() {
        guard let location else { return }
        let sky = AstronomyService.snapshot(date: Date(), location: location)
        func make(_ star: CatalogStar, _ direction: SIMD3<Double>, disc: Bool) -> Target {
            Target(id: star.id, name: star.title, direction: Refraction.apparent(direction), isDisc: disc)
        }
        var list: [Target] = []
        if sky.sunAltitude > 5 { list.append(make(.sun, sky.sunDirection, disc: true)) }
        if asin(sky.moonDirection.z) * 180 / .pi > 5 && sky.moonIllumination > 0.15 {
            list.append(make(.moon, sky.moonDirection, disc: true))
        }
        if sky.sunAltitude < -6 {
            list += sky.planets.filter { $0.star.mag < 1.5 && $0.direction.z > sin(10 * .pi / 180) }
                .sorted { $0.star.mag < $1.star.mag }.map { make($0.star, $0.direction, disc: false) }
            list += catalogue.filter { $0.mag < 1.3 }.sorted { $0.mag < $1.mag }
                .map { ($0, sky.direction(ra: $0.ra_deg, dec: $0.dec_deg)) }
                .filter { $0.1.z > sin(15 * .pi / 180) }.prefix(6).map { make($0.0, $0.1, disc: false) }
        }
        targets = list
        if !list.contains(where: { $0.id == selectedID })
            && !engine.candidates.contains(where: { $0.id == selectedID })
        {
            selectedID = list.first?.id
        }
        if !choseMode {
            mode = list.isEmpty ? .pattern : .reference
            engine.patternEnabled = mode == .pattern
        }
    }
    // MARK: Save calibration

    func calibrate() {
        guard previewState == nil, let target, engine.referenceReady, let ray = engine.centerDirection
        else { return }
        let d = target.direction
        let expected = SIMD3(Float(d.x), Float(d.z), Float(-d.y))
        guard let offset = CalibrationReference.correction(expected: expected, observed: ray),
            !target.isDisc || engine.centerIsDisc
        else {
            outcome = .failed(
                "The light does not fit this reference’s height or shape. Check the object, or use pattern matching."
            )
            return
        }
        save(
            offset: offset, label: target.name,
            message: "Calibrated using the confirmed reference \(target.name).")
    }
    func save(offset: Double, label: String, message: String) {
        guard previewState == nil else { return }
        let garden = arAim().flatMap { ar in
            motionAim().map { SkyCalibration.wrap(ar.azimuth + offset - $0) }
        }
        SkyCalibration.save(arOffset: offset, motionOffset: garden, target: label)
        // Replace the old local quaternion without resetting the AR world we just calibrated.
        engine.alignment.save(
            rotation: simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)), reference: label, date: Date(),
            location: location)
        outcome = .saved(
            message
                + (garden == nil
                    ? " Garden direction still needs a fresh motion reading." : " Camera and garden updated.")
        )
    }
}
