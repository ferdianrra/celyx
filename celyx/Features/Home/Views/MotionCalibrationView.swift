import SwiftUI

struct MotionCalibrationView: View {
    let model: HomeViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stage: MotionCalibrationStage { model.motionCalibrationStage }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                Text("Let’s find north").font(.title3.bold())
                HStack(spacing:8) {
                    step("Location",done:stage != .location && stage != .blocked)
                    step("Compass",done:stage == .settling || stage == .ready)
                    step("Ready",done:stage == .ready)
                }
                Text(model.motionStatus).font(.subheadline).fixedSize(horizontal:false,vertical:true)
                if stage == .compass {
                    compassMovement
                    Text("1. Hold your phone in front of you, screen facing you.\n2. Move the whole phone along the ∞ path, tilting it gently from side to side. Repeat 2–3 times.\n3. When we’ve found north, hold still, then point the back camera at the sky.")
                        .font(.footnote).fixedSize(horizontal:false,vertical:true)
                    Text("You don’t need to turn your body. Move away from cars, speakers, or metal fences, and remove magnetic accessories if you can.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if stage == .settling {
                    Label("Hold your phone comfortably for about a second.",systemImage:"iphone")
                        .font(.footnote)
                } else {
                    Label("Allow location access while using the app so we can show the sky where you are.",systemImage:"location")
                        .font(.footnote)
                }
                ProgressView(value:model.motionCalibrationProgress)
                Text("We’ll finish automatically when your compass is ready. The direction is a guide, so it may still be a little off.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Use Touch") { model.setMode(.touch) }.buttonStyle(.bordered)
                    if stage == .location || stage == .blocked {
                        Button("Open Settings") {
                            if let url = URL(string:UIApplication.openSettingsURLString) { openURL(url) }
                        }.buttonStyle(.borderedProminent)
                    } else {
                        Button("Try Again") { model.recalibrateMotion() }.buttonStyle(.bordered)
                    }
                }
            }
            .padding(24)
        }
        .fixedSize(horizontal:false,vertical:true)
        .frame(maxWidth:350,maxHeight:620)
        .background(.regularMaterial,in:RoundedRectangle(cornerRadius:24))
        .padding(20)
    }
    private func step(_ title: String,done: Bool) -> some View {
        HStack(spacing:5) {
            Circle().fill(done ? Color.green : Color.white.opacity(0.3)).frame(width:6,height:6)
            Text(title).font(.caption)
        }
        .padding(.horizontal,9).padding(.vertical,6)
        .background(.white.opacity(0.07),in:Capsule())
    }
    private var compassMovement: some View {
        TimelineView(.animation(minimumInterval:1/30,paused:reduceMotion)) { context in
            let t = reduceMotion ? Double.pi/4 : context.date.timeIntervalSinceReferenceDate * 1.5
            ZStack {
                Path { path in
                    for i in 0...160 {
                        let angle = Double(i)/160 * 2 * .pi
                        let point = CGPoint(x:140+100*sin(angle),y:52+29*sin(2*angle))
                        if i == 0 { path.move(to:point) } else { path.addLine(to:point) }
                    }
                }.stroke(.white.opacity(0.25),style:StrokeStyle(lineWidth:2,dash:[4,5]))
                Image(systemName:"iphone")
                    .font(.system(size:34)).foregroundStyle(.white)
                    .rotationEffect(.degrees(sin(t)*25))
                    .position(x:140+100*sin(t),y:52+29*sin(2*t))
            }
            .frame(width:280,height:104).frame(maxWidth:.infinity)
        }
        .accessibilityLabel("Move your whole phone in a sideways figure eight, gently tilting it left and right.")
    }
}
