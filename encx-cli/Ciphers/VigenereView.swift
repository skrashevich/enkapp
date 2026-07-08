import SwiftUI

/// Шифр Виженера: многоалфавитный сдвиг по ключевому слову. RU и EN.
struct VigenereView: View {
    private enum Direction: String, CaseIterable, Identifiable {
        case decrypt
        case encrypt
        var id: String { rawValue }
    }

    @State private var input = ""
    @State private var key = ""
    @State private var alphabet: CipherAlphabet = .ru
    @State private var includeYo = true
    @State private var direction: Direction = .decrypt

    private var currentAlphabet: [Character] {
        alphabet == .ru ? CipherAlphabet.ru.letters(includeYo: includeYo) : CipherAlphabet.en.letters()
    }

    private var output: String {
        VigenereCipher.transform(input, key: key, alphabet: currentAlphabet, decrypt: direction == .decrypt)
    }

    private var keyHasLetters: Bool {
        key.lowercased().contains { currentAlphabet.contains($0) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                settingsSection
                inputSection
                CipherResultCard(text: output)
                hintSection
            }
            .padding()
        }
        .cipherToolChrome(title: "Шифр Виженера")
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Направление")
            Picker("Направление", selection: $direction) {
                Text("Расшифровать").tag(Direction.decrypt)
                Text("Зашифровать").tag(Direction.encrypt)
            }
            .pickerStyle(.segmented)

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
            SectionTitle("Ключ")
            TextField("Ключевое слово, напр. «ключ»", text: $key)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(GameTheme.text)
                .padding(12)
                .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 10))
            if !key.isEmpty, !keyHasLetters {
                Text("В ключе нет букв выбранного алфавита — текст не изменится.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            SectionTitle("Текст")
            CipherInputField(placeholder: direction == .decrypt ? "Зашифрованный текст" : "Открытый текст", text: $input)
        }
        .sectionPanel()
    }

    private var hintSection: some View {
        Text("Каждая буква сдвигается на позицию соответствующей буквы ключа. Ключ повторяется циклически; небуквенные символы не меняются.")
            .font(.caption)
            .foregroundStyle(GameTheme.muted)
            .sectionPanel()
    }
}

#Preview {
    NavigationStack {
        VigenereView()
    }
}
