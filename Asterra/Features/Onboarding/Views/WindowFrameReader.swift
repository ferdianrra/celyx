import SwiftUI
import UIKit

/// Reports a view's frame in window coordinates. Toolbar items live in their own hosting views, so
/// SwiftUI's `.global` space there is local to the toolbar; UIKit's window conversion is the real screen.
struct WindowFrameReader: UIViewRepresentable {
    let onChange: (CGRect) -> Void

    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.onChange = onChange
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }
    func updateUIView(_ view: Probe, context: Context) {
        view.onChange = onChange
        view.report()
    }

    final class Probe: UIView {
        var onChange: ((CGRect) -> Void)?
        private var last: CGRect = .null
        override func layoutSubviews() { super.layoutSubviews(); report() }
        override func didMoveToWindow() { super.didMoveToWindow(); report() }
        func report() {
            guard window != nil else { return }
            let frame = convert(bounds, to: nil)
            guard frame != last, frame.width > 0 else { return }
            last = frame
            DispatchQueue.main.async { [onChange] in onChange?(frame) }
        }
    }
}
