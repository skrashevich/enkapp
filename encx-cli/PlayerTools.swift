import SwiftUI

/// Единый реестр игровых утилит. Добавление новой утилиты =
/// один `case` + ветка в вычисляемых свойствах + View в `destination`.
enum PlayerTool: String, CaseIterable, Identifiable {
    case anagramizer
    // Следующие утилиты добавлять здесь, напр.: case caesar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anagramizer: return "Анаграмайзер"
        }
    }

    var subtitle: String {
        switch self {
        case .anagramizer: return "Поиск слов по шаблону, буквам или их сочетанию."
        }
    }

    var systemImage: String {
        switch self {
        case .anagramizer: return "textformat.abc.dottedunderline"
        }
    }

    var tint: Color {
        switch self {
        case .anagramizer: return GameTheme.bonusTitle
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .anagramizer: AnagramizerView()
        }
    }
}

/// Шторка со списком утилит. Открывается поверх любого экрана.
struct ToolsHubView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
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

#Preview {
    ToolsHubView()
}
