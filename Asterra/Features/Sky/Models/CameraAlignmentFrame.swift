import UIKit
import simd

struct CameraAlignmentFrame {
    let generation: Int
    let image: UIImage
    let size: CGSize
    let date: Date
    let location: ObserverLocation
    let view: simd_float4x4
    let projection: simd_float4x4
}
