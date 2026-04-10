import AppKit
import Foundation

final class ImageFileStore {
    static let shared = ImageFileStore()

    private let directoryURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directoryURL = appSupport.appendingPathComponent("Paste", isDirectory: true)

        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func save(image: NSImage) throws -> String {
        let fileName = "\(UUID().uuidString).png"
        let fileURL = directoryURL.appendingPathComponent(fileName)
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try pngData.write(to: fileURL, options: .atomic)
        return fileName
    }

    func load(relativePath: String) throws -> NSImage {
        let url = directoryURL.appendingPathComponent(relativePath)
        guard let image = NSImage(contentsOf: url) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return image
    }

    func delete(relativePath: String) throws {
        let url = directoryURL.appendingPathComponent(relativePath)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
