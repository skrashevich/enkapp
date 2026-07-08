import SwiftUI

/// Раскладка клавиатуры: исправляет текст, набранный не в той раскладке (ЙЦУКЕН ↔ QWERTY).
struct KeyboardLayoutView: View {
    @State private var input = ""

    private var output: String {
        KeyboardLayout.convert(input)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                inputSection
                CipherResultCard(text: output)
                hintSection
            }
            .padding()
        }
        .cipherToolChrome(title: "Раскладка клавиатуры")
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Текст не в той раскладке")
            CipherInputField(placeholder: "Напр. «ghbdtn» или «руддщ»", text: $input)
            Text("Переключение автоматическое: работает в обе стороны за один проход.")
                .font(.caption)
                .foregroundStyle(GameTheme.muted)
        }
        .sectionPanel()
    }

    private var hintSection: some View {
        Text("Каждый символ переносится на клавишу противоположной раскладки. Незнакомые символы остаются без изменений.")
            .font(.caption)
            .foregroundStyle(GameTheme.muted)
            .sectionPanel()
    }
}

#Preview {
    NavigationStack {
        KeyboardLayoutView()
    }
}
