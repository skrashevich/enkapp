import SwiftUI
import Observation
import UIKit

struct CodesView: View {
    @Bindable var model: EncounterViewModel
    @State private var copiedActionID: Int?
    @State private var codeLogShareURL: URL?
    @State private var codeLogExportError: String?
    @State private var showCodeLogShareSheet = false

    private var loggedActionsNewestFirst: [CodeAction] {
        model.codeLogActions.sorted {
            if $0.levelNumber != $1.levelNumber {
                return $0.levelNumber > $1.levelNumber
            }
            return $0.actionID > $1.actionID
        }
    }

    private var loggedActionGroups: [CodeActionLevelGroup] {
        Dictionary(grouping: loggedActionsNewestFirst, by: \.levelNumber)
            .map { CodeActionLevelGroup(levelNumber: $0.key, actions: $0.value) }
            .sorted { $0.levelNumber > $1.levelNumber }
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    exportCodeLog()
                } label: {
                    Label("Экспортировать", systemImage: "square.and.arrow.up")
                }
                .disabled(model.codeLogActions.isEmpty)
            }
        }
        .sheet(isPresented: $showCodeLogShareSheet, onDismiss: {
            if let codeLogShareURL {
                try? FileManager.default.removeItem(at: codeLogShareURL)
            }
            codeLogShareURL = nil
        }) {
            if let codeLogShareURL {
                ShareSheet(items: [codeLogShareURL])
            }
        }
        .alert("Не удалось экспортировать журнал", isPresented: codeLogExportErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(codeLogExportError ?? "")
        }
        .refreshable {
            await model.flushQueue()
            await model.refreshLevel()
            await model.refreshCodeLog()
        }
        .task(id: model.currentModel?.gameID) {
            await model.refreshCodeLog()
        }
        .task(id: model.selectedGameID) {
            if model.queueConnectionStatus == .ready, model.queue.pending.isEmpty {
                await model.measureServerLatency()
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
            return "Отправятся автоматически. Таймаут одной попытки — \(EncounterTimeouts.codeSendSeconds) сек."
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
                ForEach(loggedActionGroups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Уровень \(group.levelNumber)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(GameTheme.sectionHeader)

                        ForEach(group.actions) { action in
                            sentCodeRow(action)
                        }
                    }
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
                    Text("\(action.login), \(action.locDateTime)")
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

    private var codeLogExportErrorPresented: Binding<Bool> {
        Binding(
            get: { codeLogExportError != nil },
            set: { if !$0 { codeLogExportError = nil } }
        )
    }

    private func exportCodeLog() {
        codeLogExportError = nil
        do {
            let url = try model.exportCodeLogFileURL()
            codeLogShareURL = url
            showCodeLogShareSheet = true
        } catch {
            codeLogExportError = error.localizedDescription
        }
    }
}

private struct CodeActionLevelGroup: Identifiable {
    let levelNumber: Int
    let actions: [CodeAction]

    var id: Int { levelNumber }
}
