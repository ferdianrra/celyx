import SceneKit
import UIKit

@MainActor
enum GardenBodyAssets {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()
    static func image(_ name: String, extension ext: String = "jpg") -> UIImage? {
        let key = (name + "." + ext) as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let url = try? SkyAssets.url(name, extension: ext),
            let image = UIImage(contentsOfFile: url.path)
        else { return nil }
        cache.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height) * 4)
        return image
    }
    static func family(_ star: CatalogStar) -> String {
        let title = star.title.lowercased()
        if title.contains("canopus") { return "canopus" }
        if title.contains("sirius") { return "sirius" }
        if title.contains("rigel") { return "rigel" }
        return (star.bv ?? 0.65) < 0 ? "rigel" : (star.bv ?? 0.65) < 0.45 ? "sirius" : "canopus"
    }
    static func portrait(_ star: CatalogStar) -> UIImage? {
        guard !star.isSolarSystemBody else { return nil }
        return image("garden-" + family(star) + "-portrait", extension: "png")
    }
    static func texture(_ star: CatalogStar) -> UIImage? {
        let name: String
        switch star.id {
        case -2: name = "moon"
        case -3: name = "mercury"
        case -4: name = "venus"
        case -5: name = "mars"
        case -6: name = "jupiter"
        default: name = family(star)
        }
        return image("garden-" + name)
    }
    static let glow: UIImage = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128), format: format).image {
            renderer in
            let colors =
                [
                    UIColor.white.cgColor, UIColor.white.withAlphaComponent(0.23).cgColor,
                    UIColor.clear.cgColor,
                ] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.25, 1])
            {
                renderer.cgContext.drawRadialGradient(
                    gradient, startCenter: CGPoint(x: 64, y: 64), startRadius: 0,
                    endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: .drawsAfterEndLocation)
            }
        }
    }()
    static func body(_ star: CatalogStar, radius: CGFloat = 0.14) -> SCNNode {
        let geometry = SCNSphere(radius: radius)
        geometry.segmentCount = 24
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = texture(star) ?? UIImage(named: "StarSurface")
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .clamp
        let tint = star.rgb
        if !star.isSolarSystemBody && !["canopus", "sirius", "rigel"].contains(star.title.lowercased()) {
            material.multiply.contents = UIColor(
                red: CGFloat(tint.x), green: CGFloat(tint.y), blue: CGFloat(tint.z), alpha: 1)
        }
        material.shaderModifiers = [
            .surface: """
            float facing = max(0.0, dot(normalize(_surface.normal), normalize(_surface.view)));
            _surface.diffuse.rgb *= 0.40 + 0.60 * pow(facing, 0.45);
            """
        ]
        geometry.firstMaterial = material
        let node = SCNNode(geometry: geometry)
        node.name = "garden-body"
        if !star.isPlanet && !star.isMoon {
            let halo = SCNPlane(width: radius * 5.5, height: radius * 5.5)
            let glowMaterial = SCNMaterial()
            glowMaterial.lightingModel = .constant
            glowMaterial.diffuse.contents = glow
            glowMaterial.multiply.contents = UIColor(
                red: CGFloat(tint.x), green: CGFloat(tint.y), blue: CGFloat(tint.z), alpha: 1)
            glowMaterial.blendMode = .add
            glowMaterial.writesToDepthBuffer = false
            halo.firstMaterial = glowMaterial
            let corona = SCNNode(geometry: halo)
            corona.constraints = [SCNBillboardConstraint()]
            corona.opacity = 0.45
            node.addChildNode(corona)
        }
        return node
    }
}
