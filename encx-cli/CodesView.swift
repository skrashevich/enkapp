import SwiftUI
import Observation
import UIKit

struct CodesView: View {
    @Bindable var model: EncounterViewModel
    @State private var copiedActionID: Int?

    private var loggedActionsNewestFirst: [CodeAction] {
        model.codeLogActions.sorted {
            if $0.levelNumber != $1.levelNumber {
                return $0.levelNumber > $1.levelNumber
            }
            return $0.actionID > $1.actionID
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                pendingSection
                logSection
            }
            .padding()
        }
        .background(GameTheme.background)
        .navigationTitle("Журнал кодов")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await model.flushQueue()
            await model.refreshCodeLog()
            await model.refreshLevel()
        }
        .task(id: model.currentModel?.gameID) {
            await model.refreshCodeLog()
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
            return "Сеть есть, но сервер игры не отвечает. Коды сохранены, повтор с паузой до 8 сек."
        case .ready:
            return "Отправятся автоматически каждые 0.4 сек. Таймаут одной попытки — 1 сек."
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                GameSectionHeader(title: "Пробитые коды (\(loggedActionsNewestFirst.count))")
                Spacer()
                if model.isCodeLogLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if !model.codeLogStatusMessage.isEmpty {
                Text(model.codeLogStatusMessage)
                    .font(.subheadline)
                    .foregroundStyle(GameTheme.muted)
            }

            if loggedActionsNewestFirst.isEmpty && !model.isCodeLogLoading && model.codeLogStatusMessage.isEmpty {
                Text("Пробитых кодов пока нет")
                    .font(.subheadline)
                    .foregroundStyle(GameTheme.muted)
            } else {
                ForEach(loggedActionsNewestFirst) { action in
                    sentCodeRow(action)
                }
            }
        }
    }

    private func sentCodeRow(_ action: CodeAction) -> some View {
        let resultColor = action.isCorrect ? GameTheme.accent : GameTheme.muted

        return Button {
            copyCode(action.answer, actionID: action.id)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: action.isCorrect ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(resultColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(action.answer)
                        .font(.body.monospaced())
                        .foregroundStyle(action.isCorrect ? GameTheme.accent : GameTheme.text)
                    Text("Ур. \(action.levelNumber) · \(action.login), \(action.locDateTime)")
                        .font(.caption)
                        .foregroundStyle(GameTheme.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: copiedActionID == action.id ? "checkmark" : "doc.on.doc")
                    .font(.subheadline)
                    .foregroundStyle(copiedActionID == action.id ? GameTheme.accent : GameTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(GameTheme.panel, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(action.isCorrect ? GameTheme.accent.opacity(0.55) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                copyCode(action.answer, actionID: action.id)
            } label: {
                Label("Копировать", systemImage: "doc.on.doc")
            }
        }
        .sensoryFeedback(.success, trigger: copiedActionID)
    }

    private func copyCode(_ code: String, actionID: Int) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UIPasteboard.general.string = trimmed
        copiedActionID = actionID
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedActionID == actionID {
                copiedActionID = nil
            }
        }
    }
}
