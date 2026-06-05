import SwiftUI

struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(.secondary)
    }
}

extension View {
    func sectionPanel() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct GameActionRow: View {
    let game: GameInfo
    let badge: String
    let model: EncounterViewModel

    private var gameID: Int64 { Int64(game.id) }

    private var isActive: Bool {
        model.isGameActive(game)
    }

    private var isCurrentJoinedGame: Bool {
        guard model.selectedGameID == gameID,
              let current = model.currentModel,
              current.gameID == game.id else {
            return false
        }
        return !model.needsGameEntry(current)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Task { await model.openGame(gameID) }
            } label: {
                GameRow(game: game, badge: badge)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)

            Button {
                Task { await model.openGame(gameID) }
            } label: {
                Image(systemName: isActive && isCurrentJoinedGame ? "play.fill" : "chevron.right.circle.fill")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.borderedProminent)
            .tint(isActive && isCurrentJoinedGame ? .green : .accentColor)
            .disabled(model.isBusy)
            .accessibilityLabel(isActive && isCurrentJoinedGame ? "Открыть игру" : "Перейти к игре")
        }
    }
}

struct DomainGameActionRow: View {
    let game: DomainGame
    let model: EncounterViewModel

    private var gameID: Int64 { Int64(game.id) }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Task { await model.openGame(gameID) }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(game.title).font(.body)
                        Text(verbatim: "#\(String(game.id))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)

            Button {
                Task { await model.openGame(gameID) }
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)
            .disabled(model.isBusy)
            .accessibilityLabel("Перейти к игре")
        }
        .task(id: gameID) {
            await model.ensureGameModerationLoadedForUI(gameID: gameID)
        }
    }
}

struct GameRow: View {
    let game: GameInfo
    let badge: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(game.title)
                    .font(.body)
                Spacer()
                Text(badge)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(verbatim: "#\(game.displayNumberText) / \(game.description.strippingHTML())")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

struct DetailBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text.isEmpty ? "Нет данных" : text)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}

struct StatusRow: View {
    let title: String
    let value: String
    let isDone: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isDone ? .green : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(isDone ? .green : .secondary)
            }
        }
    }
}
