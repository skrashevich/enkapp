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

                ForEach(level.sectors.sortedForDisplay) { sector in
                    StatusRow(
                        title: sector.name.isEmpty ? "Сектор \(sector.displayOrder)" : sector.name,
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

struct LevelHelpsSection: View {
    let helps: [Help]
    let penaltyHelps: [Help]
    var onRequestPenaltyHelp: ((Help) -> Void)?

    @State private var syncedAt = Date()
    @State private var pendingPenaltyHelp: Help?

    private var syncKey: String {
        (helps + penaltyHelps)
            .sorted { $0.helpID < $1.helpID }
            .map { "\($0.helpID):\($0.remainSeconds):\($0.helpText ?? "")" }
            .joined(separator: "|")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GameSectionHeader(
                title: "Подсказки (\(helps.count + penaltyHelps.count))"
            )

            ForEach(helps.sorted(by: { $0.number < $1.number })) { help in
                HelpRow(help: help, title: "Подсказка \(help.number)", syncedAt: syncedAt)
                    .sectionPanel()
            }

            if !penaltyHelps.isEmpty {
                if !helps.isEmpty {
                    Text("Штрафные подсказки")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GameTheme.muted)
                        .padding(.top, 4)
                }

                ForEach(penaltyHelps.sorted(by: { $0.number < $1.number })) { help in
                    HelpRow(
                        help: help,
                        title: "Штраф \(GameDurationFormatter.minutesAndSeconds(help.penalty))",
                        syncedAt: syncedAt,
                        fallbackText: help.penaltyMessage ?? "Требуется запрос",
                        onRequestPenaltyHelp: onRequestPenaltyHelp.map { request in
                            {
                                if help.requestConfirm {
                                    pendingPenaltyHelp = help
                                } else {
                                    request(help)
                                }
                            }
                        }
                    )
                    .sectionPanel()
                }
            }
        }
        .onAppear { syncedAt = Date() }
        .onChange(of: syncKey) { _, _ in
            syncedAt = Date()
        }
        .confirmationDialog(
            "Открыть штрафную подсказку?",
            isPresented: Binding(
                get: { pendingPenaltyHelp != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingPenaltyHelp = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let help = pendingPenaltyHelp {
                Button("Открыть со штрафом \(GameDurationFormatter.minutesAndSeconds(help.penalty))", role: .destructive) {
                    onRequestPenaltyHelp?(help)
                    pendingPenaltyHelp = nil
                }
            }
            Button("Отмена", role: .cancel) {
                pendingPenaltyHelp = nil
            }
        } message: {
            Text(pendingPenaltyHelp?.penaltyMessage ?? "После открытия подсказки команда получит штраф.")
        }
    }
}

private struct HelpRow: View {
    let help: Help
    let title: String
    let syncedAt: Date
    var fallbackText: String?
    var onRequestPenaltyHelp: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(GameTheme.bonusTitle)

            if let text = help.unlockedText {
                helpContent(text)
            } else if help.remainSeconds > 0 {
                TickingCountdownText(
                    countdown: SyncedSecondsCountdown(
                        remainSeconds: help.remainSeconds,
                        syncedAt: syncedAt
                    ),
                    label: GameDurationFormatter.helpUnlockLabel
                )
                .font(.body)
                .foregroundStyle(GameTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let fallbackText, !fallbackText.isEmpty {
                helpContent(fallbackText)
            } else {
                Text("Открывается…")
                    .font(.body)
                    .foregroundStyle(GameTheme.muted)
            }

            if help.canRequestPenalty, let onRequestPenaltyHelp {
                Button {
                    onRequestPenaltyHelp()
                } label: {
                    Label("Открыть штрафную подсказку", systemImage: "exclamationmark.triangle")
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func helpContent(_ text: String) -> some View {
        if text.contains("<") {
            EncounterHTMLView(html: text)
        } else {
            CoordinateText(text: text.strippingHTML())
                .font(.body)
                .foregroundStyle(GameTheme.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
