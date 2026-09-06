import SwiftUI
import Observation
import UIKit

struct CodesView: View {
    @Bindable var model: EncounterViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var copiedActionID: Int?
    @State private var codeLogShareURL: URL?
    @State private var codeLogExportError: String?
    @State private var showCodeLogShareSheet = false
    @State private var showClearQueueConfirmation = false
    @State private var codeDraft = ""
    @FocusState private var codeFieldFocused: Bool

    private var codeLogSnapshot: CodeLogSnapshot {
        let actions = model.codeLogActions.sorted {
            if $0.levelNumber != $1.levelNumber {
                return $0.levelNumber > $1.levelNumber
            }
            if $0.actionID != $1.actionID { return $0.actionID > $1.actionID }
            // Every synthetic action has actionID 0; tie-break on id so the order is stable
            // across launches (Dictionary.values order and sorted() are both unstable).
            return $0.id > $1.id
        }

        var groups: [CodeActionLevelGroup] = []
        for action in actions {
            if groups.last?.levelNumber == action.levelNumber {
                groups[groups.count - 1].actions.append(action)
            } else {
                groups.append(CodeActionLevelGroup(levelNumber: action.levelNumber, actions: [action]))
            }
        }

        return CodeLogSnapshot(actions: actions, groups: groups)
    }

