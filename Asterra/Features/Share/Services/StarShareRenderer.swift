import SwiftUI
import UIKit

enum StarShareRenderer {
    static func image(content: StarShareContent, layout: ShareCardLayout, photo: UIImage?) -> UIImage? {
        let renderer = ImageRenderer(content: StarShareCard(content: content, layout: layout, photo: photo))
        renderer.isOpaque = false
        renderer.scale = 1080 / StarShareCard.size.width
        return renderer.uiImage
    }
}
