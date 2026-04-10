import Foundation
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

        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            container = try ModelContainer(for: schema, configurations: [config])
            try ensureSystemTags()
        } catch {
            fatalError("Failed to initialize model container: \(error)")
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

        try context.save()
    }
}
