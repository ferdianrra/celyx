import SwiftUI
import Testing
import UIKit

@testable import Asterra

@MainActor
struct StarKitPortraitTests {
    private func star(named name: String) throws -> CatalogStar {
        try #require(try SkyAssets.stars().first { $0.name == name })
    }

    @Test func catalogStarsDriveStarKitFromBVAndLuminosity() throws {
        let sirius = try star(named: "Sirius")
        #expect(sirius.colorIndex == sirius.bv)
        // Sirius is ~25 L☉; the catalog's rounded distance keeps it within a loose band.
        let luminosity = try #require(sirius.luminosity)
        #expect((10...60).contains(luminosity))

        let rigel = try star(named: "Rigel")
        let betelgeuse = try star(named: "Betelgeuse")
        #expect(StarStyle(rigel).temperature > StarStyle(betelgeuse).temperature)
        #expect(StarStyle(rigel).corona > StarStyle(sirius).corona)
    }

    /// Share cards are exported with ImageRenderer, so the shader star must appear there too.
    @Test func portraitRendersTheShaderStarInImageRenderer() throws {
        let renderer = ImageRenderer(content: StarPortraitView(star: try star(named: "Rigel"))
            .frame(width: 96, height: 96))
        renderer.scale = 1
        let image = try #require(renderer.uiImage?.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Sample the disk centre.
        context.draw(image, in: CGRect(x: -48, y: -48, width: image.width, height: image.height))
        #expect(pixel[3] > 200)
        #expect(Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2]) > 300)
    }

    /// Moon and planets draw their textured sphere (and Saturn its procedural bands) in export too.
    @Test func solarSystemPortraitsRenderALitDisk() throws {
        for body in [CatalogStar.sun, .moon] + CatalogStar.planets {
            #expect(body.isSun || PlanetLook.look(for: body) != nil, "\(body.title) has no look")
            let renderer = ImageRenderer(content: StarPortraitView(star: body).frame(width: 96, height: 96))
            renderer.scale = 1
            let image = try #require(renderer.uiImage?.cgImage)
            var pixel = [UInt8](repeating: 0, count: 4)
            let context = try #require(CGContext(
                data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            // Sample slightly toward the lit upper-left of the disk.
            context.draw(image, in: CGRect(x: -44, y: -50, width: image.width, height: image.height))
            #expect(pixel[3] > 200, "\(body.title) disk is transparent")
            #expect(Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2]) > 150, "\(body.title) disk is dark")
        }
    }
}
