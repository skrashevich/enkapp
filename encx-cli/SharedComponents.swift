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

    private var isActive: Bool {
        model.isGameActive(game)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Task { await openSelectedGame() }
            } label: {
                GameRow(game: game, badge: badge)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)

            if isActive {
                Button {
                    Task { await model.openGame(Int64(game.id)) }
                } label: {
                    Image(systemName: "play.fill")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(model.isBusy)
                .accessibilityLabel("Войти в игру")
            } else {
                Button {
                    Task { await model.submitGameApplication(Int64(game.id)) }
                } label: {
                    Image(systemName: "person.badge.plus")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy || !model.hasStoredSession)
                .accessibilityLabel("Подать заявку на игру")
            }
        }
    }

    private func openSelectedGame() async {
        if isActive {
            await model.openGame(Int64(game.id))
        } else {
            await model.enterGame(Int64(game.id))
        }
    }
}

struct DomainGameActionRow: View {
    let game: DomainGame
    let model: EncounterViewModel

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Task { await model.openGame(Int64(game.id)) }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(game.title).font(.body)
                        Text("#\(game.id)")
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
                Task { await model.submitGameApplication(Int64(game.id)) }
            } label: {
                Image(systemName: "person.badge.plus")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)
            .disabled(model.isBusy || !model.hasStoredSession)
            .accessibilityLabel("Подать заявку на игру")
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
            Text("#\(game.id) / \(game.description.strippingHTML())")
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
