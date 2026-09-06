import SwiftUI
import Observation

struct LevelPlayView: View {
    @Bindable var model: EncounterViewModel
    @State private var codeDraft = ""
    @State private var previousCodeDraft = ""
    @FocusState private var codeFieldFocused: Bool
    @State private var codeResultToast: CodeResultFeedback?
    @State private var codeResultDismissTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let game = model.currentModel, game.isGameComplete {
                finishedState(game: game)
            } else if let game = model.currentModel, let level = game.level {
                gameScreen(game: game, level: level)
            } else if let game = model.currentModel {
                waitingState(game: game)
            } else {
                emptyState
            }
        }
        .background(GameTheme.background)
        .refreshable {
            await model.refreshLevel()
        }
        .onChange(of: model.selectedGameID) { _, _ in
            codeDraft = ""
            previousCodeDraft = ""
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "gamecontroller")
                .font(.system(size: 44))
                .foregroundStyle(GameTheme.muted)
            Text("Игра не открыта")
                .font(.title3.weight(.semibold))
                .foregroundStyle(GameTheme.text)
            Text("Выберите игру на вкладке «Игры».")
                .font(.subheadline)
                .foregroundStyle(GameTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("К списку игр") {
                model.selectedScreen = .games
            }
            .buttonStyle(.borderedProminent)
            .tint(GameTheme.accent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GameTheme.background)
    }

    private func waitingState(game: GameModel) -> some View {
        let gameID = Int64(game.gameID)
        let title = game.gameTitle.isEmpty ? "Игра #\(game.gameID)" : game.gameTitle
        let needsEntry = model.needsGameEntry(gameID: gameID)
        let isActive = model.isGameActive(gameID: gameID)
        let isPending = model.isApplicationPending(game)
        let moderated = model.isGameModerated(gameID: gameID)
        let primaryMessage = waitingStateMessage(
            game: game,
            needsEntry: needsEntry,
            isActive: isActive,
            isPending: isPending,
            moderated: moderated
        )
        let detailMessage = model.statusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let showsDetailMessage = !detailMessage.isEmpty && detailMessage != primaryMessage

        return VStack(spacing: 16) {
            Spacer()
            Image(systemName: waitingStateIcon(
                game: game,
                needsEntry: needsEntry,
                isPending: isPending
            ))
                .font(.system(size: 44))
                .foregroundStyle(GameTheme.muted)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(GameTheme.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text(primaryMessage)
                .font(.subheadline)
                .foregroundStyle(GameTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if !needsEntry, !isActive, let countdown = model.gameStartCountdown {
                TickingCountdownText(
                    countdown: countdown,
                    label: GameDurationFormatter.gameStartLabel
                )
                .font(.title3.weight(.semibold))
                .foregroundStyle(GameTheme.accent)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }

            if showsDetailMessage {
                Text(detailMessage)
                    .font(.caption)
                    .foregroundStyle(GameTheme.accent)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if needsEntry, !isPending {
                Button(model.entryActionTitle(gameID: gameID)) {
                    Task { await model.enterGame(gameID) }
                }
                .buttonStyle(.borderedProminent)
                .tint(GameTheme.accent)
                .disabled(model.isBusy || !model.hasStoredSession)
            }

            Button("Обновить") {
                Task { await model.refreshLevel() }
            }
            .buttonStyle(.bordered)
            .disabled(model.isBusy)

            Button("К списку игр") {
                model.selectedScreen = .games
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GameTheme.background)
        .task(id: game.gameID) {
            await model.ensureGameModerationLoadedForUI(gameID: gameID)
            await model.refreshGameRegistrationState(gameID: gameID)
            await model.pollWaitingGameState(gameID: gameID)
        }
    }

    private func waitingStateIcon(game: GameModel, needsEntry: Bool, isPending: Bool) -> String {
        if isPending {
            return "clock"
        }
        if game.shouldShowEventStatus {
            return waitingStateErrorIcon(for: game.event)
        }
        return needsEntry ? "person.badge.plus" : "hourglass"
    }

    private func waitingStateErrorIcon(for event: Int) -> String {
        switch event {
        case GameEvent.levelDismissed16, GameEvent.levelDismissed18, GameEvent.levelDismissed21:
            return "arrow.clockwise.circle"
        case GameEvent.levelAutoAdvance, GameEvent.allSectorsSolved, GameEvent.levelTimeout:
            return "hourglass"
        default:
            return "exclamationmark.triangle"
        }
    }

    private func waitingStateMessage(
        game: GameModel,
        needsEntry: Bool,
        isActive: Bool,
        isPending: Bool,
        moderated: Bool
    ) -> String {
        if isPending {
            return "Заявка отправлена и ожидает одобрения организатора."
        }
        if game.shouldShowEventStatus {
            return EncounterClient.eventText(for: game.event)
        }
        if needsEntry {
            if moderated {
                if isActive {
                    return "Вы ещё не в игре. Подайте заявку на участие."
                }
                return "Игра ещё не началась. Подайте заявку на участие."
            }
            if isActive {
                return "Вы ещё не в игре. Войдите, чтобы участвовать."
            }
            return "Игра ещё не началась. Войдите в игру, чтобы участвовать."
        }
        if game.isAwaitingLevelOpen || isActive {
            return "Ждём открытия уровня…"
        }
        return "Игра скоро начнётся."
    }

    private func finishedState(game: GameModel) -> some View {
        let title = game.gameTitle.isEmpty ? "Игра #\(game.gameID)" : game.gameTitle
        let status = EncounterClient.eventText(for: game.event)
        let level = game.level
        let passedLevels = game.levels.filter(\.isPassed).count
        let totalLevels = max(game.levels.count, level?.number ?? 0)

        return VStack(spacing: 16) {
            Spacer()

            Image(systemName: game.isGameEnded ? "flag.checkered" : "trophy.fill")
                .font(.system(size: 52))
                .foregroundStyle(GameTheme.accent)

            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(GameTheme.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text(status)
                .font(.headline)
                .foregroundStyle(GameTheme.accent)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let finalTeamStanding = model.finalTeamStanding {
                Text(finalTeamStanding.displayText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(GameTheme.text)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if let level {
                Text(level.name.isEmpty ? "Уровень \(level.number)" : level.name)
                    .font(.subheadline)
                    .foregroundStyle(GameTheme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if totalLevels > 0 {
                    Text("Пройдено уровней: \(passedLevels) из \(totalLevels)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(GameTheme.muted)
                }

                if game.isGameFinished, level.timeoutSecondsRemain > 0 {
                    FinishTransitionCountdown(remainSeconds: level.timeoutSecondsRemain)
                        .padding(.top, 4)
                }
            }

            if !model.statusMessage.isEmpty {
                Text(model.statusMessage)
                    .font(.caption)
                    .foregroundStyle(GameTheme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            NavigationLink {
                GameStatisticsView(model: model, gameID: Int64(game.gameID))
            } label: {
                Text("Статистика")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(GameTheme.accent)
            .padding(.horizontal, 32)

            NavigationLink(value: AppRoute.codes) {
                Text("Журнал кодов")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 32)

            Button("Обновить") {
                Task { await model.refreshLevel() }
            }
            .buttonStyle(.bordered)
            .disabled(model.isBusy)

            Button("К списку игр") {
                model.selectedScreen = .games
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GameTheme.background)
        .task(id: game.isGameFinished ? game.gameID : -1) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                // Silent: this is an unattended poll, so it must respect the unreachable-engine
                // and anti-spam guards. An explicit refresh bypasses both by design.
                await model.refreshLevelSilently()
                guard model.currentModel?.isGameFinished == true else { return }
            }
        }
    }

    private func gameScreen(game: GameModel, level: Level) -> some View {
        VStack(spacing: 0) {
            gameTopBar(game: game, level: level)

            if let popup = model.teammateCodePopup {
                teammateCodePopupView(popup)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            LevelPlayScrollBody(
                model: model,
                statusMessage: model.statusMessage,
                level: level
            )
        }
        .background(GameTheme.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // The toast lives inside the same bottom inset as the input bar so it always
            // stacks above the field instead of overlapping it.
            VStack(spacing: 0) {
                if let result = codeResultToast {
                    codeResultToastView(result)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                LevelCodeInputBar(
                    text: $codeDraft,
                    canSubmitLevel: canSubmitCode(level: level, kind: .level),
                    showsBonusAction: model.canSubmitBonusCode(on: level),
                    levelBlockDuration: level.canSubmitLevelAnswer() ? 0 : level.blockDuration,
                    isFocused: $codeFieldFocused,
                    onSubmitLevel: { submitCodeDraft(kind: .level) },
                    onSubmitBonus: { submitCodeDraft(kind: .bonus) },
                    onLevelBlockExpired: {
                        Task { await model.refreshLevelSilently() }
                    }
                )
            }
            .background(GameTheme.background)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(GameTheme.hairline)
                    .frame(height: 1)
            }
        }
        .animation(.easeOut(duration: 0.25), value: codeResultToast)
        .animation(.easeOut(duration: 0.25), value: model.teammateCodePopup)
        .onChange(of: model.lastCodeResult) { _, newValue in
            if let newValue {
                showCodeResultToast(newValue)
            } else {
                dismissCodeResultToast()
            }
        }
    }

    private func showCodeResultToast(_ result: CodeResultFeedback) {
        codeResultDismissTask?.cancel()
        codeResultToast = result
        codeResultDismissTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            dismissCodeResultToast()
        }
    }

    private func dismissCodeResultToast() {
        codeResultDismissTask?.cancel()
        codeResultDismissTask = nil
        codeResultToast = nil
    }

    private func codeResultToastView(_ result: CodeResultFeedback) -> some View {
        Text(result.message)
            .font(.footnote.weight(.medium))
            .foregroundStyle(codeResultColor(for: result.verdict))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(GameTheme.panel, in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }

    private func codeResultColor(for verdict: CodeAnswerVerdict) -> Color {
        switch verdict {
        case .correct:
            return GameTheme.accent
        case .incorrect:
            return .orange
        case .unchecked:
            return GameTheme.sectionHeader
        }
    }

    private func teammateCodePopupView(_ popup: TeammateCodePopup) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(popup.entries.enumerated()), id: \.offset) { index, entry in
                if index > 0 {
                    Divider()
                        .overlay(GameTheme.muted.opacity(0.25))
                }

                HStack(spacing: 10) {
                    Image(systemName: entry.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(entry.isCorrect ? GameTheme.accent : .orange)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(entry.isCorrect ? GameTheme.accent : .orange)
                        Text(entry.message)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(GameTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GameTheme.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(GameTheme.muted.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
    }

    private func canSubmitCode(level: Level, kind: CodeSubmissionKind) -> Bool {
        let hasText = !codeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasText, model.currentModel?.level != nil else { return false }
        switch kind {
        case .level:
            return model.canSubmitLevelCode(on: level)
        case .bonus:
            return model.canSubmitBonusCode(on: level)
        }
    }

    private func submitCodeDraft(kind: CodeSubmissionKind) {
        let trimmed = codeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let level = model.currentModel?.level {
            let canSubmit: Bool
            switch kind {
            case .level:
                canSubmit = model.canSubmitLevelCode(on: level)
            case .bonus:
                canSubmit = model.canSubmitBonusCode(on: level)
            }
            guard canSubmit else {
                // Let the model publish the precise reason, but keep the unsent draft intact.
                model.submitCode(trimmed, kind: kind)
                return
            }
        }
        previousCodeDraft = trimmed
        codeDraft = ""
        model.submitCode(trimmed, kind: kind)
    }

    private func repeatPreviousCodeDraft() {
        guard !previousCodeDraft.isEmpty else { return }
        codeDraft = previousCodeDraft
        codeFieldFocused = true
    }

    private func gameTopBar(game: GameModel, level: Level) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(GameTheme.accent)
                    .frame(width: 20, height: 20)
                    .overlay {
                        Text("EN")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    }

                Text(headerIdentityLine(game: game))
                    .font(.caption)
                    .foregroundStyle(GameTheme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Button {
                    Task { await model.refreshLevel() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 19))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .disabled(model.isBusy)
                .accessibilityLabel("Обновить")

                headerMenu(game: game)
            }
            .frame(height: 28)

            levelServiceLine(game: game, level: level)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(GameTheme.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(GameTheme.hairline)
                .frame(height: 1)
        }
    }

    private func headerIdentityLine(game: GameModel) -> String {
        let title = game.gameTitle.isEmpty ? "Игра #\(game.gameID)" : game.gameTitle
        return ([title] + [game.login, game.teamName].filter { !$0.isEmpty })
            .joined(separator: " · ")
    }

    private func headerMenu(game: GameModel) -> some View {
        Menu {
            Button {
                Task { await model.refreshLevel() }
            } label: {
                Label("Обновить", systemImage: "arrow.clockwise")
            }
            .disabled(model.isBusy)

            if !previousCodeDraft.isEmpty {
                Button {
                    repeatPreviousCodeDraft()
                } label: {
                    Label("Повторить код «\(previousCodeDraft)»", systemImage: "arrow.uturn.backward")
                }
            }

            if model.agentSettings.enabled {
                Button {
                    model.showAgentSheet = true
                } label: {
                    Label("Ассистент", systemImage: "sparkles")
                }
                .disabled(model.isBusy)
            }

            Button {
                model.showToolsSheet = true
            } label: {
                Label("Инструменты", systemImage: "wrench.and.screwdriver")
            }
            .disabled(model.isBusy)

            Button {
                model.navigationPath.append(.statistics(Int64(game.gameID)))
            } label: {
                Label("Статистика", systemImage: "chart.bar")
            }

            Button {
                model.navigationPath.append(.codes)
            } label: {
                Label(codesMenuTitle, systemImage: "list.bullet.rectangle")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 19))
                .foregroundStyle(.white.opacity(0.4))
        }
        .accessibilityLabel("Ещё")
    }

    private var codesMenuTitle: String {
        let pending = model.queue.pending.count
        return pending > 0 ? "Коды · в очереди \(pending)" : "Коды"
    }

    private func levelServiceLine(game: GameModel, level: Level) -> some View {
        let title = currentLevelTitle(game: game, level: level)
        let total = level.displaySectorsTotal

        return HStack(spacing: 10) {
            Text(title.isEmpty ? "Ур. \(level.number)" : "Ур. \(level.number) · \(title)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GameTheme.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            LevelSegmentedProgressBar(total: total, closed: level.passedSectorsCount)
                .frame(minWidth: 24, maxWidth: .infinity)

            HStack(spacing: 4) {
                Text(verbatim: "\(level.passedSectorsCount)/\(total)")

                if level.timeoutSecondsRemain > 0 {
                    Text(verbatim: "·")
                    LevelDrainCountdown(remainSeconds: level.timeoutSecondsRemain) {
                        Task { await model.refreshLevelSilently() }
                    }
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(GameTheme.accent)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func currentLevelTitle(game: GameModel, level: Level) -> String {
        let directName = level.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !directName.isEmpty {
            return directName
        }

        return game.levels
            .first { $0.levelID == level.levelID || $0.levelNumber == level.number }?
            .levelName
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

}

private extension Level {
    /// Sectors needed to pass the level; falls back to the sector count when the engine omits the rule.
    var displaySectorsTotal: Int {
        requiredSectorsCount > 0 ? requiredSectorsCount : sectors.count
    }
}

/// Compact five-segment sector progress indicator for the service line.
private struct LevelSegmentedProgressBar: View {
    let total: Int
    let closed: Int

    private var segmentCount: Int {
        guard total > 0 else { return 5 }
        return min(total, 5)
    }

    private var filledCount: Int {
        guard total > 0, closed > 0 else { return 0 }
        if total <= 5 {
            return min(closed, segmentCount)
        }
        let scaled = Int((Double(closed) / Double(total) * Double(segmentCount)).rounded())
        return min(max(scaled, 1), segmentCount)
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(0..<segmentCount), id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < filledCount ? GameTheme.accent : GameTheme.trackEmpty)
                    .frame(height: 3)
            }
        }
        .animation(.easeOut(duration: 0.25), value: filledCount)
        .accessibilityHidden(true)
    }
}

private struct FinishTransitionCountdown: View {
    let remainSeconds: Int
    @State private var syncedAt = Date()

    var body: some View {
        if remainSeconds > 0 {
            VStack(spacing: 4) {
                Text("Автопереход")
                    .font(.caption)
                    .foregroundStyle(GameTheme.muted)
                TickingCountdownText(
                    countdown: SyncedSecondsCountdown(
                        remainSeconds: remainSeconds,
                        syncedAt: syncedAt
                    ),
                    label: GameDurationFormatter.levelDrainLabel
                )
                .font(.title3.weight(.semibold))
                .foregroundStyle(GameTheme.accent)
            }
            .onAppear { syncedAt = Date() }
            .onChange(of: remainSeconds) { _, _ in
                syncedAt = Date()
            }
        }
    }
}

private struct LevelDrainCountdown: View {
    let remainSeconds: Int
    var onDrain: (() -> Void)?
    @State private var syncedAt = Date()

    var body: some View {
        if remainSeconds > 0 {
            TickingCountdownText(
                countdown: SyncedSecondsCountdown(
                    remainSeconds: remainSeconds,
                    syncedAt: syncedAt
                ),
                label: GameDurationFormatter.compactDrain(seconds:)
            )
            .lineLimit(1)
            .accessibilityLabel("До слива уровня")
            .onAppear { syncedAt = Date() }
            .onChange(of: remainSeconds) { _, _ in
                syncedAt = Date()
            }
            // When the drain countdown hits zero on-screen, force a refresh so the level
            // never stays stuck on "Слив…" if background polling was paused (e.g. anti-spam backoff).
            .task(id: remainSeconds) {
                try? await Task.sleep(for: .seconds(Double(remainSeconds) + 1))
                guard !Task.isCancelled else { return }
                onDrain?()
            }
        }
    }
}

private struct LevelCodeInputBar: View {
    @Binding var text: String
    var canSubmitLevel: Bool
    var showsBonusAction: Bool
    var levelBlockDuration: Int
    var isFocused: FocusState<Bool>.Binding
    var onSubmitLevel: () -> Void
    var onSubmitBonus: () -> Void
    var onLevelBlockExpired: () -> Void

    private let fieldFont = Font.system(size: 17, weight: .semibold, design: .monospaced)
    private let controlHeight: CGFloat = 44
    private let controlRadius: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if levelBlockDuration > 0 {
                LevelAnswerBlockCountdown(
                    remainSeconds: levelBlockDuration,
                    onExpire: onLevelBlockExpired
                )
            }

            HStack(spacing: 8) {
                codeField

                if showsBonusAction {
                    Button(action: onSubmitBonus) {
                        Text("Бонус")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(GameTheme.bonusTitle)
                            .frame(height: controlHeight)
                            .padding(.horizontal, 14)
                            .background(
                                GameTheme.bonusTitle.opacity(0.16),
                                in: RoundedRectangle(cornerRadius: controlRadius)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: controlRadius)
                                    .stroke(GameTheme.bonusTitle.opacity(0.45), lineWidth: 1)
                            }
                    }
                    .accessibilityHint("Отправить как ответ на бонусное задание")
                }

                Button(action: onSubmitLevel) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(.white)
                        .frame(width: controlHeight, height: controlHeight)
                        .background(
                            canSubmitLevel ? GameTheme.accent : GameTheme.fieldFill,
                            in: RoundedRectangle(cornerRadius: controlRadius)
                        )
                }
                .disabled(!canSubmitLevel)
                .accessibilityLabel("Отправить")
                .accessibilityHint("Отправить как ответ на уровень")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var codeField: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text("КОД")
                    .font(fieldFont)
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.32))
                    .allowsHitTesting(false)
            }

            TextField("", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .focused(isFocused)
                .onSubmit(onSubmitLevel)
                .font(fieldFont)
                .tracking(1.2)
                .foregroundStyle(GameTheme.text)
                .accessibilityLabel("Код")
        }
        .padding(.horizontal, 14)
        .frame(height: controlHeight)
        .background(GameTheme.fieldFill, in: RoundedRectangle(cornerRadius: controlRadius))
        .overlay {
            RoundedRectangle(cornerRadius: controlRadius)
                .stroke(GameTheme.fieldStroke, lineWidth: 1)
        }
    }
}

private struct LevelAnswerBlockCountdown: View {
    let remainSeconds: Int
    let onExpire: () -> Void
    @State private var syncedAt = Date()

    var body: some View {
        TickingCountdownText(
            countdown: SyncedSecondsCountdown(remainSeconds: remainSeconds, syncedAt: syncedAt),
            label: { "Ответы на уровень через \($0) сек. · бонусы доступны" }
        )
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(GameTheme.sectionHeader)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { syncedAt = Date() }
        .onChange(of: remainSeconds) { _, _ in syncedAt = Date() }
        .task(id: remainSeconds) {
            try? await Task.sleep(for: .seconds(Double(remainSeconds) + 1))
            guard !Task.isCancelled else { return }
            onExpire()
        }
    }
}
private struct LevelPlayScrollBody: View {
    let model: EncounterViewModel
    let statusMessage: String
    let level: Level

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(GameTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                taskSection

                if !level.sectors.isEmpty {
                    sectorsSection
                }

                if !level.helps.isEmpty || !level.penaltyHelps.isEmpty {
                    helpsSection
                }

                if !level.bonuses.isEmpty {
                    bonusesSection
                }

                if !level.messages.isEmpty {
                    messagesSection
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
        }
    }

    /// One flat block: hairline separator, uppercase label with optional right-aligned counter, content.
    @ViewBuilder
    private func block<Content: View>(
        _ title: String,
        tint: Color = GameTheme.sectionHeader,
        trailing: String? = nil,
        showsDivider: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsDivider {
                Divider()
                    .overlay(GameTheme.hairline)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(tint)

                Spacer(minLength: 4)

                if let trailing {
                    Text(trailing)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(.top, showsDivider ? 12 : 0)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var taskSection: some View {
        block("Задание", showsDivider: false) {
            VStack(alignment: .leading, spacing: 10) {
                if let task = level.task {
                    taskView(task)
                }

                ForEach(Array(level.tasks.enumerated()), id: \.offset) { index, task in
                    if level.tasks.count > 1 || level.task == nil {
                        Text("Задание \(index + 1)")
                            .font(.caption)
                            .foregroundStyle(GameTheme.muted)
                    }
                    taskView(task)
                }
            }
        }
    }

    @ViewBuilder
    private func taskView(_ task: LevelTask) -> some View {
        let html = task.formattedText.isEmpty ? task.taskText : task.formattedText
        if html.contains("<") {
            EncounterHTMLView(html: html, fontSize: 16, lineHeight: 1.4)
        } else {
            CoordinateText(text: task.displayText)
                .font(.system(size: 16))
                .lineSpacing(5)
                .foregroundStyle(GameTheme.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sectorsSection: some View {
        block("Секторы", trailing: sectorsProgressCaption) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6)
                ],
                spacing: 6
            ) {
                ForEach(level.sectors.sortedForDisplay) { sector in
                    sectorChip(sector)
                }
            }
        }
    }

    private var sectorsProgressCaption: String {
        let total = level.displaySectorsTotal
        let closed = level.passedSectorsCount
        let remaining = level.sectorsLeftToClose > 0
            ? level.sectorsLeftToClose
            : max(0, total - closed)
        if remaining > 0 {
            return "закрыто \(closed) из \(total) · осталось \(remaining)"
        }
        return "закрыто \(closed) из \(total)"
    }

    private func sectorChip(_ sector: Sector) -> some View {
        HStack(spacing: 8) {
            if sector.isAnswered {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GameTheme.accent)

                Text(verbatim: sectorChipCode(sector))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(GameTheme.accent)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text(verbatim: "— — —")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.28))
            }

            Spacer(minLength: 4)

            Text(verbatim: "\(sector.displayOrder)")
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if sector.isAnswered {
                RoundedRectangle(cornerRadius: 9)
                    .fill(GameTheme.accent.opacity(0.12))
            } else {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(
                        GameTheme.sectorEmptyStroke,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            }
        }
        .animation(.easeOut(duration: 0.25), value: sector.isAnswered)
        .accessibilityElement(children: .combine)
    }

    private func sectorChipCode(_ sector: Sector) -> String {
        let answer = sector.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !answer.isEmpty {
            return answer
        }
        return sector.name.isEmpty ? "Сектор \(sector.displayOrder)" : sector.name
    }

    private var helpsSection: some View {
        block("Подсказки") {
            LevelPlayHelpsList(
                helps: level.helps,
                penaltyHelps: level.penaltyHelps
            ) { help in
                Task { await model.requestPenaltyHelp(help) }
            }
        }
    }

    private var bonusesSection: some View {
        block(
            "Бонусы",
            tint: GameTheme.bonusTitle,
            trailing: "выполнен \(level.passedBonusesCount) из \(level.bonuses.count)"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(level.bonuses.sorted { $0.number < $1.number }) { bonus in
                    bonusParagraph(bonus)
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
    }

    /// One flowing paragraph per bonus: optional checkmark, run-in title, then task and reward text.
    private func bonusParagraph(_ bonus: Bonus) -> Text {
        var paragraph = Text(verbatim: "")

        if bonus.isAnswered {
            paragraph = Text(Image(systemName: "checkmark"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GameTheme.accent)
                + Text(verbatim: " ")
        }

        paragraph = paragraph + Text(verbatim: "Бонус \(bonus.number): \(bonus.name). ")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(bonus.isAnswered ? GameTheme.accent : GameTheme.bonusTitle)

        return paragraph + Text(verbatim: bonusBodyText(bonus))
            .font(.system(size: 16))
            .foregroundStyle(.white.opacity(0.85))
    }

    private func bonusBodyText(_ bonus: Bonus) -> String {
        [bonus.task, bonus.help]
            .map { $0.strippingHTML().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var messagesSection: some View {
        block("Сообщения оргов", tint: .white.opacity(0.45)) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(level.messages) { message in
                    (
                        Text(verbatim: "\(messageAuthor(message)): ")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(GameTheme.bonusTitle)
                            + Text(verbatim: message.displayText)
                            .font(.system(size: 16))
                            .foregroundStyle(GameTheme.text)
                    )
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }
            }
        }
    }

    private func messageAuthor(_ message: AdminMessage) -> String {
        let login = message.ownerLogin.trimmingCharacters(in: .whitespacesAndNewlines)
        return login.isEmpty ? "орг" : login
    }
}

/// Inline hints list for the play screen. Unlock countdown and penalty-request logic are the same as
/// `LevelHelpsSection`; only the presentation is flat rows instead of panels.
private struct LevelPlayHelpsList: View {
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
            ForEach(helps.sorted { $0.number < $1.number }) { help in
                helpRow(help, isPenalty: false)
            }

            ForEach(penaltyHelps.sorted { $0.number < $1.number }) { help in
                helpRow(help, isPenalty: true)
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

    private func helpRow(_ help: Help, isPenalty: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(verbatim: "\(help.number)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(GameTheme.sectionHeader)
                .frame(width: 14, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                if isPenalty, help.penalty > 0 {
                    Text(verbatim: "Штраф \(GameDurationFormatter.minutesAndSeconds(help.penalty))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GameTheme.muted)
                }

                helpBody(help, isPenalty: isPenalty)

                if help.canRequestPenalty, onRequestPenaltyHelp != nil {
                    Button {
                        if help.requestConfirm {
                            pendingPenaltyHelp = help
                        } else {
                            onRequestPenaltyHelp?(help)
                        }
                    } label: {
                        Label("Открыть штрафную подсказку", systemImage: "exclamationmark.triangle")
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func helpBody(_ help: Help, isPenalty: Bool) -> some View {
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
            .font(.system(size: 16))
            .foregroundStyle(GameTheme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if isPenalty, let fallback = help.penaltyMessage, !fallback.isEmpty {
            helpContent(fallback)
        } else if isPenalty {
            helpContent("Требуется запрос")
        } else {
            Text("Открывается…")
                .font(.system(size: 16))
                .foregroundStyle(GameTheme.muted)
        }
    }

    @ViewBuilder
    private func helpContent(_ text: String) -> some View {
        if text.contains("<") {
            EncounterHTMLView(html: text, fontSize: 16, lineHeight: 1.4)
        } else {
            CoordinateText(text: text.strippingHTML())
                .font(.system(size: 16))
                .lineSpacing(6)
                .foregroundStyle(GameTheme.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
