import Foundation
import SwiftData

enum ClipKind: String, Codable, CaseIterable {
    case text
    case image
}

@Model
final class ClipItem {
    var id: UUID
    var kindRawValue: String
    var contentText: String?
    var note: String
    var imageRelativePath: String?
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \ItemTagLink.item) var tagLinks: [ItemTagLink]

    init(
        id: UUID = UUID(),
        kind: ClipKind,
        contentText: String? = nil,
        note: String = "",
        imageRelativePath: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kindRawValue = kind.rawValue
        self.contentText = contentText
        self.note = note
        self.imageRelativePath = imageRelativePath
        self.createdAt = createdAt
        self.tagLinks = []
    }

    var kind: ClipKind {
        get { ClipKind(rawValue: kindRawValue) ?? .text }
        set { kindRawValue = newValue.rawValue }
    }
}
