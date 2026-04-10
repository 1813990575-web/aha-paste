import Foundation
import SwiftData

@Model
final class Tag {
    var id: UUID
    var name: String
    var isSystem: Bool
    var colorHex: String?
    var sortOrder: Int?
    @Relationship(deleteRule: .cascade, inverse: \ItemTagLink.tag) var itemLinks: [ItemTagLink]

    init(id: UUID = UUID(), name: String, isSystem: Bool = false, colorHex: String? = "#FF5C8A", sortOrder: Int? = 0) {
        self.id = id
        self.name = name
        self.isSystem = isSystem
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.itemLinks = []
    }
}

@Model
final class ItemTagLink {
    var id: UUID
    var item: ClipItem?
    var tag: Tag?

    init(id: UUID = UUID(), item: ClipItem? = nil, tag: Tag? = nil) {
        self.id = id
        self.item = item
        self.tag = tag
    }
}
