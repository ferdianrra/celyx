//
//  ConstellationFiguresView.swift
//  celyx
//
//  Created by Ferdiansyah Annora on 02/11/26.
//
import SwiftUI
import simd

struct ConstellationFiguresView: View {
    let model: HomeViewModel
    let size: CGSize
    var body: some View {
        let projections = ConstellationFigureProjection.project(
            model.constellationFigures,visibleIDs:model.visibleConstellationIDs,scene:model.scene,size:size)
        // Resolve at most two PNGs. The cache is bounded; never decode all 85 images per frame.
        let drawings = projections.compactMap { projection -> (ProjectedConstellationFigure,UIImage)? in
            guard let image = ConstellationFigureImages.image(for:projection.figure) else { return nil }
            return (projection,image)
        }
        Canvas { context,canvasSize in
            context.clip(to:skyClip(size:canvasSize,altitude:model.scene.altitude,fieldOfView:model.scene.fieldOfView),style:FillStyle(eoFill:true))
            context.blendMode = .plusLighter
            for (projection,image) in drawings {
                var layer = context
                layer.opacity = projection.opacity
                layer.concatenate(projection.transform)
                layer.draw(Image(uiImage:image),in:CGRect(x:0,y:0,width:projection.figure.definition.size[0],height:projection.figure.definition.size[1]))
            }
        }
        .opacity(1-model.detailVisualProgress)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // The horizon is a circle (or half-plane) in stereographic projection.
    // Clip above 9° to keep the artwork off the decorative island silhouettes.
    private func skyClip(size: CGSize,altitude: Double,fieldOfView: Double) -> Path {
        let minimumAltitude = 9.0 * .pi/180
        let a = sin(altitude)+sin(minimumAltitude)
        let focal = CameraProjection.focalLength(width:size.width,height:size.height,fieldOfView:fieldOfView)
        if abs(a) < 0.0001 {
            let edge = size.height*0.47-focal*(sin(minimumAltitude)-sin(altitude))/cos(altitude)
            return Path(CGRect(x:0,y:0,width:size.width,height:max(0,edge)))
        }
        let radius = 2*focal*cos(minimumAltitude)/abs(a)
        let centerY = size.height*0.47-2*focal*cos(altitude)/a
        let disk = CGRect(x:size.width*0.5-radius,y:centerY-radius,width:radius*2,height:radius*2)
        var path = Path()
        if a < 0 { path.addRect(CGRect(origin:.zero,size:size)) }
        path.addEllipse(in:disk)
        return path
    }
}

@MainActor
private enum ConstellationFigureImages {
    private static let cache: NSCache<NSString,UIImage> = {
        let cache = NSCache<NSString,UIImage>()
        cache.countLimit = 6
        cache.totalCostLimit = 6*512*512*4
        return cache
    }()
    static func image(for figure: ConstellationFigure) -> UIImage? {
        let key = figure.definition.file as NSString
        if let image = cache.object(forKey:key) { return image }
        let file = URL(fileURLWithPath:figure.definition.file)
        guard let url = try? SkyAssets.url(file.deletingPathExtension().lastPathComponent,extension:file.pathExtension),
              let image = UIImage(contentsOfFile:url.path) else { return nil }
        cache.setObject(image,forKey:key,cost:Int(image.size.width*image.size.height*4))
        return image
    }
}

#Preview("Constellation artwork") {
    let model = HomeViewModel.preview()
    model.quality = .dark
    if let figure = model.constellationFigures.first(where: { $0.id == "And" }), let sky = model.snapshot {
        let d = sky.basis*figure.center
        model.scene.azimuth = atan2(d.x,d.y); model.scene.altitude = asin(d.z)
    }
    return HomeView(model:model)
}
