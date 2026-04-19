import Foundation

struct DataBackupResult {
    let archiveName: String
    let storeComponentCount: Int
    let includedImages: Bool
}

enum DataBackupError: LocalizedError {
    case noDatabaseFound
    case invalidArchive
    case archiveCommandFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDatabaseFound:
            return "未找到可导出的数据库文件"
        case .invalidArchive:
            return "导入文件格式不正确"
        case .archiveCommandFailed(let message):
            return "压缩文件处理失败：\(message)"
        }
    }
}

final class DataBackupService {
    static let shared = DataBackupService()

    private let fileManager = FileManager.default
    private let workingFolderName = "AhaPasteBackup"
    private let manifestFileName = "manifest.json"

    private init() {}

    func exportBackup(to archiveURL: URL) throws -> DataBackupResult {
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("aha-paste-backup-export-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let payloadRoot = tempRoot.appendingPathComponent(workingFolderName, isDirectory: true)
        let databaseDir = payloadRoot.appendingPathComponent("database", isDirectory: true)
        let imagesDir = payloadRoot.appendingPathComponent("images", isDirectory: true)

        try fileManager.createDirectory(at: databaseDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        let sourceStoreBaseURL = activeStoreBaseURL()
        let sourceStoreComponents = existingStoreComponents(forBaseURL: sourceStoreBaseURL)
        guard sourceStoreComponents.isEmpty == false else {
            throw DataBackupError.noDatabaseFound
        }

        for sourceURL in sourceStoreComponents {
            let destinationURL = databaseDir.appendingPathComponent(sourceURL.lastPathComponent)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }

        let sourceImagesDirectory = imageDirectoryURL
        let imagesExist = fileManager.fileExists(atPath: sourceImagesDirectory.path)
        if imagesExist {
            try fileManager.removeItem(at: imagesDir)
            try fileManager.copyItem(at: sourceImagesDirectory, to: imagesDir)
        }

        let manifest = DataBackupManifest(
            version: 1,
            exportedAt: ISO8601DateFormatter().string(from: .now),
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "aha.paste",
            storeFileName: sourceStoreBaseURL.lastPathComponent,
            storeComponents: sourceStoreComponents.map(\.lastPathComponent).sorted(),
            includesImages: imagesExist
        )

        let manifestURL = payloadRoot.appendingPathComponent(manifestFileName)
        let manifestData = try JSONEncoder.backupManifestEncoder.encode(manifest)
        try manifestData.write(to: manifestURL, options: .atomic)

        if fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.removeItem(at: archiveURL)
        }

        try runTool(
            executablePath: "/usr/bin/ditto",
            arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", payloadRoot.path, archiveURL.path]
        )

        return DataBackupResult(
            archiveName: archiveURL.lastPathComponent,
            storeComponentCount: sourceStoreComponents.count,
            includedImages: imagesExist
        )
    }

    func importBackup(from archiveURL: URL) throws -> DataBackupResult {
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("aha-paste-backup-import-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let unzipRoot = tempRoot.appendingPathComponent("unzipped", isDirectory: true)
        try fileManager.createDirectory(at: unzipRoot, withIntermediateDirectories: true)

        try runTool(
            executablePath: "/usr/bin/ditto",
            arguments: ["-x", "-k", archiveURL.path, unzipRoot.path]
        )

        let payloadRoot = try locatePayloadRoot(in: unzipRoot)
        let manifestURL = payloadRoot.appendingPathComponent(manifestFileName)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw DataBackupError.invalidArchive
        }

        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(DataBackupManifest.self, from: manifestData)

        let databaseDir = payloadRoot.appendingPathComponent("database", isDirectory: true)
        guard fileManager.fileExists(atPath: databaseDir.path) else {
            throw DataBackupError.invalidArchive
        }

        let sourceStoreBaseURL = databaseDir.appendingPathComponent(manifest.storeFileName)
        guard fileManager.fileExists(atPath: sourceStoreBaseURL.path) else {
            throw DataBackupError.invalidArchive
        }

        let destinationStoreBaseURL = preferredStoreBaseURL
        try replaceStoreGroup(fromBaseURL: sourceStoreBaseURL, toBaseURL: destinationStoreBaseURL)

        let sourceImagesDir = payloadRoot.appendingPathComponent("images", isDirectory: true)
        if manifest.includesImages, fileManager.fileExists(atPath: sourceImagesDir.path) {
            try replaceDirectory(at: imageDirectoryURL, with: sourceImagesDir)
        } else {
            try? fileManager.removeItem(at: imageDirectoryURL)
            try fileManager.createDirectory(at: imageDirectoryURL, withIntermediateDirectories: true)
        }

        return DataBackupResult(
            archiveName: archiveURL.lastPathComponent,
            storeComponentCount: manifest.storeComponents.count,
            includedImages: manifest.includesImages
        )
    }

    private var appSupportURL: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private var preferredStoreBaseURL: URL {
        let storeName = Bundle.main.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = (storeName?.isEmpty == false ? storeName! : "aha.paste") + ".store"
        return appSupportURL.appendingPathComponent(normalized, conformingTo: .data)
    }

    private var legacyStoreBaseURL: URL {
        appSupportURL.appendingPathComponent("default.store", conformingTo: .data)
    }

    private var imageDirectoryURL: URL {
        appSupportURL.appendingPathComponent("Paste", isDirectory: true)
    }

    private func activeStoreBaseURL() -> URL {
        if fileManager.fileExists(atPath: preferredStoreBaseURL.path) {
            return preferredStoreBaseURL
        }
        if fileManager.fileExists(atPath: legacyStoreBaseURL.path) {
            return legacyStoreBaseURL
        }
        return preferredStoreBaseURL
    }

    private func existingStoreComponents(forBaseURL baseURL: URL) -> [URL] {
        ["", "-wal", "-shm"]
            .map { baseURL.appendingSuffix($0) }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    private func replaceStoreGroup(fromBaseURL sourceBaseURL: URL, toBaseURL destinationBaseURL: URL) throws {
        for suffix in ["", "-wal", "-shm"] {
            let sourceURL = sourceBaseURL.appendingSuffix(suffix)
            let destinationURL = destinationBaseURL.appendingSuffix(suffix)

            if fileManager.fileExists(atPath: sourceURL.path) {
                try replaceFile(at: destinationURL, with: sourceURL)
            } else if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
        }
    }

    private func replaceDirectory(at destination: URL, with source: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private func replaceFile(at destination: URL, with source: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: source)
        } else {
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    private func locatePayloadRoot(in directory: URL) throws -> URL {
        let directCandidate = directory.appendingPathComponent(workingFolderName, isDirectory: true)
        if fileManager.fileExists(atPath: directCandidate.path) {
            return directCandidate
        }

        let children = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])
        if let matched = children.first(where: { child in
            let manifestURL = child.appendingPathComponent(manifestFileName)
            return fileManager.fileExists(atPath: manifestURL.path)
        }) {
            return matched
        }

        throw DataBackupError.invalidArchive
    }

    private func runTool(executablePath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "unknown"
            throw DataBackupError.archiveCommandFailed(message)
        }
    }
}

private struct DataBackupManifest: Codable {
    let version: Int
    let exportedAt: String
    let bundleIdentifier: String
    let storeFileName: String
    let storeComponents: [String]
    let includesImages: Bool
}

private extension URL {
    func appendingSuffix(_ suffix: String) -> URL {
        guard suffix.isEmpty == false else {
            return self
        }
        return URL(fileURLWithPath: path + suffix)
    }
}

private extension JSONEncoder {
    static var backupManifestEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
