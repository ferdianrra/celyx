import UIKit
import AVFoundation
import Observation
import simd

@MainActor @Observable
final class SkyPatternCalibrationService: NSObject, SkyCaptureSessionDelegate {
    struct Light: Identifiable {
        let id: Int
        let point: CGPoint
    }
    let alignment: CameraSkyAlignment
    var session: SkyCaptureSession { alignment.session }
    var location: ObserverLocation?
    var viewport = CGSize.zero
    var orientation: UIInterfaceOrientation = .portrait
    var patternEnabled = false { didSet { if oldValue != patternEnabled { resetSearch() } } }
    var filters = CalibrationCatalogFilter() {
        didSet {
            if oldValue != filters {
                resetSearch()
                refreshCatalog()
            }
        }
    }
    var isBrowsing = false { didSet { if oldValue != isBrowsing { resetSearch() } } }
    var selectedCatalogID: Int?
    private(set) var candidates: [CalibrationCandidate] = []
    private(set) var lights: [Light] = []
    private(set) var progress: Double = 0
    private(set) var solution: SkyPatternSolution?
    private(set) var centerDirection: SIMD3<Float>?
    private(set) var centerIsDisc = false
    private(set) var referenceReady = false
    private(set) var message = "Finding camera tracking…"
    private let catalogue: [CatalogStar]
    private let previewDate: Date?
    @ObservationIgnored private var running = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var lastAnalysis: TimeInterval = -1
    @ObservationIgnored private var consensus = SkyPatternConsensus()
    @ObservationIgnored private var previousCenter: SIMD3<Float>?
    @ObservationIgnored private var centerSince: TimeInterval?
    @ObservationIgnored private var centerCount = 0
    @ObservationIgnored private var lastCenterTime: TimeInterval?

    init(catalogue: [CatalogStar], alignment: CameraSkyAlignment, preview: Bool = false) {
        self.catalogue = catalogue
        self.alignment = alignment
        previewDate = preview ? AppPreviewData.date : nil
        super.init()
        if preview {
            location = AppPreviewData.location
            refreshCatalog()
        }
    }

    // MARK: Filtered catalog and projection

    func refreshCatalog() {
        guard let location else {
            candidates = []
            return
        }
        let sky = AstronomyService.snapshot(date: previewDate ?? Date(), location: location)
        candidates = catalogue.filter { !$0.isSolarSystemBody }.compactMap { star in
            let d = Refraction.apparent(sky.direction(ra: star.ra_deg, dec: star.dec_deg))
            let point = CalibrationCandidate(
                star: star, direction: SIMD3(Float(d.x), Float(d.z), Float(-d.y)))
            return filters.allows(magnitude: star.mag, altitude: point.altitude) ? point : nil
        }.sorted { $0.star.mag == $1.star.mag ? $0.id < $1.id : $0.star.mag < $1.star.mag }
        if let selectedCatalogID, !candidates.contains(where: { $0.id == selectedCatalogID }) {
            self.selectedCatalogID = nil
        }
    }
    var predictions: [CameraSkyPrediction] {
        guard let frame = session.currentFrame, viewport.width > 0, viewport.height > 0,
            case .normal = frame.camera.trackingState
        else { return [] }
        let view = frame.camera.viewMatrix(viewRotationAngle: viewAngle)
        let projection = frame.camera.projectionMatrix(
            viewRotationAngle: viewAngle, viewportSize: viewport, zNear: 0.01, zFar: 2000)
        return candidates.map { candidate in
            let d = correctedDirection(candidate.direction)
            return CameraSkyPrediction(
                direction: d, star: candidate.star,
                guide: SkyFinderProjection.project(
                    direction: d, view: view, projection: projection, size: viewport))
        }
    }
    var suggestions: [CalibrationSuggestion] {
        let aim: SIMD3<Float>?
        if let centerDirection {
            aim = centerDirection
        } else if let frame = session.currentFrame {
            let d = -frame.camera.transform.columns.2
            aim = SIMD3(d.x, d.y, d.z)
        } else {
            aim = nil
        }
        guard let aim else { return [] }
        return candidates.compactMap { candidate in
            let separation =
                acos(min(1, max(-1, Double(simd_dot(aim, correctedDirection(candidate.direction)))))) * 180
                / .pi
            guard separation <= 15, abs(asin(Double(aim.y)) * 180 / .pi - candidate.altitude) <= 3 else {
                return nil
            }
            return CalibrationSuggestion(candidate: candidate, separation: separation)
        }.sorted { $0.separation < $1.separation }.prefix(8).map { $0 }
    }
    private func correctedDirection(_ direction: SIMD3<Float>) -> SIMD3<Float> {
        alignment.correct(
            simd_quatf(angle: Float(SkyCalibration.arHeadingOffset), axis: SIMD3(0, 1, 0)).act(direction))
    }

