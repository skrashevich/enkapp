import SwiftUI

struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(GameTheme.sectionHeader)
    }
}

extension View {
    func sectionPanel() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .dashboardPanelBackground()
    }

    func dashboardPanelBackground(cornerRadius: CGFloat = 12) -> some View {
        background(GameTheme.panel, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(GameTheme.border, lineWidth: 1)
            }
    }
}

/// Shared appearance for the assistant entry point on the home and game screens.
struct AgentIcon: View {
    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 18, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(GameTheme.bonusTitle)
            .accessibilityHidden(true)
    }
}
