import SwiftUI
import ARKit
import simd

/// Separate calibration step: aim the circle at a sky object whose true position we know from GPS + clock
/// (the Sun by day, the Moon, a bright planet or star at night). The difference between that true
/// direction and where the phone's compass says it's pointing is saved and removed everywhere.
struct SkyCalibrationView: View {
    let catalogue: [CatalogStar]
    let onClose: () -> Void

    struct Target: Identifiable, Equatable {
        let id: Int
        let name: String
        let direction: SIMD3<Double>   // true, apparent (refracted) direction [east, north, up]
        let isDisc: Bool
        var azimuth: Double { atan2(direction.x,direction.y) }
        var altitude: Double { asin(min(1,max(-1,direction.z))) }
    }
    enum Outcome: Equatable { case none, saved(String), failed(String) }

    @State private var session = ARSession()
    @State private var motion: MotionService?
    @State private var location: ObserverLocation?
    @State private var attitude: simd_double3x3?
    @State private var motionMessage: String?
    @State private var targets: [Target] = []
    @State private var selectedID: Int?
    @State private var viewSize: CGSize = .zero
    @State private var outcome: Outcome = .none
    @State private var cameraDenied = false
    @Environment(\.scenePhase) private var phase

    private var target: Target? { targets.first(where:{ $0.id == selectedID }) ?? targets.first }

