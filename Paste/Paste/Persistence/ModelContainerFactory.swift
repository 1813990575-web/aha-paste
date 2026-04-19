import Foundation
import SQLite3
import SwiftData

enum SystemTagName {
    static let all = "全部"
    static let images = "图片"
}

final class ModelContainerFactory {
    static let shared = ModelContainerFactory()
    let container: ModelContainer

    private init() {
        let schema = Schema([
            ClipItem.self,
            Tag.self,
            ItemTagLink.self
        ])

        do {
            let storeName = Self.storeName
            try Self.migrateLegacyStoreIfNeeded(storeName: storeName)
            let config = ModelConfiguration(storeName, schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [config])
            try ensureSystemTags()
        } catch {
            fatalError("Failed to initialize model container: \(error)")
        }
    }

    private static var storeName: String {
        let fallback = "aha.paste"
        guard
            let bundleID = Bundle.main.bundleIdentifier?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            bundleID.isEmpty == false
        else {
            return fallback
        }
        return bundleID
    }

    private static func storeURL(named name: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("\(name).store", conformingTo: .data)
    }

    private static func migrateLegacyStoreIfNeeded(storeName: String) throws {
        guard storeName != "default" else {
            return
        }

        let fileManager = FileManager.default
        let legacyURL = Self.storeURL(named: "default")
        let targetURL = Self.storeURL(named: storeName)

        guard fileManager.fileExists(atPath: targetURL.path) == false else {
            return
        }

        guard fileManager.fileExists(atPath: legacyURL.path) else {
            return
        }

        guard legacyStoreLooksLikePasteStore(at: legacyURL) else {
            return
        }

        try copyStoreFileGroup(fromBaseURL: legacyURL, toBaseURL: targetURL)
    }

    private static func copyStoreFileGroup(fromBaseURL source: URL, toBaseURL target: URL) throws {
        let fileManager = FileManager.default

        for suffix in ["", "-wal", "-shm"] {
            let sourceURL = source.appendingPathExtensionSuffix(suffix)
            let targetURL = target.appendingPathExtensionSuffix(suffix)

            guard fileManager.fileExists(atPath: sourceURL.path) else {
                continue
            }

            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.copyItem(at: sourceURL, to: targetURL)
        }
    }

    private static func legacyStoreLooksLikePasteStore(at url: URL) -> Bool {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let database {
                sqlite3_close(database)
            }
            return false
        }

        defer {
            sqlite3_close(database)
        }

        let sql = "SELECT name FROM sqlite_master WHERE type='table';"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            if let statement {
                sqlite3_finalize(statement)
            }
            return false
        }

        defer {
            sqlite3_finalize(statement)
        }

        var tableNames = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let namePtr = sqlite3_column_text(statement, 0) else {
                continue
            }
            tableNames.insert(String(cString: namePtr).uppercased())
        }

        let requiredTokens = ["CLIPITEM", "TAG", "ITEMTAGLINK"]
        return requiredTokens.allSatisfy { token in
            tableNames.contains(where: { $0.contains(token) })
        }
    }

    private func ensureSystemTags() throws {
        let context = ModelContext(container)

        for tagName in [SystemTagName.all, SystemTagName.images] {
            let descriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.name == tagName })
            let existing = try context.fetch(descriptor)
            if existing.isEmpty {
                context.insert(Tag(
                    name: tagName,
                    isSystem: true,
                    colorHex: tagName == SystemTagName.images ? "#5B8CFF" : "#9AA0A6",
                    sortOrder: nil
                ))
            } else {
                for tag in existing where tag.colorHex == nil {
                    tag.colorHex = tagName == SystemTagName.images ? "#5B8CFF" : "#9AA0A6"
                }
            }
        }

        let allTags = try context.fetch(FetchDescriptor<Tag>())
        for tag in allTags where tag.colorHex == nil {
            tag.colorHex = tag.isSystem ? "#9AA0A6" : "#FF5C8A"
        }

        let customTags = allTags
            .filter { $0.isSystem == false }
            .sorted { lhs, rhs in
                let lhsOrder = lhs.sortOrder ?? Int.max
                let rhsOrder = rhs.sortOrder ?? Int.max
                if lhsOrder != rhsOrder {
                    return lhsOrder < rhsOrder
                }
                return lhs.name.localizedCompare(rhs.name) == .orderedAscending
            }

        for (index, tag) in customTags.enumerated() where tag.sortOrder != index {
            tag.sortOrder = index
        }

        let allItems = try context.fetch(FetchDescriptor<ClipItem>())
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.id.uuidString > rhs.id.uuidString
            }

        for (index, item) in allItems.enumerated() where item.sortOrder != index {
            item.sortOrder = index
        }

        try context.save()
    }
}

private extension URL {
    func appendingPathExtensionSuffix(_ suffix: String) -> URL {
        guard suffix.isEmpty == false else {
            return self
        }
        return URL(fileURLWithPath: path + suffix)
    }
}
