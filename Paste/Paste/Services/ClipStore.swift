import AppKit
import Foundation
import SwiftData

enum ClipFilter: Hashable, Identifiable {
    case all
    case images
    case tag(UUID)

    var id: String {
        switch self {
        case .all:
            return "all"
        case .images:
            return "images"
        case .tag(let id):
            return "tag-\(id.uuidString)"
        }
    }
}

enum ClipStoreError: LocalizedError {
    case nothingToSave

    var errorDescription: String? {
        switch self {
        case .nothingToSave:
            return "没有可发送的内容"
        }
    }
}

@MainActor
final class ClipStore {
    private let context: ModelContext
    private let tagPalette = [
        "#E56F52",
        "#7A67D8",
        "#FF5C8A",
        "#4C86E8",
        "#C98A2E",
        "#4FA46F",
        "#B65FD1",
        "#7D2AE8"
    ]

    init(context: ModelContext) {
        self.context = context
    }

    func fetchItems(searchText: String, filter: ClipFilter) throws -> [ClipItem] {
        let descriptor = FetchDescriptor<ClipItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        var items = try context.fetch(descriptor)

        switch filter {
        case .all:
            items = items.filter { $0.kind == .text }
        case .images:
            items = items.filter { $0.kind == .image }
        case .tag(let tagID):
            items = items.filter { item in
                item.kind == .text && item.tagLinks.contains { $0.tag?.id == tagID }
            }
        }

        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else {
            return items
        }

        let lowercaseQuery = trimmedQuery.lowercased()
        return items.filter { item in
            let content = item.contentText?.lowercased() ?? ""
            let note = item.note.lowercased()
            return content.contains(lowercaseQuery) || note.contains(lowercaseQuery)
        }
    }

    func saveText(content: String, note: String) throws {
        try saveText(content: content, note: note, customTagID: nil)
    }

    func saveText(content: String, note: String, customTagID: UUID?) throws {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedContent.isEmpty == false else {
            throw ClipStoreError.nothingToSave
        }

        let item = ClipItem(kind: .text, contentText: trimmedContent, note: trimmedNote)
        context.insert(item)
        try attach(tagsNamed: [SystemTagName.all], to: item)
        if let customTag = try fetchCustomTag(id: customTagID) {
            try assignCustomTag(customTag, to: item)
            return
        }
        try context.save()
    }

    func saveImage(_ image: NSImage, note: String) throws {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let relativePath = try ImageFileStore.shared.save(image: image)
        let item = ClipItem(kind: .image, note: trimmedNote, imageRelativePath: relativePath)
        context.insert(item)
        try attach(tagsNamed: [SystemTagName.images], to: item)
        try context.save()
    }

    func delete(_ item: ClipItem) throws {
        if let relativePath = item.imageRelativePath {
            try? ImageFileStore.shared.delete(relativePath: relativePath)
        }

        context.delete(item)
        try context.save()
    }

    func update(_ item: ClipItem, content: String?, note: String) throws {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        item.note = trimmedNote

        if item.kind == .text {
            let trimmedContent = (content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedContent.isEmpty == false else {
                throw ClipStoreError.nothingToSave
            }
            item.contentText = trimmedContent
        }

        try context.save()
    }

    func copyPayload(for item: ClipItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.kind {
        case .text:
            let value = item.contentText ?? ""
            pasteboard.setString(value, forType: .string)
        case .image:
            guard
                let relativePath = item.imageRelativePath,
                let image = try? ImageFileStore.shared.load(relativePath: relativePath)
            else {
                return
            }
            pasteboard.writeObjects([image])
        }
    }

    func fetchCustomTags() throws -> [Tag] {
        let descriptor = FetchDescriptor<Tag>()
        let tags = try context.fetch(descriptor).filter { tag in
            tag.isSystem == false
        }

        try ensureCustomTagOrdering(tags)
        try ensureCustomTagColors(tags)
        return tags.sorted { lhs, rhs in
            let lhsOrder = lhs.sortOrder ?? Int.max
            let rhsOrder = rhs.sortOrder ?? Int.max
            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }

    func customTagItemCounts() throws -> [UUID: Int] {
        let descriptor = FetchDescriptor<ClipItem>()
        let items = try context.fetch(descriptor)
        var counts: [UUID: Int] = [:]

        for item in items where item.kind == .text {
            for link in item.tagLinks {
                guard let tag = link.tag, tag.isSystem == false else {
                    continue
                }
                counts[tag.id, default: 0] += 1
            }
        }

        return counts
    }

    func createTag(named name: String) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else {
            return
        }

        let descriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.name == trimmedName })
        let exists = try context.fetch(descriptor).isEmpty == false
        guard exists == false else {
            return
        }

