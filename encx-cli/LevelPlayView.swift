import SwiftUI
import Observation

struct LevelPlayView: View {
    @Bindable var model: EncounterViewModel
    @State private var codeDraft = ""
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
                await model.refreshLevel()
                guard model.currentModel?.isGameFinished == true else { return }
            }
        }
    }

    private func gameScreen(game: GameModel, level: Level) -> some View {
        VStack(spacing: 0) {
            gameHeader(game: game)
            levelProgress(game: game, level: level)

            LevelPlayScrollBody(
                statusMessage: model.statusMessage,
                level: level
            )
        }
        .background(GameTheme.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            LevelCodeInputBar(
                text: $codeDraft,
                canSubmit: model.currentModel?.level != nil && !codeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                isFocused: $codeFieldFocused,
                onSubmit: submitCodeDraft
            )
        }
        .overlay(alignment: .bottom) {
            if let result = codeResultToast {
                codeResultToastView(result)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 64)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: codeResultToast)
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
            .font(.subheadline.weight(.medium))
            .foregroundStyle(result.isCorrect ? GameTheme.accent : .orange)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(GameTheme.panel, in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }

    private func submitCodeDraft() {
        let trimmed = codeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        codeDraft = ""
        model.submitCode(trimmed)
    }

    private func gameHeader(game: GameModel) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(GameTheme.accent)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Text("EN")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                    }

                Text(game.gameTitle.isEmpty ? "Игра #\(game.gameID)" : game.gameTitle)
                    .font(.headline)
                    .foregroundStyle(GameTheme.text)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 18) {
                Button {
                    Task { await model.refreshLevel() }
                } label: {
                    headerAction("Обновить", systemImage: "arrow.clockwise")
                }
                .disabled(model.isBusy)

                NavigationLink {
                    GameStatisticsView(model: model, gameID: Int64(game.gameID))
                } label: {
                    headerAction("Статистика", systemImage: "chart.bar")
                }

                NavigationLink {
                    CodesView(
                        model: model,
                        sentActions: game.level?.mixedActions ?? []
                    )
                } label: {
                    codesHeaderAction(pendingCount: model.queue.pending.count)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(GameTheme.panel)
    }

    private func codesHeaderAction(pendingCount: Int) -> some View {
        VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.body)
                if pendingCount > 0 {
                    Text("\(pendingCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Color.orange, in: Circle())
                        .offset(x: 8, y: -8)
                }
            }
            Text("Коды")
                .font(.system(size: 9))
                .lineLimit(1)
        }
        .foregroundStyle(GameTheme.text)
        .frame(minWidth: 44)
    }

    private func headerAction(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.body)
            Text(title)
                .font(.system(size: 9))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(GameTheme.text)
        .frame(minWidth: 44)
    }

    private func levelProgress(game: GameModel, level: Level) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if !game.teamName.isEmpty || !game.login.isEmpty {
                    Text([game.login, game.teamName].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(GameTheme.muted)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Уровень")
                            .foregroundStyle(GameTheme.muted)
                        Text("\(level.number)")
                            .fontWeight(.bold)
                            .foregroundStyle(GameTheme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(GameTheme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                        Text("из \(max(game.levels.count, level.number))")
                            .foregroundStyle(GameTheme.muted)
                    }
                    .font(.subheadline)

                    LevelDrainCountdown(remainSeconds: level.timeoutSecondsRemain)
                }
            }

            if let progress = sectorsProgressCaption(level: level) {
                Text(progress)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(GameTheme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private func sectorsProgressCaption(level: Level) -> String? {
        if level.requiredSectorsCount > 0 {
            let remaining = level.sectorsLeftToClose > 0
                ? level.sectorsLeftToClose
                : max(0, level.requiredSectorsCount - level.passedSectorsCount)
            if remaining > 0 {
                return "Для прохождения: \(level.passedSectorsCount) из \(level.requiredSectorsCount) · осталось \(remaining)"
            }
            return "Для прохождения: \(level.passedSectorsCount) из \(level.requiredSectorsCount)"
        }
        if level.sectorsLeftToClose > 0 {
            return "Осталось закрыть: \(level.sectorsLeftToClose) \(LevelPlayWordForms.sector(level.sectorsLeftToClose))"
        }
        return nil
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
    @State private var syncedAt = Date()

    var body: some View {
        if remainSeconds > 0 {
            TickingCountdownText(
                countdown: SyncedSecondsCountdown(
                    remainSeconds: remainSeconds,
                    syncedAt: syncedAt
                ),
                label: GameDurationFormatter.levelDrainLabel
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(GameTheme.accent)
            .onAppear { syncedAt = Date() }
            .onChange(of: remainSeconds) { _, _ in
                syncedAt = Date()
            }
        }
    }
}

private struct LevelCodeInputBar: View {
    @Binding var text: String
    var canSubmit: Bool
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField("Введите ответ или код и нажмите Enter", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .focused(isFocused)
                .onSubmit(onSubmit)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(GameTheme.border, lineWidth: 1)
                }
                .foregroundStyle(GameTheme.text)

            Button(action: onSubmit) {
                Image(systemName: "paperplane.fill")
                    .frame(width: 40, height: 40)
                    .background(canSubmit ? GameTheme.accent : GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
            }
            .disabled(!canSubmit)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(GameTheme.background)
    }
}

private struct LevelPlayScrollBody: View {
    let statusMessage: String
    let level: Level

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(GameTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !level.sectors.isEmpty {
                    sectorsSection
                }

                taskSection

                if !level.helps.isEmpty || !level.penaltyHelps.isEmpty {
                    helpsSection
                }

                if !level.messages.isEmpty {
                    messagesSection
                }

                if !level.bonuses.isEmpty {
                    bonusesSection
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private var sectorsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GameSectionHeader(title: sectorsSectionTitle)

            ForEach(level.sectors.sortedForDisplay) { sector in
                Text(sectorLine(sector))
                    .font(.body)
                    .foregroundStyle(sector.isAnswered ? GameTheme.accent : GameTheme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GameSectionHeader(title: "Задание")

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

    @ViewBuilder
    private func taskView(_ task: LevelTask) -> some View {
        let html = task.formattedText.isEmpty ? task.taskText : task.formattedText
        if html.contains("<") {
            EncounterHTMLView(html: html)
        } else {
            Text(task.displayText)
                .font(.body)
                .foregroundStyle(GameTheme.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var messagesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GameSectionHeader(title: "Сообщения")
            ForEach(level.messages) { message in
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.ownerLogin)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GameTheme.bonusTitle)
                    Text(message.displayText)
                        .font(.body)
                        .foregroundStyle(GameTheme.text)
                }
            }
        }
    }

    private var bonusesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GameSectionHeader(
                title: "На уровне \(level.bonuses.count) \(LevelPlayWordForms.bonus(level.bonuses.count)) (Выполненные — \(level.passedBonusesCount))"
            )

            ForEach(level.bonuses.sorted(by: { $0.number < $1.number })) { bonus in
                VStack(alignment: .leading, spacing: 4) {
                    Text("Бонус \(bonus.number): \(bonus.name)\(bonus.isAnswered ? " ✓" : "")")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(GameTheme.bonusTitle)

                    if !bonus.task.isEmpty {
                        bonusContent(bonus.task)
                    }
                    if !bonus.help.isEmpty {
                        bonusContent(bonus.help)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func bonusContent(_ text: String) -> some View {
        if text.contains("<") {
            EncounterHTMLView(html: text)
        } else {
            Text(text.strippingHTML())
                .font(.body)
                .foregroundStyle(GameTheme.text)
        }
    }

    private var helpsSection: some View {
        LevelHelpsSection(helps: level.helps, penaltyHelps: level.penaltyHelps)
    }

    private var sectorsSectionTitle: String {
        let total = level.sectors.count
        var title = "На уровне \(total) \(LevelPlayWordForms.sector(total))"
        if level.requiredSectorsCount > 0 {
            title += " · для прохождения \(level.passedSectorsCount) из \(level.requiredSectorsCount)"
        } else if level.sectorsLeftToClose > 0 {
            title += " · осталось \(level.sectorsLeftToClose)"
        }
        return title
    }

    private func sectorLine(_ sector: Sector) -> String {
        let name = sector.name.isEmpty ? "Сектор \(sector.displayOrder)" : sector.name
        if sector.isAnswered {
            return "\(name): \(sector.answer)"
        }
        return "\(name): код не введён"
    }
}

private enum LevelPlayWordForms {
    static func sector(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod100 >= 11 && mod100 <= 14 { return "секторов" }
        switch mod10 {
        case 1: return "сектор"
        case 2...4: return "сектора"
        default: return "секторов"
        }
    }

    static func bonus(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod100 >= 11 && mod100 <= 14 { return "бонусов" }
        switch mod10 {
        case 1: return "бонус"
        case 2...4: return "бонуса"
        default: return "бонусов"
        }
    }
}
