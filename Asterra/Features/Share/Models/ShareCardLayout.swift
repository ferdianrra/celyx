import Foundation

enum ShareCardLayout: String, CaseIterable, Identifiable {
    case polaroid, fullPhoto
    var id: String { rawValue }
    var title: String { self == .polaroid ? "Polaroid" : "Full photo" }
}