        let tags = try fetchCustomTags()
        let colorHex = nextColorHex(after: tags.count, avoiding: tags.last?.colorHex)
        let nextSortOrder = (tags.compactMap(\.sortOrder).max() ?? -1) + 1
        let tag = Tag(name: trimmedName, isSystem: false, colorHex: colorHex, sortOrder: nextSortOrder)
        context.insert(tag)
        try ensureCustomTagOrdering(tags + [tag])
        try ensureCustomTagColors(try fetchCustomTags())
        try context.save()
    }

    func renameTag(_ tag: Tag, to newName: String) throws {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else {
            return
        }

        let descriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.name == trimmedName })
        let existing = try context.fetch(descriptor)
        if existing.contains(where: { $0.id != tag.id }) {
            return
        }

        tag.name = trimmedName
        try ensureCustomTagColors(try fetchCustomTags())
        try context.save()
    }

    func deleteTag(_ tag: Tag) throws {
        for link in tag.itemLinks {
            context.delete(link)
        }
        context.delete(tag)
        try ensureCustomTagOrdering(try fetchCustomTags())
        try context.save()
    }

    func moveTagToFront(_ tag: Tag) throws {
        var tags = try fetchCustomTags()
        guard let index = tags.firstIndex(where: { $0.id == tag.id }) else {
            return
        }
        let moved = tags.remove(at: index)
        tags.insert(moved, at: 0)
        try applyCustomTagOrdering(tags)
    }

    func moveTag(_ tag: Tag, by delta: Int) throws {
        guard delta != 0 else {
            return
        }

        var tags = try fetchCustomTags()
        guard let index = tags.firstIndex(where: { $0.id == tag.id }) else {
            return
        }

        let target = min(max(index + delta, 0), tags.count - 1)
        guard target != index else {
            return
        }

        let moved = tags.remove(at: index)
        tags.insert(moved, at: target)
        try applyCustomTagOrdering(tags)
    }

    func moveTag(_ tag: Tag, to targetIndex: Int) throws {
        var tags = try fetchCustomTags()
        guard let sourceIndex = tags.firstIndex(where: { $0.id == tag.id }) else {
            return
        }

        let boundedTarget = min(max(targetIndex, 0), max(tags.count - 1, 0))
        guard boundedTarget != sourceIndex else {
            return
        }

        let moved = tags.remove(at: sourceIndex)
        tags.insert(moved, at: boundedTarget)
        try applyCustomTagOrdering(tags)
    }

    func currentCustomTag(for item: ClipItem) -> Tag? {
        item.tagLinks
            .compactMap(\.tag)
            .first(where: { $0.isSystem == false })
    }

    func assignCustomTag(_ tag: Tag?, to item: ClipItem) throws {
        let customLinks = item.tagLinks.filter { $0.tag?.isSystem == false }
        for link in customLinks {
            context.delete(link)
        }
        item.tagLinks.removeAll { $0.tag?.isSystem == false }

        if let tag {
            let link = ItemTagLink(item: item, tag: tag)
            context.insert(link)
            item.tagLinks.append(link)
            tag.itemLinks.append(link)
        }

        try context.save()
    }

    private func fetchCustomTag(id: UUID?) throws -> Tag? {
        guard let id else {
            return nil
        }

        let descriptor = FetchDescriptor<Tag>(predicate: #Predicate { tag in
            tag.id == id && tag.isSystem == false
        })
        return try context.fetch(descriptor).first
    }

    func ingestClipboardIfNeeded(changeCount: Int) throws -> String? {
        let pasteboard = NSPasteboard.general

        if let image = NSImage(pasteboard: pasteboard) {
            let item = ClipItem(kind: .image, note: "自动监听", imageRelativePath: try ImageFileStore.shared.save(image: image))
            item.createdAt = .now.addingTimeInterval(TimeInterval(changeCount) * 0.0001)
            context.insert(item)
            try attach(tagsNamed: [SystemTagName.images], to: item)
            try context.save()
            return "已捕获图片"
        }

        guard let text = pasteboard.string(forType: .string) else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        let descriptor = FetchDescriptor<ClipItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let duplicate = try context.fetch(descriptor).first {
            $0.kind == .text && $0.contentText == trimmed
        }
        if duplicate != nil {
            return nil
        }

        let item = ClipItem(kind: .text, contentText: trimmed, note: "自动监听")
        context.insert(item)
        try attach(tagsNamed: [SystemTagName.all], to: item)
        try context.save()
        return trimmed.count > 18 ? "已捕获：\(trimmed.prefix(18))..." : "已捕获：\(trimmed)"
    }

    private func attach(tagsNamed names: [String], to item: ClipItem) throws {
        for name in names {
            let descriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.name == name })
            guard let tag = try context.fetch(descriptor).first else {
                continue
            }
            let link = ItemTagLink(item: item, tag: tag)
            context.insert(link)
            item.tagLinks.append(link)
            tag.itemLinks.append(link)
        }
    }

    private func applyCustomTagOrdering(_ tags: [Tag]) throws {
        for (index, tag) in tags.enumerated() {
            tag.sortOrder = index
        }
        try context.save()
    }

    private func ensureCustomTagOrdering(_ tags: [Tag]) throws {
        var hasChanges = false

        for (index, tag) in tags.enumerated() where tag.sortOrder != index {
            tag.sortOrder = index
            hasChanges = true
        }

        if hasChanges {
            try context.save()
        }
    }

    private func ensureCustomTagColors(_ tags: [Tag]) throws {
        var hasChanges = false

        for (index, tag) in tags.enumerated() {
            let normalized = paletteColor(for: index, previousHex: index > 0 ? tags[index - 1].colorHex : nil)
            if tag.colorHex != normalized {
                tag.colorHex = normalized
                hasChanges = true
            }
        }

        if hasChanges {
            try context.save()
        }
    }

    private func paletteColor(for index: Int, previousHex: String?) -> String {
        guard tagPalette.isEmpty == false else {
            return "#FF5C8A"
        }

        var candidate = tagPalette[index % tagPalette.count]
        if candidate == previousHex {
            candidate = tagPalette[(index + 1) % tagPalette.count]
        }
        return candidate
    }

    private func nextColorHex(after count: Int, avoiding previousHex: String?) -> String {
        paletteColor(for: count, previousHex: previousHex)
    }
}
