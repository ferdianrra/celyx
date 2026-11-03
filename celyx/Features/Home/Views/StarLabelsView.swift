//
//  StarLabelsView.swift
//  celyx
//
//  Created by Ferdiansyah Annora on 02/11/26.
//
import SwiftUI
import simd

struct StarLabelsView: View {
    let model: HomeViewModel
    let size: CGSize
    private struct Label: Identifiable {
        let observation: StarObservation
        let point: CGPoint
        var id: Int { observation.id }
    }
    private var labels: [Label] {
        let az = model.scene.azimuth, alt = model.scene.altitude
        let forward = SIMD3(sin(az)*cos(alt),cos(az)*cos(alt),sin(alt))
        let right = SIMD3(cos(az),-sin(az),0.0), up = simd_cross(right,forward)
        let focal = CameraProjection.focalLength(width:size.width,height:size.height,fieldOfView:model.scene.fieldOfView)
        var result: [Label] = []
        let stars = model.scene.showsStars ? model.displayedObservations.filter { $0.star.hasCommonName } : []
        let sun = [model.sunObservation,model.moonObservation].compactMap { $0 }.filter { $0.altitude > 0 }
        let candidates = (sun + stars).sorted {
            simd_dot($0.direction,forward) > simd_dot($1.direction,forward)
        }
        for observation in candidates {
            let d = observation.direction
            guard simd_dot(d,forward) > cos(22 * .pi/180),
                  let p = CameraProjection.project(direction:SIMD3(simd_dot(d,right),simd_dot(d,up),simd_dot(d,forward)),focal:focal) else { continue }
            let point = CGPoint(x:size.width*0.5+p.x,y:size.height*0.47-p.y)
            guard point.x > 55, point.x < size.width-55, point.y > 120, point.y < size.height-180,
                  !result.contains(where:{ hypot($0.point.x-point.x,$0.point.y-point.y) < 66 }) else { continue }
            result.append(Label(observation:observation,point:point))
            if result.count == 5 { break }
        }
        return result
    }
    private var selectedPoint: CGPoint? {
        guard let direction = model.selectedObservation?.direction else { return nil }
        let az = model.scene.azimuth, alt = model.scene.altitude
        let forward = SIMD3(sin(az)*cos(alt),cos(az)*cos(alt),sin(alt))
        let right = SIMD3(cos(az),-sin(az),0.0), up = simd_cross(right,forward)
        let focal = CameraProjection.focalLength(width:size.width,height:size.height,fieldOfView:model.scene.fieldOfView)
        guard let point = CameraProjection.project(direction:SIMD3(simd_dot(direction,right),simd_dot(direction,up),simd_dot(direction,forward)),focal:focal) else { return nil }
        return CGPoint(x:size.width*0.5+point.x,y:size.height*0.47-point.y)
    }
    var body: some View {
        ZStack {
            ForEach(labels) { label in
                Button { model.showDetail(label.observation.star) } label: {
                    VStack(spacing:5) {
                        if label.observation.star.isSolarSystemBody {
                            Color.clear.frame(width:44,height:44)
                        } else {
                            Circle().fill(.white.opacity(0.16)).frame(width:28,height:28)
                                .overlay(Circle().stroke(.white.opacity(0.45),lineWidth:0.6))
                        }
                        Text(label.observation.star.title).font(.system(size:12,weight:.medium))
                            .shadow(color:.black,radius:4).padding(.horizontal,7).padding(.vertical,3)
                            .background(.black.opacity(0.25),in:Capsule())
                    }
                    .foregroundStyle(.white).frame(minWidth:60,minHeight:52)
                }
                .buttonStyle(.plain)
                .position(x:label.point.x,y:label.point.y+12)
                .accessibilityLabel("Detail \(label.observation.star.title)")
                .accessibilityIdentifier("star-label-\(label.id)")
                .opacity(1-model.detailVisualProgress)
                .allowsHitTesting(!model.isInspectingStar)
                .accessibilityHidden(model.isInspectingStar)
            }
            if model.detailVisualProgress > 0, let star = model.selectedStar, !star.isSun,
               let point = selectedPoint {
                let progress = model.detailVisualProgress
                StarPortraitView(star:star).frame(width:2+128*progress,height:2+128*progress)
                    .opacity(min(1,progress*2))
                    .position(point).allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

#Preview("Star labels") {
    let model = HomeViewModel.preview()
    GeometryReader { geometry in
        StarLabelsView(model:model,size:geometry.size).background(Color(red:0.03,green:0.02,blue:0.1))
    }
}
