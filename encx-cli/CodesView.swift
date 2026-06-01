import SwiftUI
import Observation

struct CodesView: View {
    @Bindable var model: EncounterViewModel
    let sentActions: [CodeAction]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                pendingSection
                if !sentActions.isEmpty {
                    sentSection
                }
            }
            .padding()
        }
        .background(GameTheme.background)
        .navigationTitle("Коды")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await model.flushQueue()
            await model.refreshLevel()
        }
        .task(id: model.selectedGameID) {
            while !Task.isCancelled {
                if model.queueConnectionStatus == .ready, model.queue.pending.isEmpty {
                    await model.measureServerLatency()
                }
                let seconds = model.queue.pending.isEmpty ? 4.0 : 1.0
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GameSectionHeader(title: "Ожидают отправки")

            HStack {
                Label(
                    model.codesConnectionStatusLabel,
                    systemImage: model.queueConnectionStatus.systemImage
                )
                .foregroundStyle(connectionStatusColor)
                Spacer()
                Text("\(model.queue.pending.count)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(GameTheme.sectionHeader)
            }
            .font(.subheadline)

            if model.queue.pending.isEmpty {
                Text("Нет кодов в очереди")
                    .font(.subheadline)
                    .foregroundStyle(GameTheme.muted)
            } else {
                Text(pendingHint)
                    .font(.caption)
                    .foregroundStyle(GameTheme.muted)

                ForEach(model.queue.pending) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.code)
                            .font(.body.monospaced())
                            .foregroundStyle(GameTheme.text)
                        Text("Уровень \(item.levelNumber)")
                            .font(.caption)
                            .foregroundStyle(GameTheme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(GameTheme.panel, in: RoundedRectangle(cornerRadius: 8))
                }
            }

            HStack {
                Button {
                    Task { await model.flushQueue() }
                } label: {
                    Label("Отправить", systemImage: "tray.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .tint(GameTheme.accent)
                .disabled(model.queue.pending.isEmpty || model.isBusy)

                Spacer()

                Button(role: .destructive) {
                    model.clearQueue()
                } label: {
                    Label("Очистить", systemImage: "trash")
                }
                .disabled(model.queue.pending.isEmpty)
            }
        }
    }

    private var connectionStatusColor: Color {
        switch model.queueConnectionStatus {
        case .ready: return GameTheme.text
        case .offline, .serverUnreachable: return .orange
        }
    }

    private var pendingHint: String {
        switch model.queueConnectionStatus {
        case .offline:
            return "Отправка возобновится, когда появится сеть."
        case .serverUnreachable:
            return "Сеть есть, но сервер игры не отвечает. Коды сохранены, повтор каждые 0.4 сек."
        case .ready:
            return "Отправятся автоматически каждые 0.4 сек. Таймаут одной попытки — 1 сек."
        }
    }

    private var sentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GameSectionHeader(title: "Отправленные на уровне (\(sentActions.count))")

            ForEach(sentActions) { action in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: action.isCorrect ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(action.isCorrect ? GameTheme.accent : GameTheme.muted)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(action.answer)
                            .font(.body.monospaced())
                            .foregroundStyle(GameTheme.text)
                        Text("\(action.login), \(action.locDateTime)")
                            .font(.caption)
                            .foregroundStyle(GameTheme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(GameTheme.panel, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
