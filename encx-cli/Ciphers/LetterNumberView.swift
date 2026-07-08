import SwiftUI

/// Код букв (A1Z26): замена букв их порядковыми номерами в алфавите и обратно.
struct LetterNumberView: View {
    private enum Direction: String, CaseIterable, Identifiable {
        case toNumbers
        case toText
        var id: String { rawValue }
    }

    @State private var input = ""
    @State private var alphabet: CipherAlphabet = .ru
    @State private var includeYo = true
    @State private var direction: Direction = .toNumbers

    private var currentAlphabet: [Character] {
        alphabet == .ru ? CipherAlphabet.ru.letters(includeYo: includeYo) : CipherAlphabet.en.letters()
    }

    private var output: String {
        switch direction {
        case .toNumbers: return LetterNumberCipher.encode(input, alphabet: currentAlphabet)
        case .toText: return LetterNumberCipher.decode(input, alphabet: currentAlphabet)
        }
    }

    private var placeholder: String {
        switch direction {
        case .toNumbers: return "Текст, напр. «привет»"
        case .toText: return "Числа, напр. «17 18 10 3 6 20»"
        }
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
        .cipherToolChrome(title: "Код букв (A1Z26)")
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Направление")
            Picker("Направление", selection: $direction) {
                Text("Текст → числа").tag(Direction.toNumbers)
                Text("Числа → текст").tag(Direction.toText)
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
            SectionTitle(direction == .toNumbers ? "Текст" : "Числа")
            CipherInputField(placeholder: placeholder, text: $input)
        }
        .sectionPanel()
    }

    private var hintSection: some View {
        Text("А = 1, Б = 2, … Числа разделяйте пробелами, слова — символом «/».")
            .font(.caption)
            .foregroundStyle(GameTheme.muted)
            .sectionPanel()
    }
}

#Preview {
    NavigationStack {
        LetterNumberView()
    }
}
