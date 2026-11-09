import AVFoundation
import SwiftUI

struct SkyCameraPreview: UIViewRepresentable {
    let session: SkyCaptureSession
    let onViewport: (CGSize, UIInterfaceOrientation) -> Void
    var onTap: ((CGPoint) -> Void)? = nil
    var onHold: ((CGPoint) -> Void)? = nil
    var onExposureDrag: ((CGFloat, CGPoint, Bool) -> Void)? = nil
    var skyMarkers: [CameraSkyPrediction] = []
    var labeledMarkerIDs: Set<Int> = []
    var selectedMarkerID: Int? = nil
    var onSelectMarker: ((Int) -> Void)? = nil
    var markerColor: UIColor = .systemCyan
    var markerTitlePrefix = ""
    var zoom: Double = 1

    func makeUIView(context: Context) -> FinderCameraContainer {
        let container = FinderCameraContainer()
        let view = container.cameraView
        view.session = session
        view.preview.session = session.captureSession
        updateUIView(container, context: context)
        view.installCameraGestures()
        return container
    }
    func updateUIView(_ container: FinderCameraContainer, context: Context) {
        container.zoom = zoom
        let view = container.cameraView
        view.viewportChanged = onViewport
        view.tapped = onTap
        view.held = onHold
        view.exposureDragged = onExposureDrag
        view.onSelectMarker = onSelectMarker
        view.markerColor = markerColor
        view.markerTitlePrefix = markerTitlePrefix
        view.updateSkyMarkers(skyMarkers, labeledIDs: labeledMarkerIDs, selectedID: selectedMarkerID)
        view.updateViewport()
    }
    static func dismantleUIView(_ view: FinderCameraContainer, coordinator: ()) {
        view.cameraView.stopRendering()
        view.cameraView.preview.session = nil
    }
}

final class FinderCameraContainer: UIView {
    let cameraView = FinderCameraView()
    var zoom: Double = 1 { didSet { updateCameraLayout() } }
    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        addSubview(cameraView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() { super.layoutSubviews(); updateCameraLayout() }
    private func updateCameraLayout() {
        cameraView.bounds = CGRect(origin: .zero, size: bounds.size)
        cameraView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        let scale = CGFloat(CameraZoom.clamped(zoom))
        cameraView.transform = CGAffineTransform(scaleX: scale, y: scale)
    }
}

final class FinderCameraView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    weak var session: SkyCaptureSession?
    var viewportChanged: ((CGSize, UIInterfaceOrientation) -> Void)?
    var tapped: ((CGPoint) -> Void)?
    var held: ((CGPoint) -> Void)?
    var exposureDragged: ((CGFloat, CGPoint, Bool) -> Void)?
    var onSelectMarker: ((Int) -> Void)?
    var markerColor: UIColor = .systemCyan
    var markerTitlePrefix = ""
    private var exposurePanActive = false
    private var markers: [CameraSkyPrediction] = []
    private var labels: Set<Int> = []
    private var selectedID: Int?
    private var markerViews: [Int: UILabel] = [:]
    private var displayLink: CADisplayLink?

    override init(frame: CGRect) {
        super.init(frame: frame)
        preview.videoGravity = .resizeAspectFill
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        stopRendering()
        if window != nil {
            let link = CADisplayLink(target: self, selector: #selector(renderMarkers))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }
    func stopRendering() { displayLink?.invalidate(); displayLink = nil }
    func updateSkyMarkers(_ markers: [CameraSkyPrediction], labeledIDs: Set<Int>, selectedID: Int?) {
        self.markers = markers; labels = labeledIDs; self.selectedID = selectedID
        let ids = Set(markers.map(\.id))
        for id in Array(markerViews.keys) where !ids.contains(id) {
            markerViews.removeValue(forKey: id)?.removeFromSuperview()
        }
        renderMarkers()
    }
    @objc private func renderMarkers() {
        guard let frame = session?.currentFrame else {
            markerViews.values.forEach { $0.isHidden = true }; return
        }
        let angle = rotationAngle
        let view = frame.camera.viewMatrix(viewRotationAngle: angle)
        let projection = frame.camera.projectionMatrix(viewRotationAngle: angle, viewportSize: bounds.size,
                                                        zNear: 0.01, zFar: 2000)
        for marker in markers {
            let label = markerViews[marker.id] ?? UILabel()
            if markerViews[marker.id] == nil {
                label.font = .systemFont(ofSize: 13, weight: .medium)
                label.textAlignment = .center; label.numberOfLines = 2
                label.isUserInteractionEnabled = false
                addSubview(label); markerViews[marker.id] = label
            }
            let point = SkyFinderProjection.project(direction: marker.direction, view: view,
                                                      projection: projection, size: bounds.size).point
            label.isHidden = point == nil
            label.textColor = markerColor
            label.text = (marker.id == selectedID ? "◎" : "○") +
                (labels.contains(marker.id) ? "\n" + markerTitlePrefix + marker.star.title : "")
            label.bounds = CGRect(x: 0, y: 0, width: 150, height: 44)
            if let point { label.center = CGPoint(x: point.x, y: point.y + (labels.contains(marker.id) ? 10 : 0)) }
        }
    }
    private var rotationAngle: CGFloat {
        switch window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait {
        case .landscapeRight: 0
        case .landscapeLeft: 180
        case .portraitUpsideDown: 270
        default: 90
        }
    }
    func installCameraGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(didTap(_:)))
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(didHold(_:)))
        hold.minimumPressDuration = 0.7
        tap.require(toFail: hold)
        addGestureRecognizer(tap)
        addGestureRecognizer(hold)
        if exposureDragged != nil {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(didDragExposure(_:)))
            pan.minimumNumberOfTouches = 1
            pan.maximumNumberOfTouches = 1
            tap.require(toFail: pan)
            // The container also receives drags over the AR coaching overlay.
            (superview ?? self).addGestureRecognizer(pan)
        }
    }
    @objc private func didDragExposure(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: superview ?? self)
        let location = gesture.location(in: superview ?? self)
        let start = CGPoint(x: location.x - translation.x, y: location.y - translation.y)
        switch gesture.state {
        case .began:
            let velocity = gesture.velocity(in: self)
            exposurePanActive =
                abs(velocity.y) > abs(velocity.x) || CameraExposureGesture.isVerticalDrag(translation)
            if exposurePanActive { exposureDragged?(translation.y, start, false) }
        case .changed:
            if !exposurePanActive { exposurePanActive = CameraExposureGesture.isVerticalDrag(translation) }
            if exposurePanActive { exposureDragged?(translation.y, start, false) }
        case .ended, .cancelled, .failed:
            if exposurePanActive { exposureDragged?(translation.y, start, true) }
            exposurePanActive = false
        default: break
        }
    }
    @objc private func didTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        if let id = markerViews.filter({ !$0.value.isHidden && $0.value.frame.contains(point) })
            .min(by: { hypot($0.value.center.x - point.x, $0.value.center.y - point.y)
                < hypot($1.value.center.x - point.x, $1.value.center.y - point.y) })?.key,
            let onSelectMarker { onSelectMarker(id); return }
        tapped?(convert(point, to: superview))
    }
    @objc private func didHold(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { held?(convert(gesture.location(in: self), to: superview)) }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        updateViewport()
    }
    func updateViewport() {
        let orientation = window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
        if let connection = preview.connection, connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
        }
        viewportChanged?(bounds.size, orientation)
    }
}
