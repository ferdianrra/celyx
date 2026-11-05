import SwiftUI
import MapKit

struct VisibilityMapCanvas: UIViewRepresentable {
    let raster: VisibilityRaster?
    let selected: ViewingCoordinate?
    let selectedName: String
    let greatest: ViewingCoordinate?
    let focus: ViewingCoordinate?
    let onSelect: (ViewingCoordinate) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle:.flat,emphasisStyle:.muted)
        map.pointOfInterestFilter = .excludingAll
        map.setVisibleMapRect(.world,edgePadding:UIEdgeInsets(top:12,left:12,bottom:12,right:12),animated:false)
        map.addGestureRecognizer(UITapGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.tapped(_:))))
        return map
    }
    func updateUIView(_ map: MKMapView,context: Context) {
        context.coordinator.parent = self
        if let raster, context.coordinator.overlay == nil, let overlay = CoverageOverlay(raster:raster) {
            context.coordinator.overlay = overlay; map.addOverlay(overlay,level:.aboveRoads)
        }
        let key = "\(selected?.label ?? "")/\(greatest?.label ?? "")/\(selectedName)"
        if context.coordinator.annotationKey != key {
            context.coordinator.annotationKey = key
            map.removeAnnotations(map.annotations)
            if let greatest {
                let annotation = MKPointAnnotation(); annotation.coordinate = greatest.mapCoordinate
                annotation.title = "Greatest eclipse (catalog)"; map.addAnnotation(annotation)
            }
            if let selected {
                let annotation = MKPointAnnotation(); annotation.coordinate = selected.mapCoordinate
                annotation.title = selectedName; map.addAnnotation(annotation)
            }
        }
        if let focus, context.coordinator.lastFocus != focus {
            context.coordinator.lastFocus = focus
            map.setRegion(MKCoordinateRegion(center:focus.mapCoordinate,latitudinalMeters:1_500_000,longitudinalMeters:1_500_000),animated:true)
        }
    }
    static func dismantleUIView(_ uiView: MKMapView,coordinator: Coordinator) { uiView.delegate = nil }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: VisibilityMapCanvas
        var overlay: CoverageOverlay?
        var lastFocus: ViewingCoordinate?
        var annotationKey = ""
        init(_ parent: VisibilityMapCanvas) { self.parent = parent }
        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            let point = map.convert(gesture.location(in:map),toCoordinateFrom:map)
            parent.onSelect(.init(latitude:point.latitude,longitude:point.longitude))
        }
        func mapView(_ mapView: MKMapView,rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            if let coverage = overlay as? CoverageOverlay { return CoverageRenderer(overlay:coverage) }
            return MKOverlayRenderer(overlay:overlay)
        }
    }
}

final class CoverageOverlay: NSObject, MKOverlay {
    let coordinate = CLLocationCoordinate2D(latitude:0,longitude:0)
    let boundingMapRect = MKMapRect.world
    let image: CGImage
    init?(raster: VisibilityRaster) {
        guard let provider = CGDataProvider(data:raster.rgba as CFData), let image = CGImage(width:raster.width,height:raster.height,
            bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:raster.width*4,space:CGColorSpaceCreateDeviceRGB(),
            bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent) else { return nil }
        self.image = image
    }
}
final class CoverageRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect,zoomScale: MKZoomScale,in context: CGContext) {
        guard let overlay = overlay as? CoverageOverlay else { return }
        let bounds = rect(for:overlay.boundingMapRect)
        context.saveGState()
        context.translateBy(x:bounds.minX,y:bounds.maxY); context.scaleBy(x:1,y:-1)
        context.interpolationQuality = .medium
        context.draw(overlay.image,in:CGRect(origin:.zero,size:bounds.size))
        context.restoreGState()
    }
}
extension ViewingCoordinate {
    var mapCoordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude:latitude,longitude:longitude) }
}