    var body: some View {
        let snapshot = codeLogSnapshot
        let showsEmptyState = snapshot.actions.isEmpty
            && !model.isCodeLogLoading
            && model.codeLogStatusMessage.isEmpty
        let hasLogContent = !model.codeLogStatusMessage.isEmpty
            || showsEmptyState
            || !snapshot.groups.isEmpty

        VStack(spacing: 0) {
            header
            serviceLine

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    pendingSection
                        .padding(.bottom, 22)

                    if snapshot.groups.isEmpty {
                        sectionLabel(
                            title: "ПРОБИТЫЕ КОДЫ",
                            titleColor: GameTheme.sectionHeader,
                            hint: nil
                        )
                        .padding(.bottom, hasLogContent ? 10 : 0)
                    }

                    if !model.codeLogStatusMessage.isEmpty {
                        Text(model.codeLogStatusMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(GameTheme.muted)
                            .padding(.bottom, snapshot.groups.isEmpty ? 0 : 12)
                    }

                    if showsEmptyState {
                        Text("Пробитых кодов пока нет")
                            .font(.system(size: 13))
                            .foregroundStyle(GameTheme.muted)
                    }

                    ForEach(Array(snapshot.groups.enumerated()), id: \.element.id) { index, group in
                        logGroupHeader(group, isFirst: index == 0)
                            .padding(.bottom, 10)

                        ForEach(group.actions) { action in
                            sentCodeRow(action)
                                .padding(
                                    .bottom,
                                    logRowBottomPadding(
                                        action: action,
                                        in: group,
                                        groups: snapshot.groups
                                    )
                                )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            .refreshable {
                await model.flushQueue()
                await model.refreshLevel()
                await model.refreshCodeLog()
            }
        }
        .background(GameTheme.background)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            codeInputBar
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
        .confirmationDialog(
            "Очистить очередь кодов?",
            isPresented: $showClearQueueConfirmation,
            titleVisibility: .visible
        ) {
            Button("Очистить очередь", role: .destructive) {
                model.clearQueue()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Неотправленные коды будут удалены безвозвратно.")
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

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "arrow.backward")
                    .font(.system(size: 22))
                    .foregroundStyle(GameTheme.text)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Назад")

            Text("Журнал кодов")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(GameTheme.text)

            Spacer(minLength: 8)

            Button {
                exportCodeLog()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 21))
                    .foregroundStyle(model.codeLogActions.isEmpty ? GameTheme.muted : GameTheme.text)
            }
            .buttonStyle(.plain)
            .disabled(model.codeLogActions.isEmpty)
            .accessibilityLabel("Экспортировать")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var serviceLine: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 7, height: 7)

            Text(serviceStatusText)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                Text("в очереди \(model.queue.pending.count)")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(GameTheme.sectionHeader)
                Text("·")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.3))
                Text("пробито \(solvedCodeCount)")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
            }
            .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private var statusDotColor: Color {
        model.queueConnectionStatus == .ready ? GameTheme.accent : .orange
    }

    private var serviceStatusText: String {
        switch model.queueConnectionStatus {
        case .ready:
            if let serverRoundTripMs = model.serverRoundTripMs {
                return "Сервер отвечает · \(serverRoundTripMs) мс"
            }
            return "Сервер отвечает"
        case .offline, .serverUnreachable:
            return model.queueConnectionStatus.label
        }
    }

    private var solvedCodeCount: Int {
        model.codeLogActions.reduce(into: 0) { total, action in
            if action.isCorrect { total += 1 }
        }
    }

    // MARK: - Pending queue

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(
                title: "ОЖИДАЮТ ОТПРАВКИ",
                titleColor: GameTheme.sectionHeader,
                hint: "таймаут попытки \(EncounterTimeouts.codeSendSeconds) сек."
            )

            if model.queue.pending.isEmpty {
                Text("Нет кодов в очереди")
                    .font(.system(size: 13))
                    .foregroundStyle(GameTheme.muted)
            } else {
                ForEach(model.queue.pending) { item in
                    pendingRow(item)
                }

                HStack(spacing: 18) {
                    Button("Отправить сейчас") {
                        Task { await model.flushQueue() }
                    }
                    .foregroundStyle(GameTheme.accent)
                    .disabled(model.isBusy)

                    Button("Очистить очередь") {
                        showClearQueueConfirmation = true
                    }
                    .foregroundStyle(.white.opacity(0.4))

                    Spacer(minLength: 0)
                }
                .font(.system(size: 14, weight: .semibold))
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }

    private func pendingRow(_ item: CodeSubmission) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "clock")
                .font(.system(size: 17))
                .foregroundStyle(GameTheme.sectionHeader)

            Text(item.code)
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .tracking(0.68)
                .foregroundStyle(GameTheme.text)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text("Уровень \(item.levelNumber)")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GameTheme.sectionHeader.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(GameTheme.sectionHeader.opacity(0.28), lineWidth: 1)
        }
    }

    // MARK: - Sent code log

    private func sectionLabel(title: String, titleColor: Color, hint: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(titleColor)

            Spacer(minLength: 8)

            if let hint {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func logGroupHeader(_ group: CodeActionLevelGroup, isFirst: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if isFirst {
                sectionLabel(
                    title: "ПРОБИТЫЕ КОДЫ · УРОВЕНЬ \(group.levelNumber)",
                    titleColor: GameTheme.sectionHeader,
                    hint: "тап — копировать"
                )
            } else {
                Text("Уровень \(group.levelNumber)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer(minLength: 8)
            }

            if isFirst, model.isCodeLogLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private func logRowBottomPadding(
        action: CodeAction,
        in group: CodeActionLevelGroup,
        groups: [CodeActionLevelGroup]
    ) -> CGFloat {
        guard action.id == group.actions.last?.id else { return 8 }
        return group.id == groups.last?.id ? 0 : 16
    }

    private func sentCodeRow(_ action: CodeAction) -> some View {
        let isCopied = copiedActionID == action.id

        return Button {
            copyCode(action.answer, actionID: action.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: action.isCorrect ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(action.isCorrect ? GameTheme.accent : .white.opacity(0.3))

                Text(action.answer)
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .tracking(0.68)
                    .foregroundStyle(action.isCorrect ? GameTheme.accent : .white.opacity(0.7))
                    .strikethrough(!action.isCorrect, color: .white.opacity(0.3))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(timestampLabel(action))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)

                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 17))
                    .foregroundStyle(isCopied ? GameTheme.accent : .white.opacity(0.35))
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                action.isCorrect ? GameTheme.accent.opacity(0.10) : Color(white: 0.063),
                in: RoundedRectangle(cornerRadius: 11)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(
                        action.isCorrect ? GameTheme.accent.opacity(0.45) : Color(white: 0.15),
                        lineWidth: 1
                    )
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

    private func timestampLabel(_ action: CodeAction) -> String {
        action.locDateTime.isEmpty ? action.login : "\(action.login) · \(action.locDateTime)"
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

    // MARK: - Code input

    private var codeInputBar: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                if codeDraft.isEmpty {
                    Text("КОД")
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.32))
                }

                TextField("", text: $codeDraft)
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(GameTheme.text)
                    .tint(GameTheme.accent)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .focused($codeFieldFocused)
                    .onSubmit(submitCodeDraft)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
            .background(GameTheme.fieldFill, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(GameTheme.fieldStroke, lineWidth: 1)
            }

            Button(action: submitCodeDraft) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        canSubmitCode ? GameTheme.accent : GameTheme.fieldFill,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmitCode)
            .accessibilityLabel("Отправить код")
            .accessibilityHint("Отправить как ответ на текущий уровень")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(GameTheme.background)
    }

    private var canSubmitCode: Bool {
        let hasText = !codeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasText, let level = model.currentModel?.level else { return false }
        return model.canSubmitLevelCode(on: level)
    }

    private func submitCodeDraft() {
        let trimmed = codeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let level = model.currentModel?.level, !model.canSubmitLevelCode(on: level) {
            // Let the model publish the precise reason, but keep the unsent draft intact.
            model.submitCode(trimmed, kind: .level)
            return
        }
        codeDraft = ""
        model.submitCode(trimmed, kind: .level)
    }

    // MARK: - Export

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
    var actions: [CodeAction]

    var id: Int { levelNumber }
}

private struct CodeLogSnapshot {
    let actions: [CodeAction]
    let groups: [CodeActionLevelGroup]
}