    // MARK: Session lifecycle

    func start() {
        guard !running, !AppPreviewData.isRunning,
            AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        else { return }
        running = true
        resetSearch()
        session.delegate = self

        alignment.run()
    }

    func stop(preservingAlignment: Bool = false) {
        guard running else { return }
        running = false
        generation += 1
        analysisTask?.cancel()
        analysisTask = nil
        if session.delegate === self {
            // A successful calibration can hand over the same running world to the camera.
            // Every actual pause invalidates it; saving a quaternion cannot survive a reset.
            if !preservingAlignment || alignment.requiresCalibration {
                alignment.pause(reason: "Calibration camera stopped. Confirm the sky reference again.")
            }
            session.delegate = nil
        }
        resetSearch()
    }
    func resetSearch() {
        generation += 1
        analysisTask?.cancel()
        analysisTask = nil
        consensus.reset()
        progress = 0
        solution = nil
        lights = []
        centerDirection = nil
        referenceReady = false
        previousCenter = nil
        centerSince = nil
        centerCount = 0
        lastCenterTime = nil
        lastAnalysis = -1
    }
    private var viewAngle: CGFloat {
        switch orientation {
        case .landscapeRight: 0
        case .landscapeLeft: 180
        case .portraitUpsideDown: 270
        default: 90
        }
    }

    // MARK: Camera analysis

