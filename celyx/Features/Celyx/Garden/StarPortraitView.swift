import SwiftUI

struct StarPortraitView: View {
    let star: CatalogStar
    var solarAltitude: Double = 60
    var body: some View {
        let rgb = star.rgb
        let color = Color(red:rgb.x,green:rgb.y,blue:rgb.z)
        Group {
            if star.isSun {
                SunPortraitView(altitude:solarAltitude)
            } else if star.isPlanet {
                Circle().fill(RadialGradient(colors:[color,.black.opacity(0.9)],center:.init(x:0.3,y:0.25),startRadius:0,endRadius:80))
                    .padding(9)
            } else if star.isMoon {
                Image("StarSurface").resizable().scaledToFit().saturation(0)
                    .colorMultiply(Color(white:0.86)).clipShape(Circle()).padding(9)
            } else if let portrait = GardenBodyAssets.portrait(star) {
                Image(uiImage:portrait).resizable().scaledToFit()
            } else {
                ZStack {
                    Circle().fill(RadialGradient(colors:[color.opacity(0.9),color.opacity(0.3),.clear],center:.center,startRadius:0,endRadius:65))
                    Image("StarSurface").resizable().scaledToFit()
                        .saturation(0).colorMultiply(color).clipShape(Circle()).blendMode(.screen)
                        .padding(9)
                }
            }
        }
        .accessibilityLabel(star.isSun ? "Illustration of the Sun" : star.isMoon ? "Illustration of the Moon" : star.isPlanet ? "Illustration of \(star.title)" : "Illustration of \(star.title), color based on the star catalog")
    }
}

// A continuous glowing disc, with warmer light when the Sun is near the horizon.
private struct SunPortraitView: View {
    let altitude: Double
    private var sunlight: Color { altitude < 10 ? Color(red:1,green:0.48,blue:0.16) : Color(red:1,green:0.95,blue:0.78) }
    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width,geometry.size.height)
            ZStack {
                Circle().fill(RadialGradient(stops:[
                    .init(color:sunlight.opacity(0.5),location:0),
                    .init(color:sunlight.opacity(0.18),location:0.45),
                    .init(color:.clear,location:1)
                ],center:.center,startRadius:0,endRadius:diameter*0.5))
                Circle().fill(RadialGradient(colors:[.white,sunlight,sunlight.opacity(0.8)],
                    center:.center,startRadius:0,endRadius:diameter*0.3))
                    .frame(width:diameter*0.56,height:diameter*0.56)
                    .shadow(color:sunlight.opacity(0.7),radius:diameter*0.07)
            }
            .frame(width:geometry.size.width,height:geometry.size.height)
        }
    }
}

#Preview("Star portrait") {
    StarPortraitView(star:AppPreviewData.star).frame(width:160,height:160).padding().background(CelyxColor.night)
}

#Preview("Sun portrait") {
    SunPortraitView(altitude:5).frame(width:160,height:160).padding().background(CelyxColor.night)
}
