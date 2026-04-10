import SwiftUI

extension Tag {
    var accentColor: Color {
        Color(hex: resolvedColorHex) ?? .pink
    }

    var resolvedColorHex: String {
        colorHex ?? (isSystem ? "#9AA0A6" : "#FF5C8A")
    }
}

extension Color {
    init?(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard sanitized.count == 6, let value = UInt64(sanitized, radix: 16) else {
            return nil
        }

        let red = Double((value & 0xFF0000) >> 16) / 255
        let green = Double((value & 0x00FF00) >> 8) / 255
        let blue = Double(value & 0x0000FF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
