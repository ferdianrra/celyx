import Combine
import SwiftUI
import UIKit

/// How a solar-system body is drawn by `PlanetView`.
struct PlanetLook {
    var texture: String?            // equirectangular garden texture, nil = procedural bands
    var tint: SIMD3<Float>          // band base colour (procedural) and ring colour
    var atmosphere: SIMD3<Float>
    var atmosphereAmount: Float     // 0 = airless (Moon, Mercury)
    var rotationSpeed: Float        // radians per second at portrait scale
    var axialTilt: Float            // radians, rotates the bands and rings on screen
    var ring: Float = 0
    var radius: Float = 0.40        // disk radius as a fraction of the frame

    static func look(for body: CatalogStar) -> PlanetLook? {
        switch body.id {
        case CatalogStar.moon.id:   // tidally locked: always the near side
            PlanetLook(texture: "moon", tint: .one, atmosphere: .zero, atmosphereAmount: 0,
                       rotationSpeed: 0, axialTilt: 0.12)
        case -3:
            PlanetLook(texture: "mercury", tint: .one, atmosphere: .zero, atmosphereAmount: 0,
                       rotationSpeed: 0.04, axialTilt: 0)
        case -4:
            PlanetLook(texture: "venus", tint: .one, atmosphere: SIMD3(1.0, 0.86, 0.60),
                       atmosphereAmount: 0.75, rotationSpeed: 0.02, axialTilt: 0.05)
        case -5:
            PlanetLook(texture: "mars", tint: .one, atmosphere: SIMD3(1.0, 0.62, 0.45),
                       atmosphereAmount: 0.30, rotationSpeed: 0.08, axialTilt: 0.44)
        case -6:
            PlanetLook(texture: "jupiter", tint: .one, atmosphere: SIMD3(0.95, 0.85, 0.72),
                       atmosphereAmount: 0.45, rotationSpeed: 0.14, axialTilt: 0.05)
        case -7:
            PlanetLook(texture: nil, tint: SIMD3(0.86, 0.76, 0.56), atmosphere: SIMD3(0.98, 0.90, 0.72),
                       atmosphereAmount: 0.40, rotationSpeed: 0.12, axialTilt: 0.47,
                       ring: 1, radius: 0.21)
        default:
            nil
        }
    }
}

/// A lit, slowly rotating planet or Moon. Follows StarView's power rules: paused when
/// hidden, in the background or with Reduce Motion; ~20 fps in Low Power Mode.
struct PlanetView: View {
    let look: PlanetLook

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var paused: Bool { reduceMotion || !isVisible || scenePhase != .active || look.rotationSpeed == 0 }

    var body: some View {
        let texture = PlanetTextures.image(look.texture)
        TimelineView(.animation(minimumInterval: lowPower ? 1.0 / 20.0 : nil, paused: paused)) { context in
            let clock = Float(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600))
            let spin = reduceMotion ? 0 : clock * look.rotationSpeed
            GeometryReader { geo in
                Rectangle()
                    .fill(.black)
                    .colorEffect(ShaderLibrary.planetSurface(
                        .float2(Float(geo.size.width), Float(geo.size.height)),
                        .float(spin),
                        .image(texture),
                        .float(look.texture == nil ? 0 : 1),
                        .float3(look.tint.x, look.tint.y, look.tint.z),
                        .float3(look.atmosphere.x, look.atmosphere.y, look.atmosphere.z),
                        .float(look.atmosphereAmount),
                        .float(look.axialTilt),
                        .float(look.ring),
                        .float(look.radius)))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .onReceive(NotificationCenter.default
            .publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: RunLoop.main)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}

/// Garden textures downscaled once for portrait sizes (no mipmaps in SwiftUI shaders,
/// so a 1024 px map would shimmer inside a 44–96 pt frame).
@MainActor
enum PlanetTextures {
    private static var cache: [String: Image] = [:]
    private static let placeholder: Image = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return Image(uiImage: UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format)
            .image { _ in })
    }()

    static func image(_ name: String?) -> Image {
        guard let name else { return placeholder }
        if let cached = cache[name] { return cached }
        guard let source = GardenBodyAssets.image("garden-" + name) else { return placeholder }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 256), format: format).image { _ in
            source.draw(in: CGRect(x: 0, y: 0, width: 512, height: 256))
        }
        let image = Image(uiImage: small)
        cache[name] = image
        return image
    }
}
