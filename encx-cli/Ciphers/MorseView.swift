import SwiftUI

/// Азбука Морзе: кодирование и декодирование для русского и латинского алфавитов.
struct MorseView: View {
    private enum Direction: String, CaseIterable, Identifiable {
        case toMorse
        case toText
        var id: String { rawValue }
    }

    @State private var input = ""
    @State private var alphabet: CipherAlphabet = .ru
    @State private var direction: Direction = .toText

    private var output: String {
        switch direction {
        case .toMorse: return MorseCode.encode(input, alphabet: alphabet)
        case .toText: return MorseCode.decode(input, alphabet: alphabet)
        }
    }

    private var placeholder: String {
        switch direction {
        case .toMorse: return "Текст, напр. «привет»"
        case .toText: return "Код, напр. «.--. .-. .. .-- . -»"
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
        .cipherToolChrome(title: "Азбука Морзе")
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Направление")
            Picker("Направление", selection: $direction) {
                Text("Код → текст").tag(Direction.toText)
                Text("Текст → код").tag(Direction.toMorse)
            }
            .pickerStyle(.segmented)

            SectionTitle("Алфавит")
            CipherLanguagePicker(selection: $alphabet)
        }
        .sectionPanel()
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(direction == .toMorse ? "Текст" : "Код Морзе")
            CipherInputField(placeholder: placeholder, text: $input)
        }
        .sectionPanel()
    }

    private var hintSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Точка — «.», тире — «-». Буквы разделяются пробелом, слова — «/».")
                .font(.caption)
                .foregroundStyle(GameTheme.muted)
            Text("Распознаются также символы «·», «•», «—», «–» и «−».")
                .font(.caption)
                .foregroundStyle(GameTheme.muted)
        }
        .sectionPanel()
    }
}

#Preview {
    NavigationStack {
        MorseView()
    }
}
