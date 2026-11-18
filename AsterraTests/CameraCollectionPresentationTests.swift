import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Asterra

@MainActor struct CameraCollectionPresentationTests {
    @Test func renderReferenceStatesAndLongObjectName() throws {
        let rigel = try #require(SkyAssets.stars().first { $0.title == "Rigel" })
        let longName = try #require(SkyAssets.stars().first { $0.title == "Zubenelgenubi" })
        for (name, star) in [("rigel", rigel), ("long-name", longName)] {
            let ready = VStack(spacing: 38) {
                Spacer()
                CameraCollectionPrompt(text: "Tap anywhere to collect", ready: true)
                CameraCollectionCard(star: star, onCollect: {}, onDismiss: {})
            }
            .padding(.horizontal, 20).padding(.bottom, 34)
            .frame(width: 393, height: 852).background(CelyxColor.night).preferredColorScheme(.dark)
            let renderer = ImageRenderer(content: ready)
            renderer.scale = 2
            let image = try #require(renderer.uiImage)
            try #require(image.pngData()).write(to: URL(fileURLWithPath: "/tmp/asterra-camera-\(name).png"))
        }
        for (name, background) in [("bright", Color.white), ("dark", CelyxColor.night)] {
            let prompt = CameraCollectionPrompt(text: "Tap anywhere to collect", ready: true)
                .frame(width: 393, height: 160).background(background)
            let image = try #require(ImageRenderer(content: prompt).uiImage)
            try #require(image.pngData()).write(to: URL(fileURLWithPath: "/tmp/asterra-camera-prompt-\(name).png"))
        }
        let searching = VStack {
            Spacer()
            CameraCollectionPrompt(text: "Find a star or planet in the sky")
        }.padding(.bottom, 104).frame(width: 393, height: 852).background(CelyxColor.night)
        let image = try #require(ImageRenderer(content: searching).uiImage)
        try #require(image.pngData()).write(to: URL(fileURLWithPath: "/tmp/asterra-camera-search.png"))
    }
}
