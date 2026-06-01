import SwiftUI

enum GameTheme {
    static let background = Color.black
    static let panel = Color(white: 0.08)
    static let border = Color(white: 0.22)
    static let text = Color.white
    static let muted = Color(white: 0.62)
    static let sectionHeader = Color(red: 0.95, green: 0.82, blue: 0.18)
    static let bonusTitle = Color(red: 0.35, green: 0.85, blue: 0.95)
    static let accent = Color(red: 0.2, green: 0.72, blue: 0.35)
    static let inputBackground = Color(white: 0.12)
}

struct GameSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(GameTheme.sectionHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
