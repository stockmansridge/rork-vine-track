import SwiftUI

extension Color {
    static func fromString(_ name: String) -> Color {
        switch name.lowercased() {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "blue": return .blue
        case "purple": return .purple
        case "cyan": return .cyan
        case "green": return .green
        case "gray", "grey": return .gray
        case "pink": return .pink
        case "mint": return .mint
        case "teal": return .teal
        case "indigo": return .indigo
        case "brown": return .brown
        case "darkgreen", "dark green": return Color(red: 0.0, green: 0.5, blue: 0.0)
        default: return .gray
        }
    }

    static let availableColors: [(name: String, color: Color)] = [
        ("red", .red),
        ("orange", .orange),
        ("yellow", .yellow),
        ("blue", .blue),
        ("purple", .purple),
        ("cyan", .cyan),
        ("green", .green),
        ("gray", .gray),
        ("pink", .pink),
        ("mint", .mint),
        ("teal", .teal),
        ("indigo", .indigo),
        ("brown", .brown),
        ("darkgreen", Color(red: 0.0, green: 0.5, blue: 0.0)),
    ]
}
