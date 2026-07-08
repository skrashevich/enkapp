import SwiftUI
import UIKit

/// Шифр Цезаря: сдвиг букв на заданное число позиций + перебор всех сдвигов.
struct CaesarView: View {
    @State private var input = ""
    @State private var alphabet: CipherAlphabet = .ru
    @State private var includeYo = true
    @State private var shift = 3
    @State private var copiedShift: Int?

    private var currentAlphabet: [Character] {
        alphabet == .ru ? CipherAlphabet.ru.letters(includeYo: includeYo) : CipherAlphabet.en.letters()
    }

    private var output: String {
        CaesarCipher.shift(input, by: shift, alphabet: currentAlphabet)
    }

    private var allShifts: [CaesarShiftResult] {
        guard !input.isEmpty else { return [] }
        return CaesarCipher.allShifts(input, alphabet: currentAlphabet)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                settingsSection
                inputSection
                CipherResultCard(text: output)
                bruteForceSection
            }
            .padding()
        }
        .cipherToolChrome(title: "Шифр Цезаря")
        .onChange(of: alphabet) { _, _ in clampShift() }
        .onChange(of: includeYo) { _, _ in clampShift() }
    }

    private func clampShift() {
        let maxShift = max(1, currentAlphabet.count - 1)
        shift = min(shift, maxShift)
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
            CipherInputField(placeholder: "Текст для шифровки/дешифровки", text: $input)

            HStack {
                Text("Сдвиг: \(shift)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GameTheme.text)
                Spacer()
                Stepper("Сдвиг", value: $shift, in: 1...(currentAlphabet.count - 1))
                    .labelsHidden()
                    .tint(GameTheme.accent)
            }
        }
        .sectionPanel()
    }

    private var bruteForceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Все сдвиги")
            if allShifts.isEmpty {
                Text("Введите текст, чтобы увидеть перебор всех сдвигов.")
                    .font(.caption)
                    .foregroundStyle(GameTheme.muted)
            } else {
                ForEach(allShifts, id: \.shift) { item in
                    Button {
                        copy(item.text, shift: item.shift)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(item.shift)")
                                .font(.caption.monospaced().weight(.bold))
                                .foregroundStyle(GameTheme.bonusTitle)
                                .frame(width: 24, alignment: .trailing)
                            Text(item.text)
                                .font(.body.monospaced())
                                .foregroundStyle(GameTheme.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: copiedShift == item.shift ? "checkmark" : "doc.on.doc")
                                .font(.caption)
                                .foregroundStyle(copiedShift == item.shift ? GameTheme.accent : GameTheme.muted)
                        }
                        .padding(10)
                        .background(GameTheme.panel, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sectionPanel()
        .sensoryFeedback(.success, trigger: copiedShift)
    }

    private func copy(_ text: String, shift: Int) {
        UIPasteboard.general.string = text
        copiedShift = shift
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedShift == shift {
                copiedShift = nil
            }
        }
    }
}

#Preview {
    NavigationStack {
        CaesarView()
    }
}
