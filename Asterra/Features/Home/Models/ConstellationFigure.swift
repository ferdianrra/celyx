//
//  ConstellationFigure.swift
//  celyx
//
//  Created by Ferdiansyah Annora on 02/11/26.
//
import Foundation
import CoreGraphics
import simd

struct ConstellationFigure: Identifiable {
    struct Anchor: Decodable {
        let pixel: [Double]
        let ra_deg: Double
        let dec_deg: Double
        var equatorial: SIMD3<Double> {
            let ra = ra_deg * .pi/180, dec = dec_deg * .pi/180
            return SIMD3(cos(dec)*cos(ra),cos(dec)*sin(ra),sin(dec))
        }
    }
    struct Definition: Decodable {
        let file: String
        let size: [Double]
        let anchors: [Anchor]
    }
    let id: String
    let definition: Definition
    let center: SIMD3<Double>

    static func load() throws -> [ConstellationFigure] {
        let data = try Data(contentsOf:SkyAssets.url("figures",extension:"json"))
        let entries = try JSONDecoder().decode([String:Definition].self,from:data)
        return entries.sorted { $0.key < $1.key }.compactMap { id,definition in
            guard definition.anchors.count == 3, definition.size.count == 2,
                  definition.size.allSatisfy({ $0.isFinite && $0 > 0 }),
                  definition.anchors.allSatisfy({ $0.pixel.count == 2 && $0.pixel.allSatisfy(\.isFinite) && $0.ra_deg.isFinite && $0.dec_deg.isFinite }) else { return nil }
            let sum = definition.anchors.reduce(SIMD3<Double>.zero) { $0+$1.equatorial }
            guard simd_length(sum) > 0.01 else { return nil }
            return ConstellationFigure(id:id,definition:definition,center:simd_normalize(sum))
        }
    }
}

struct ProjectedConstellationFigure: Identifiable {
    let figure: ConstellationFigure
    let transform: CGAffineTransform
    let opacity: Double
    var id: String { figure.id }
}

enum ConstellationFigureProjection {
    // Match three asset pixels to the projected anchor stars, not to a fixed HUD position.
    static func affine(source: [CGPoint], target: [CGPoint]) -> CGAffineTransform? {
        guard source.count == 3, target.count == 3 else { return nil }
        let s1 = CGPoint(x:source[1].x-source[0].x,y:source[1].y-source[0].y)
        let s2 = CGPoint(x:source[2].x-source[0].x,y:source[2].y-source[0].y)
        let t1 = CGPoint(x:target[1].x-target[0].x,y:target[1].y-target[0].y)
        let t2 = CGPoint(x:target[2].x-target[0].x,y:target[2].y-target[0].y)
        let determinant = s1.x*s2.y-s2.x*s1.y
        guard abs(determinant) > 0.001, abs(t1.x*t2.y-t2.x*t1.y) > 0.01 else { return nil }
        let a = (t1.x*s2.y-t2.x*s1.y)/determinant
        let c = (t2.x*s1.x-t1.x*s2.x)/determinant
        let b = (t1.y*s2.y-t2.y*s1.y)/determinant
        let d = (t2.y*s1.x-t1.y*s2.x)/determinant
        let tx = target[0].x-a*source[0].x-c*source[0].y
        let ty = target[0].y-b*source[0].x-d*source[0].y
        guard [a,b,c,d,tx,ty].allSatisfy(\.isFinite) else { return nil }
        return CGAffineTransform(a:a,b:b,c:c,d:d,tx:tx,ty:ty)
    }

    static func project(_ figures: [ConstellationFigure], visibleIDs: Set<String>, scene: SkySceneState, size: CGSize) -> [ProjectedConstellationFigure] {
        guard scene.showsConstellationFigures, scene.hasLocation,
              scene.renderedCloudCover < 75, size.width > 0, size.height > 0 else { return [] }
        let basis = simd_double3x3(columns:(scene.equatorialX,scene.equatorialY,scene.equatorialZ))
        let az = scene.azimuth, alt = scene.altitude
        let forward = SIMD3(sin(az)*cos(alt),cos(az)*cos(alt),sin(alt))
        let right = SIMD3(cos(az),-sin(az),0.0), up = simd_cross(right,forward)
        let focal = CameraProjection.focalLength(width:size.width,height:size.height,fieldOfView:scene.fieldOfView)
        let inner = 12.0 * .pi/180, outer = 22.0 * .pi/180
        let candidates = figures.filter { visibleIDs.contains($0.id) }.sorted {
            simd_dot(basis*$0.center,forward) > simd_dot(basis*$1.center,forward)
        }
        return candidates.compactMap { figure -> ProjectedConstellationFigure? in
            let center = basis*figure.center
            let angle = acos(min(1,max(-1,simd_dot(center,forward))))
            guard angle < outer, center.z > sin(9 * .pi/180) else { return nil }
            var targets: [CGPoint] = []
            for anchor in figure.definition.anchors {
                let d = basis*anchor.equatorial
                guard d.z > 0, let p = CameraProjection.project(direction:SIMD3(simd_dot(d,right),simd_dot(d,up),simd_dot(d,forward)),focal:focal) else { return nil }
                targets.append(CGPoint(x:size.width*0.5+p.x,y:size.height*0.47-p.y))
            }
            let source = figure.definition.anchors.map { CGPoint(x:$0.pixel[0],y:$0.pixel[1]) }
            guard let transform = affine(source:source,target:targets) else { return nil }
            let bounds = CGRect(x:0,y:0,width:figure.definition.size[0],height:figure.definition.size[1]).applying(transform)
            guard bounds.intersects(CGRect(origin:.zero,size:size)), bounds.width < size.width*8, bounds.height < size.height*8 else { return nil }
            let t = min(1,max(0,(outer-angle)/(outer-inner)))
            let fade = t*t*(3-2*t)
            let altitude = asin(center.z)*180 / .pi
            let h = min(1,max(0,(altitude-9)/7))
            let horizonFade = h*h*(3-2*h)
            return ProjectedConstellationFigure(figure:figure,transform:transform,opacity:0.68*fade*horizonFade)
        }.prefix(2).map { $0 }
    }
}
