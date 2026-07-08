import SwiftUI
import UIKit

/// Многострочное поле ввода в едином стиле утилит.
struct CipherInputField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .lineLimit(2...6)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .foregroundStyle(GameTheme.text)
            .padding(12)
            .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Сегментированный переключатель языка алфавита (RU/EN).
struct CipherLanguagePicker: View {
    @Binding var selection: CipherAlphabet

    var body: some View {
        Picker("Алфавит", selection: $selection) {
            ForEach(CipherAlphabet.allCases) { alphabet in
                Text(alphabet.title).tag(alphabet)
            }
        }
        .pickerStyle(.segmented)
    }
}

/// Панель результата с кнопкой копирования в буфер обмена.
struct CipherResultCard: View {
    var title: String = "Результат"
    let text: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle(title)
                Spacer()
                if !text.isEmpty {
                    Button {
                        copy()
                    } label: {
                        Label(copied ? "Скопировано" : "Копировать",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(copied ? GameTheme.accent : GameTheme.muted)
                }
            }

            if text.isEmpty {
                Text("—")
                    .font(.body)
                    .foregroundStyle(GameTheme.muted)
            } else {
                Text(text)
                    .font(.body.monospaced())
                    .foregroundStyle(GameTheme.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sectionPanel()
        .sensoryFeedback(.success, trigger: copied)
    }

    private func copy() {
        UIPasteboard.general.string = text
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

/// Тумблер «ё — отдельная буква» для русского алфавита (33 против 32).
struct YoToggleRow: View {
    @Binding var includeYo: Bool

    var body: some View {
        DashboardSettingsRow(
            title: "Считать «ё» отдельной буквой",
            subtitle: "33 буквы. Выключите — «ё» приравнивается к «е» (32 буквы).",
            systemImage: "textformat.abc",
            tint: GameTheme.bonusTitle
        ) {
            Toggle("", isOn: $includeYo)
                .labelsHidden()
                .tint(GameTheme.accent)
        }
    }
}

/// Общий фон/навигация для экрана-утилиты, чтобы не дублировать модификаторы.
extension View {
    func cipherToolChrome(title: String) -> some View {
        self
            .background(GameTheme.background)
            .scrollContentBackground(.hidden)
            .preferredColorScheme(.dark)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GameTheme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
