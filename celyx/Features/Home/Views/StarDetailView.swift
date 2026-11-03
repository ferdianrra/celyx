//
//  StarDetailView.swift
//  celyx
//
//  Created by Ferdiansyah Annora on 02/11/26.
//
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
            } else if star.isMoon {
                Image("StarSurface").resizable().scaledToFit().saturation(0)
                    .colorMultiply(Color(white:0.86)).clipShape(Circle()).padding(9)
            } else {
                ZStack {
                    Circle().fill(RadialGradient(colors:[color.opacity(0.9),color.opacity(0.3),.clear],center:.center,startRadius:0,endRadius:65))
                    Image("StarSurface").resizable().scaledToFit()
                        .saturation(0).colorMultiply(color).clipShape(Circle()).blendMode(.screen)
                        .padding(9)
                }
            }
        }
        .accessibilityLabel(star.isSun ? "Illustration of the Sun" : star.isMoon ? "Illustration of the Moon" : "Illustration of \(star.title), color based on the star catalog")
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

struct StarDetailView: View {
    @Bindable var model: HomeViewModel
    var onClose: (() -> Void)? = nil
    var identificationNote: String? = nil
    var showsFindAction = true
    var onCameraCollect: (() -> Void)? = nil
    var cameraCollectTitle = "Collect"
    var body: some View {
        ScrollView {
            if let star = model.selectedStar {
                let observation = model.selectedObservation
                let isCollected = model.collected[star.id] != nil
                VStack(alignment:.leading,spacing:18) {
                    HStack(spacing:10) {
                        StarPortraitView(star:star,solarAltitude:model.sunObservation?.altitude ?? 60).frame(width:64,height:64)
                        VStack(alignment:.leading,spacing:4) {
                            Text(star.title).font(.title2.bold())
                            Text(star.isSun ? "Our nearest star" : star.isMoon ? "Earth’s natural satellite" : "Star in \(model.constellationName(star))").font(.subheadline).foregroundStyle(.white.opacity(0.65))
                        }
                        Spacer()
                        Button { if let onClose { onClose() } else { model.closeDetail() } } label: { Image(systemName:"xmark").padding(9).background(.white.opacity(0.12),in:Circle()) }
                            .accessibilityLabel("Close details")
                    }
                    if let identificationNote {
                        Text(identificationNote).font(.footnote).foregroundStyle(.orange)
                    }
                    if onCameraCollect != nil {
                        Label("Light detected in your camera",systemImage:"camera.fill").font(.footnote).foregroundStyle(.green)
                    } else {
                    Label(observation?.reason ?? "Turn on location to find its position",systemImage:observation?.likelyVisible == true ? "circle.fill" : "info.circle")
                        .font(.footnote).foregroundStyle(observation?.likelyVisible == true ? .green : .white.opacity(0.75))
                    }
                    Button {
                        if let onCameraCollect { onCameraCollect() }
                        else { model.collectInCamera() }
                    } label: {
                        Text(onCameraCollect != nil ? cameraCollectTitle : "Capture in Camera").fontWeight(.semibold).frame(maxWidth:.infinity).padding(.vertical,14)
                    }
                    .buttonStyle(.plain).foregroundStyle(Color(red:0.04,green:0.06,blue:0.18))
                    .background(.white.opacity((onCameraCollect != nil || model.location != nil) ? 1:0.45),in:Capsule())
                    .disabled(onCameraCollect == nil && model.location == nil)
                    .accessibilityIdentifier("collect-star")
                    Text(onCameraCollect != nil ? "Your photo is ready. Add a note and keep this moment." : isCollected ? "Saved to your collection." : "Open the camera to capture and save what you see.")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                    if showsFindAction {
                        Button { model.findSelectedInSky() } label: {
                            Label("Find in the Sky",systemImage:"camera.viewfinder")
                                .frame(maxWidth:.infinity).padding(.vertical,8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white).foregroundStyle(.black)
                        .disabled(model.location == nil)
                        .accessibilityIdentifier("find-in-sky")
                        Text(model.location == nil ? "Turn on location to find it in the sky." : "Follow the arrow to find \(star.title).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Divider().overlay(.white.opacity(0.15))
                    if let observation {
                        HStack {
                            fact("Altitude",String(format:"%.1f°",observation.altitude))
                            Spacer()
                            fact("Direction",String(format:"%@ · %.1f°",observation.bearing,observation.azimuth))
                        }
                        HStack {
                            fact("Magnitude",String(format:"%.2f",star.mag))
                            if !star.isSolarSystemBody {
                                Spacer()
                                fact("With atmosphere",String(format:"%.2f mag",observation.dimmedMagnitude))
                            }
                        }
                    }
                    if !star.isSolarSystemBody {
                        HStack {
                            fact("Distance",star.distance_ly.map { String(format:"%.0f light-years",$0) } ?? "Not available")
                            Spacer()
                            fact("Estimated temperature",star.temperature.map { String(format:"≈ %.0f K",$0) } ?? "Not available")
                        }
                        Text("You’ll find \(star.title) in \(model.constellationName(star)). A lower magnitude means a brighter star. Its position follows your location and the current time.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                        Text("This is an illustration, with its color based on the star catalog. Distance and brightness come from HYG; temperature is an estimate.")
                            .font(.caption).foregroundStyle(.white.opacity(0.55))
                    } else if star.isMoon {
                        Text("The Moon’s position follows your location and the current time.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                    } else {
                        Text("The Sun’s position follows your location and the current time. Spot it in the camera to save the moment.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                    }
                    Text("Forecasts can’t tell exactly what you can see from where you’re standing. \(model.onlineConditions ? "Weather: Open-Meteo / CAMS." : "Live weather is off.")")
                        .font(.caption).foregroundStyle(.white.opacity(0.55))
                }.padding(20)
            }
        }
        .foregroundStyle(.white)
        .background(LinearGradient(colors:[Color(red:0.12,green:0.25,blue:0.68),Color(red:0.025,green:0.035,blue:0.12)],startPoint:.top,endPoint:.bottom))
        .preferredColorScheme(.dark)
    }
    private func fact(_ name: String,_ value: String) -> some View {
        VStack(alignment:.leading,spacing:4) { Text(name).font(.caption).foregroundStyle(.white.opacity(0.55)); Text(value).font(.subheadline.weight(.medium)) }
    }
}

#Preview("Star illustration",traits:.sizeThatFitsLayout) {
    let model = HomeViewModel.preview()
    if let star = model.stars.first { StarPortraitView(star:star).frame(width:160,height:160).background(.black) }
}
#Preview("Star detail") {
    let model = HomeViewModel.preview()
    model.selectedStar = model.nearby.first?.star
    return StarDetailView(model:model)
}
