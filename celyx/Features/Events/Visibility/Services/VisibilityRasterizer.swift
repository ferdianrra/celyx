import Foundation

/// Web-Mercator coverage, with geometry evaluated at every sample's actual latitude/longitude.
/// Rendering uses no ephemeris caches and can run off the UI thread.
enum VisibilityRasterizer {
    nonisolated static func render(_ geometry: EventVisibilityGeometry,size: Int = 768) throws -> VisibilityRaster {
        var pixels = [UInt8](repeating:0,count:size*size*4)
        let minimumSine = sin(geometry.minimumAltitude * .pi/180)
        let maximumSunSine = sin(geometry.maximumSunAltitude * .pi/180)
        for y in 0..<size {
            if y%8 == 0 { try Task.checkCancellation() }
            let mercator = Double.pi*(1-2*(Double(y)+0.5)/Double(size))
            let latitude = atan(sinh(mercator))*180 / .pi
            for x in 0..<size {
                let longitude = (Double(x)+0.5)/Double(size)*360-180
                if geometry.matches(.init(latitude:latitude,longitude:longitude),minimumSine:minimumSine,maximumSunSine:maximumSunSine) {
                    let i = (y*size+x)*4
                    // Premultiplied sRGB, green; this is geometry, not a weather forecast.
                    pixels[i] = 12; pixels[i+1] = 104; pixels[i+2] = 63; pixels[i+3] = 120
                }
            }
        }
        return VisibilityRaster(width:size,height:size,rgba:Data(pixels))
    }
}
