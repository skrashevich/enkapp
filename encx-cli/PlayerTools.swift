import SwiftUI

/// Единый реестр игровых утилит. Добавление новой утилиты =
/// один `case` + ветка в вычисляемых свойствах + View в `destination`.
enum PlayerTool: String, CaseIterable, Identifiable {
    case anagramizer
    case caesar
    case vigenere
    case morse
    case atbash
    case letterNumber
    case keyboardLayout

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anagramizer: return "Анаграмайзер"
        case .caesar: return "Шифр Цезаря"
        case .vigenere: return "Шифр Виженера"
        case .morse: return "Азбука Морзе"
        case .atbash: return "Атбаш"
        case .letterNumber: return "Код букв (A1Z26)"
        case .keyboardLayout: return "Раскладка клавиатуры"
        }
    }

    var subtitle: String {
        switch self {
        case .anagramizer: return "Поиск слов по шаблону, буквам или их сочетанию."
        case .caesar: return "Сдвиг букв алфавита и перебор всех сдвигов. RU и EN."
        case .vigenere: return "Многоалфавитный шифр по ключевому слову. RU и EN."
        case .morse: return "Кодирование и декодирование Морзе. RU и EN."
        case .atbash: return "Зеркальная замена букв в алфавите. RU и EN."
        case .letterNumber: return "Замена букв их номерами в алфавите и обратно."
        case .keyboardLayout: return "Исправление текста, набранного не в той раскладке."
        }
    }

    var systemImage: String {
        switch self {
        case .anagramizer: return "textformat.abc.dottedunderline"
        case .caesar: return "arrow.left.arrow.right.circle"
        case .vigenere: return "key.horizontal"
        case .morse: return "dot.radiowaves.left.and.right"
        case .atbash: return "arrow.left.and.right.righttriangle.left.righttriangle.right"
        case .letterNumber: return "number.circle"
        case .keyboardLayout: return "keyboard"
        }
    }

    var tint: Color {
        switch self {
        case .anagramizer: return GameTheme.bonusTitle
        case .caesar: return GameTheme.accent
        case .vigenere: return GameTheme.bonusTitle
        case .morse: return GameTheme.sectionHeader
        case .atbash: return GameTheme.bonusTitle
        case .letterNumber: return GameTheme.accent
        case .keyboardLayout: return GameTheme.sectionHeader
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .anagramizer: AnagramizerView()
        case .caesar: CaesarView()
        case .vigenere: VigenereView()
        case .morse: MorseView()
        case .atbash: AtbashView()
        case .letterNumber: LetterNumberView()
        case .keyboardLayout: KeyboardLayoutView()
        }
    }
}

/// Шторка со списком утилит. Открывается поверх любого экрана.
struct ToolsHubView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ToolsHubContent()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Готово") { dismiss() }
                            .tint(GameTheme.text)
                    }
                }
                .toolbarBackground(GameTheme.background, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

/// Список утилит для общей навигации приложения и модального окна.
struct ToolsHubContent: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(PlayerTool.allCases) { tool in
                    NavigationLink {
                        tool.destination
                    } label: {
                        DashboardSettingsRow(
                            title: tool.title,
                            subtitle: tool.subtitle,
                            systemImage: tool.systemImage,
                            tint: tool.tint
                        ) {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(GameTheme.muted)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(GameTheme.background)
        .scrollContentBackground(.hidden)
        .navigationTitle("Инструменты")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(GameTheme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

#Preview {
    ToolsHubView()
}