    var body: some View {
        ZStack(alignment:.bottom) {
            GeometryReader { geometry in
                ZStack {
                    SkyCameraPreview(session:session,onViewport:{ _,_ in })
                    CrosshairView(state:.default,soundEnabled:false,hapticsEnabled:false,idleLoops:false)
                        .position(x:geometry.size.width/2,y:geometry.size.height/2+10)
                        .accessibilityHidden(true)
                }
                .onAppear { viewSize = geometry.size }
                .onChange(of:geometry.size) { _, value in viewSize = value }
            }
            .ignoresSafeArea()

            VStack {
                HStack(alignment:.top) {
                    CelyxBackButton(action:close)
                    Spacer()
                }
                .padding(.leading,20)
                Spacer()
            }

            panel
                .padding(.horizontal,6).padding(.bottom,6)
                .ignoresSafeArea(edges:.bottom)
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .task { await start() }
        .task(id:location?.coordinateLabel) {
            while !Task.isCancelled {
                refreshTargets()
                try? await Task.sleep(for:.seconds(5))
            }
        }
        .onDisappear(perform:stop)
        .onChange(of:phase) { _, value in
            if value == .active { runSession() } else { session.pause() }
        }
    }

    // MARK: Panel

    private var panel: some View {
        ZStack(alignment:.top) {
            CelyxBluePanel(cornerRadius:34)
            CelyxGrabber()
            VStack(alignment:.leading,spacing:14) {
                HStack {
                    VStack(alignment:.leading,spacing:4) {
                        Text("Calibrate direction").font(.system(size:22,weight:.bold)).foregroundStyle(CelyxColor.primaryLabel)
                        Text(instruction).font(.system(size:13)).foregroundStyle(CelyxColor.secondaryLabel)
                            .fixedSize(horizontal:false,vertical:true)
                    }
                    Spacer(minLength:0)
                }
                if targets.count > 1 {
                    ScrollView(.horizontal,showsIndicators:false) {
                        HStack(spacing:8) {
                            ForEach(targets) { item in
                                Button { selectedID = item.id; outcome = .none } label: {
                                    Text(item.name).font(.system(size:13,weight:.medium)).foregroundStyle(.white)
                                        .padding(.horizontal,12).frame(height:32)
                                }
                                .buttonStyle(.plain)
                                .glassEffect(item.id == target?.id ? .regular.tint(.white.opacity(0.3)).interactive() : .regular.interactive(),in:Capsule())
                            }
                        }
                    }
                }
                TimelineView(.periodic(from:.now,by:0.2)) { _ in readout }
                statusLine
                HStack(spacing:10) {
                    CelyxPillButton(title:"It’s in the circle",style:target == nil ? .disabled : .primary,action:calibrate)
                    if SkyCalibration.isCalibrated {
                        Button("Reset") { SkyCalibration.reset(); outcome = .none }
                            .font(.system(size:15,weight:.semibold)).foregroundStyle(.white)
                            .padding(.horizontal,16).frame(height:48)
                            .glassEffect(.regular.interactive(),in:Capsule())
                    }
                }
            }
            .padding(.horizontal,20).padding(.top,28).padding(.bottom,22)
        }
        .fixedSize(horizontal:false,vertical:true)
    }

    private var instruction: String {
        if cameraDenied { return "Allow camera access in Settings to calibrate." }
        guard location != nil else { return "Finding your location…" }
        guard let target else { return "Nothing bright enough is up right now. Try again when the Sun, Moon or a bright star is visible." }
        let safety = target.id == CatalogStar.sun.id ? " Aim with the screen; never look straight at the Sun." : ""
        return "Hold your phone upright, put \(target.name) in the circle, hold still, then tap the button.\(safety)"
    }

    /// Live numbers: where the target really is vs. where each sensor thinks the phone points.
    @ViewBuilder private var readout: some View {
        if let target {
            let ar = arAim()
            VStack(alignment:.leading,spacing:4) {
                row("\(target.name) is at",String(format:"%.0f°  ·  %.0f° up",degrees(target.azimuth),target.altitude*180 / .pi))
                if let ar {
                    let turn = SkyCalibration.wrap(target.azimuth-(ar.azimuth+SkyCalibration.arHeadingOffset))*180 / .pi
                    row("Phone points at",String(format:"%.0f°  ·  %.0f° up",degrees(ar.azimuth+SkyCalibration.arHeadingOffset),ar.altitude*180 / .pi))
                    row("Turn",abs(turn) < 2 ? "On target" : String(format:"%.0f° %@",abs(turn),turn > 0 ? "right" : "left"))
                }
                if let motion = motionAim() {
                    row("Garden sensor",String(format:"%.0f°  ·  %.0f° up",degrees(motion.azimuth+SkyCalibration.motionHeadingOffset),motion.altitude*180 / .pi))
                }
            }
        }
    }
    private func row(_ label: String,_ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.white.opacity(0.55))
            Spacer()
            Text(value).foregroundStyle(.white).monospacedDigit()
        }
        .font(.system(size:13))
    }

    @ViewBuilder private var statusLine: some View {
        switch outcome {
        case .saved(let message):
            Label(message,systemImage:"checkmark.circle.fill").font(.system(size:13,weight:.medium)).foregroundStyle(CelyxColor.ready)
        case .failed(let message):
            Label(message,systemImage:"exclamationmark.circle.fill").font(.system(size:13,weight:.medium)).foregroundStyle(.orange)
        case .none:
            if let date = SkyCalibration.date {
                Text("Last calibrated \(date.formatted(.relative(presentation:.named))) with \(SkyCalibration.target ?? "a sky object"): camera \(signed(SkyCalibration.arHeadingOffset)), garden \(signed(SkyCalibration.motionHeadingOffset))")
                    .font(.system(size:12)).foregroundStyle(.white.opacity(0.55))
            } else if let motionMessage {
                Text(motionMessage).font(.system(size:12)).foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    // MARK: Sensors

    private func start() async {
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for:.video) {
        case .authorized: granted = true
        case .notDetermined: granted = await AVCaptureDevice.requestAccess(for:.video)
        default: granted = false
        }
        guard granted else { cameraDenied = true; return }
        runSession()
        let service = motion ?? MotionService()
        motion = service
        service.onLocation = { fix in location = fix }
        service.onCalibration = { ready,_,message,_ in motionMessage = ready ? nil : message }
        service.onAttitude = { value in attitude = value }
        service.start { _,_,_ in }
    }
    private func runSession() {
        guard AROrientationTrackingConfiguration.isSupported else { return }
        let configuration = AROrientationTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading
        session.run(configuration,options:[.resetTracking])
    }
    private func stop() {
        session.pause()
        motion?.stop()
    }
    private func close() { stop(); onClose() }

    /// ARKit camera direction, raw (before calibration). gravityAndHeading: x east, y up, z south.
    private func arAim() -> (azimuth: Double, altitude: Double)? {
        guard let frame = session.currentFrame, case .normal = frame.camera.trackingState else { return nil }
        let back = frame.camera.transform.columns.2
        let forward = SIMD3(Double(-back.x),Double(-back.y),Double(-back.z))
        return (atan2(forward.x,-forward.z),asin(min(1,max(-1,forward.y))))
    }
    /// CoreMotion camera direction, raw (before calibration).
    private func motionAim() -> (azimuth: Double, altitude: Double)? {
        guard let attitude else { return nil }
        let forward = -attitude.columns.2
        return (atan2(forward.x,forward.y),asin(min(1,max(-1,forward.z))))
    }

    private func refreshTargets() {
        guard let location else { return }
        let sky = AstronomyService.snapshot(date:Date(),location:location)
        func make(_ star: CatalogStar,_ direction: SIMD3<Double>,disc: Bool) -> Target {
            Target(id:star.id,name:star.title,direction:Refraction.apparent(direction),isDisc:disc)
        }
        var list: [Target] = []
        let sunUp = sky.sunAltitude > 5
        if sunUp { list.append(make(.sun,sky.sunDirection,disc:true)) }
        let moonAltitude = asin(sky.moonDirection.z)*180 / .pi
        if moonAltitude > 5 && sky.moonIllumination > 0.15 { list.append(make(.moon,sky.moonDirection,disc:true)) }
        if sky.sunAltitude < -6 {
            list += sky.planets.filter { $0.star.mag < 1.5 && $0.direction.z > sin(10 * .pi/180) }
                .sorted { $0.star.mag < $1.star.mag }.map { make($0.star,$0.direction,disc:false) }
            list += catalogue.filter { $0.mag < 1.3 }
                .map { ($0,sky.direction(ra:$0.ra_deg,dec:$0.dec_deg)) }
                .filter { $0.1.z > sin(15 * .pi/180) }
                .prefix(6).map { make($0.0,$0.1,disc:false) }
        }
        targets = list
        if !list.contains(where:{ $0.id == selectedID }) { selectedID = list.first?.id }
    }

    // MARK: Calibrate

    private func calibrate() {
        guard let target else { return }
        guard let ar = arAim() else {
            outcome = .failed("The camera’s direction isn’t ready. Hold still and try again."); return
        }
        // Tilt comes from gravity and is reliable, so a big height mismatch means you aren't aiming at it.
        let heightError = abs(ar.altitude-target.altitude)*180 / .pi
        guard heightError <= 6 else {
            outcome = .failed(String(format:"%@ is %.0f° up. Put it in the circle and try again.",target.name,target.altitude*180 / .pi)); return
        }
        // For the Sun and Moon, make sure there really is a bright disc in the circle.
        if target.isDisc {
            guard let buffer = session.currentFrame?.capturedImage, viewSize != .zero,
                  let sample = CenterLightProbe.measure(buffer,viewSize:viewSize,radius:28),
                  sample.peak >= (target.id == CatalogStar.sun.id ? 245 : 120) else {
                outcome = .failed("We can’t see \(target.name) in the circle yet."); return
            }
        }
        let arOffset = SkyCalibration.wrap(target.azimuth-ar.azimuth)
        let motionOffset = motionAim().map { SkyCalibration.wrap(target.azimuth-$0.azimuth) }
        SkyCalibration.save(arOffset:arOffset,motionOffset:motionOffset,target:target.name)
        let gardenPart = motionOffset.map { ", garden \(signed($0))" } ?? " (garden needs the compass to settle, so try once more)"
        outcome = .saved("Calibrated with \(target.name): camera \(signed(arOffset))\(gardenPart)")
    }

    private func degrees(_ radians: Double) -> Double { (radians*180 / .pi+360).truncatingRemainder(dividingBy:360) }
    private func signed(_ radians: Double) -> String { String(format:"%+.0f°",radians*180 / .pi) }
}
