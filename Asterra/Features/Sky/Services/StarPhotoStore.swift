import Foundation
import UIKit

enum StarPhotoStore {
    private static var directory: URL {
        get throws {
            let root = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let directory = root.appendingPathComponent("StarJournal", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
    }
    static func save(_ image: UIImage) throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.97) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let filename = UUID().uuidString + ".jpg"
        try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
        return filename
    }
    static func load(_ filename: String?) -> UIImage? {
        guard let filename, filename == URL(fileURLWithPath: filename).lastPathComponent,
            let directory = try? directory
        else { return nil }
        return UIImage(contentsOfFile: directory.appendingPathComponent(filename).path)
    }
    static func remove(_ filename: String) {
        guard filename == URL(fileURLWithPath: filename).lastPathComponent,
            let directory = try? directory
        else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
    }
}
