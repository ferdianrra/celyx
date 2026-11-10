//
//  CameraProjection.swift
//  celyx
//
//  Created by Ferdiansyah Annora on 02/11/26.
//

import Foundation
import simd

// CPU counterpart of the conformal projection shared by background and GPU stars.
// Camera-space X is right, Y is up and Z is forward.
enum CameraProjection {
    static func focalLength(width: Double, height: Double, fieldOfView: Double) -> Double {
        min(width, height) * 0.62 / tan(fieldOfView * .pi / 360)
    }
    static func ray(offset: SIMD2<Double>, focal: Double) -> SIMD3<Double> {
        let q = offset / (2 * focal)
        let lengthSquared = simd_dot(q, q)
        return SIMD3(2 * q.x, 2 * q.y, 1 - lengthSquared) / (1 + lengthSquared)
    }
    static func project(direction: SIMD3<Double>, focal: Double) -> SIMD2<Double>? {
        guard direction.z > -0.9 else { return nil }
        return SIMD2(direction.x, direction.y) * (2 * focal / (1 + direction.z))
    }
}