    func session(_ session: SkyCaptureSession, didUpdate frame: SkyCaptureFrame) {
        guard running, solution == nil, analysisTask == nil else { return }
        guard case .normal = frame.camera.trackingState else {
            consensus.reset()
            progress = 0
            referenceReady = false
            centerDirection = nil
            message = "Hold steady while the camera and motion sensors get ready."
            return
        }
        guard let location, viewport.width > 0, viewport.height > 0 else {
            message = "Finding your location…"
            return
        }
        let time = frame.timestamp
        guard lastAnalysis < 0 || time - lastAnalysis >= 0.25 else { return }
        lastAnalysis = time
        refreshCatalog()
        if isBrowsing { return }
        let sky = AstronomyService.snapshot(date: Date(), location: location)
        let fixedCandidates = self.candidates.map {
            CalibrationCatalogPoint(id: $0.id, direction: $0.direction, magnitude: $0.star.mag)
        }
        let buffer = CameraAnalysisBuffer(value: frame.capturedImage)
        let intrinsics = frame.camera.intrinsics
        let cameraTransform = frame.camera.transform
        let resolution = frame.camera.imageResolution
        let size = viewport
        let view = frame.camera.viewMatrix(viewRotationAngle: viewAngle)
        let projection = frame.camera.projectionMatrix(
            viewRotationAngle: viewAngle, viewportSize: size, zNear: 0.01, zFar: 2000)
        let token = generation
        let pattern = patternEnabled && sky.sunAltitude < -6
        let prior = SkyCalibration.arHeadingOffset
        analysisTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                () -> ([CalibrationObservation], [Bool], [CGPoint], SkyPatternSolution?) in
                let sources =
                    CameraStarDetector.detectDiscs(in: buffer.value)
                    + CameraStarDetector.detect(in: buffer.value)
                var observations: [CalibrationObservation] = []
                var discs: [Bool] = []
                var points: [CGPoint] = []
                for source in sources {
                    guard CameraSkyContext.permits(source.point, in: buffer.value, isDisc: source.isDisc) else { continue }
                    let x =
                        (Float(source.point.x * resolution.width) - intrinsics.columns.2.x)
                        / intrinsics.columns.0.x
                    let y =
                        -(Float(source.point.y * resolution.height) - intrinsics.columns.2.y)
                        / intrinsics.columns.1.y
                    let world = cameraTransform * SIMD4(x, y, -1, 0)
                    let ray = simd_normalize(SIMD3(world.x, world.y, world.z))
                    guard
                        let point = SkyFinderProjection.project(
                            direction: ray, view: view, projection: projection, size: size
                        ).point,
                        !observations.contains(where: {
                            simd_dot($0.direction, ray) > cos(0.75 * Float.pi / 180)
                        })
                    else { continue }
                    observations.append(.init(id: observations.count, direction: ray))
                    discs.append(source.isDisc)
                    points.append(point)
                }
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let anchor = observations.indices.filter {
                    hypot(points[$0].x - center.x, points[$0].y - center.y) <= 28
                }
                .min {
                    hypot(points[$0].x - center.x, points[$0].y - center.y)
                        < hypot(points[$1].x - center.x, points[$1].y - center.y)
                }
                let fit =
                    pattern && anchor != nil
                    ? SkyPatternMatcher.solve(
                        observations: observations.enumerated().filter { !discs[$0.offset] }.map(\.element),
                        catalogue: fixedCandidates, anchorID: observations[anchor!].id, priorOffset: prior)
                    : nil
                return (observations, discs, points, fit)
            }.value
            guard let self, token == self.generation else { return }
            self.analysisTask = nil
            guard self.running, !Task.isCancelled,
                let latest = self.session.currentFrame, latest.timestamp - time < 0.8,
                case .normal = latest.camera.trackingState
            else {
                self.consensus.reset()
                self.progress = 0
                self.referenceReady = false
                return
            }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            self.lights = result.0.indices.map { Light(id: result.0[$0].id, point: result.2[$0]) }
            let centered = result.0.indices.filter {
                hypot(result.2[$0].x - center.x, result.2[$0].y - center.y) <= 28
            }
            if centered.count == 1, let index = centered.first {
                let ray = result.0[index].direction
                if let previous = self.previousCenter, simd_dot(previous, ray) > cos(0.35 * Float.pi / 180),
                    let previousTime = self.lastCenterTime, time - previousTime < 0.8
                {
                    self.centerCount += 1
                } else {
                    self.centerSince = time
                    self.centerCount = 1
                }
                self.lastCenterTime = time
                self.previousCenter = ray
                self.centerDirection = ray
                self.centerIsDisc = result.1[index]
                self.referenceReady = self.centerCount >= 4 && time - (self.centerSince ?? time) >= 0.8
            } else {
                self.centerDirection = nil
                self.previousCenter = nil
                self.referenceReady = false
                self.centerSince = nil
                self.centerCount = 0
            }
            self.progress = self.consensus.add(result.3, at: time)
            if self.progress >= 1, let solution = result.3 {
                self.solution = solution
                self.message = "Pattern confirmed across independent frames."
            } else if let fit = result.3 {
                self.message =
                    "Comparing \(fit.matches.count) lights with the surrounding sky… Hold steady."
            } else if centered.count != 1 {
                self.message =
                    "Put a detected light in the circle. You can choose and confirm a catalog candidate even if only one light is visible."
            } else if result.0.filter({ $0.direction.y > sin(8 * Float.pi / 180) }).count
                < SkyPatternMatcher.minimumAutomaticPatternStars
            {
                self.message =
                    "One light is enough for a confirmed reference. Open Calibration Stars to choose its possible identity; more lights help automatic pattern matching."
            } else {
                self.message =
                    "No unique pattern yet. Try a different light in the circle while keeping the surrounding stars visible."
            }
        }
    }

    // MARK: Tracking interruptions

    func sessionWasInterrupted(_ session: SkyCaptureSession) {
        guard running else { return }
        resetSearch()
        alignment.invalidate(reason: "Camera interrupted. Reacquire the sky reference.")
        message = "Camera interrupted. Reacquire the star pattern."
    }
    func sessionInterruptionEnded(_ session: SkyCaptureSession) {
        guard running else { return }
        running = false
        start()
    }
    func session(_ session: SkyCaptureSession, didFailWithError error: Error) {
        guard running else { return }
        running = false
        resetSearch()
        message = "Camera tracking stopped. Close and reopen calibration."
    }
}
