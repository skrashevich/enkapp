import SwiftUI

struct LevelTasksScreen: View {
    let level: Level

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let task = level.task {
                    DetailBlock(title: "Текущее", text: task.displayText)
                        .sectionPanel()
                }

                ForEach(Array(level.tasks.enumerated()), id: \.offset) { index, task in
                    DetailBlock(title: "Задание \(index + 1)", text: task.displayText)
                        .sectionPanel()
                }
            }
            .padding()
        }
        .background(GameTheme.background)
        .navigationTitle("Задания")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LevelMessagesScreen: View {
    let messages: [AdminMessage]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(messages) { message in
                    DetailBlock(title: message.ownerLogin, text: message.displayText)
                        .sectionPanel()
                }
            }
            .padding()
        }
        .background(GameTheme.background)
        .navigationTitle("Сообщения")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LevelSectorsScreen: View {
    let level: Level

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("Закрыто \(level.passedSectorsCount) из \(level.requiredSectorsCount)")
                    .font(.subheadline)
                    .foregroundStyle(GameTheme.muted)

                ForEach(level.sectors) { sector in
                    StatusRow(
                        title: sector.name.isEmpty ? "Сектор \(sector.order)" : sector.name,
                        value: sector.isAnswered ? sector.answer : "код не введён",
                        isDone: sector.isAnswered
                    )
                    .sectionPanel()
                }
            }
            .padding()
        }
        .background(GameTheme.background)
        .navigationTitle("Секторы")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LevelHelpsScreen: View {
    let helps: [Help]
    let penaltyHelps: [Help]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if !helps.isEmpty {
                    GameSectionHeader(title: "Подсказки")
                    ForEach(helps) { help in
                        DetailBlock(
                            title: "Подсказка \(help.number)",
                            text: help.helpText?.strippingHTML() ?? "Откроется через \(help.remainSeconds) сек."
                        )
                        .sectionPanel()
                    }
                }

                if !penaltyHelps.isEmpty {
                    GameSectionHeader(title: "Штрафные подсказки")
                    ForEach(penaltyHelps) { help in
                        DetailBlock(
                            title: "Штраф \(help.penalty) сек.",
                            text: help.helpText?.strippingHTML() ?? help.penaltyMessage ?? "Требуется запрос"
                        )
                        .sectionPanel()
                    }
                }
            }
            .padding()
        }
        .background(GameTheme.background)
        .navigationTitle("Подсказки")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LevelBonusesScreen: View {
    let level: Level

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("Закрыто \(level.passedBonusesCount) из \(level.bonuses.count)")
                    .font(.subheadline)
                    .foregroundStyle(GameTheme.muted)

                ForEach(level.bonuses) { bonus in
                    DetailBlock(
                        title: bonus.isAnswered ? "\(bonus.name) ✓" : bonus.name,
                        text: [bonus.task, bonus.help, bonus.answer]
                            .filter { !$0.isEmpty }
                            .joined(separator: "\n\n")
                            .strippingHTML()
                    )
                    .sectionPanel()
                }
            }
            .padding()
        }
        .background(GameTheme.background)
        .navigationTitle("Бонусы")
        .navigationBarTitleDisplayMode(.inline)
    }
}
