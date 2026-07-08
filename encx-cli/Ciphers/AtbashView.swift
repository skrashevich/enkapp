import SwiftUI

/// Атбаш: симметричная замена буквы на противоположную по счёту в алфавите.
struct AtbashView: View {
    @State private var input = ""
    @State private var alphabet: CipherAlphabet = .ru
    @State private var includeYo = true

    private var currentAlphabet: [Character] {
        alphabet == .ru ? CipherAlphabet.ru.letters(includeYo: includeYo) : CipherAlphabet.en.letters()
    }

    private var output: String {
        AtbashCipher.transform(input, alphabet: currentAlphabet)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                settingsSection
                inputSection
                CipherResultCard(text: output)
            }
            .padding()
        }
        .cipherToolChrome(title: "Атбаш")
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Алфавит")
            CipherLanguagePicker(selection: $alphabet)
            if alphabet == .ru {
                YoToggleRow(includeYo: $includeYo)
            }
        }
        .sectionPanel()
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Текст")
            CipherInputField(placeholder: "Текст для преобразования", text: $input)
            Text("Атбаш обратим: повторное преобразование вернёт исходный текст.")
                .font(.caption)
                .foregroundStyle(GameTheme.muted)
        }
        .sectionPanel()
    }
}

#Preview {
    NavigationStack {
        AtbashView()
    }
}
