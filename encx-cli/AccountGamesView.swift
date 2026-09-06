import SwiftUI
import Observation

struct AccountGamesView: View {
    @Bindable var model: EncounterViewModel
    @State private var showDomainChooser = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                topBar

                if model.isMonitoringGame {
                    GameMonitoringBanner(model: model)
                }

                if !model.hasStoredSession && model.games.isEmpty && model.domainGames.isEmpty {
                    ContentUnavailableView {
                        Label("Войдите в аккаунт", systemImage: "person.crop.circle")
                    } description: {
                        Text("Откройте настройки и выполните вход, чтобы увидеть список игр.")
                    }
                    .foregroundStyle(GameTheme.text, GameTheme.muted)
                    .padding(.top, 20)
                } else {
                    if !model.hasStoredSession {
                        loginHintSection
                    }
                    gamesSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(GameTheme.background)
        .sheet(isPresented: $showDomainChooser) {
            DomainChooserView(model: model, isPresented: $showDomainChooser)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .refreshable {
            await model.refreshGames()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                showDomainChooser = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.system(size: 16))
                        .foregroundStyle(GameTheme.bonusTitle)
                    Text(model.settings.domain)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GameTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 12)
                .background(GameTheme.hairline, in: RoundedRectangle(cornerRadius: 18))
                .contentShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)
            .accessibilityLabel("Сменить домен")

            Spacer(minLength: 8)

            HStack(spacing: 18) {
                Button {
                    Task { await model.refreshGames() }
                } label: {
                    topBarIcon("arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(model.isBusy)
                .accessibilityLabel("Обновить")

                Button {
                    model.selectedScreen = .team
                } label: {
                    topBarIcon("person.2.fill")
                }
                .buttonStyle(.plain)
                .disabled(model.isBusy)
                .accessibilityLabel("Управление командой")

                NavigationLink {
                    SettingsView(model: model)
                } label: {
                    topBarIcon("gearshape")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Настройки")
            }
        }
    }

    private func topBarIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 22))
            .foregroundStyle(Color.white.opacity(0.6))
    }

    // MARK: - Sections

    @ViewBuilder
    private var gamesSection: some View {
        VStack(alignment: .leading, spacing: 26) {
            if model.games.isEmpty && model.domainGames.isEmpty {
                ContentUnavailableView("Нет списка игр", systemImage: "list.bullet.rectangle")
                    .foregroundStyle(GameTheme.text, GameTheme.muted)
            }

            if let heroGame {
                liveSection(game: heroGame)
            }

            if !model.upcomingGames.isEmpty {
                upcomingSection
            }

            if !filteredDomainGames.isEmpty {
                domainSection
            }
        }
    }

    private func liveSection(game: GameInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(GameTheme.accent)
                    .frame(width: 8, height: 8)
                Text("Идёт сейчас")
                    .font(.system(size: 12, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(GameTheme.accent)
            }

            heroCard(game: game)

            ForEach(otherActiveGames) { other in
                compactGameRow(game: other, showApplicationHint: false)
            }
        }
    }

    private func heroCard(game: GameInfo) -> some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(game.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(GameTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: heroSubline(game: game))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            heroMetrics(game: game)

            Button {
                Task { await model.openGame(Int64(game.id)) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 17, weight: .bold))
                    Text("Продолжить игру")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(GameTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)
            .accessibilityLabel("Продолжить игру")
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [GameTheme.accent.opacity(0.18), GameTheme.accent.opacity(0.06)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(GameTheme.accent.opacity(0.55), lineWidth: 1)
        }
    }

    private func heroMetrics(game: GameInfo) -> some View {
        HStack(alignment: .bottom, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                metricLabel("уровень")
                Text(verbatim: levelProgressText(for: game))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(GameTheme.text)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 4) {
                metricLabel("до слива")
                drainValue(for: game)
            }

            Spacer(minLength: 8)

            progressSegments(for: game)
        }
    }

    private func metricLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .textCase(.uppercase)
            .foregroundStyle(Color.white.opacity(0.45))
    }

    @ViewBuilder
    private func drainValue(for game: GameInfo) -> some View {
        if let seconds = drainSeconds(for: game), seconds > 0 {
            HeroDrainCountdown(remainSeconds: seconds)
        } else {
            Text(verbatim: "—")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(GameTheme.accent)
        }
    }

    private func progressSegments(for game: GameInfo) -> some View {
        let closed = closedSegments(for: game)
        return HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(index < closed ? GameTheme.accent : GameTheme.trackEmpty)
                    .frame(width: 14, height: 6)
            }
        }
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Скоро")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GameTheme.sectionHeader)
                Text(verbatim: upcomingCountLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.45))
            }

            ForEach(model.upcomingGames) { game in
                compactGameRow(game: game, showApplicationHint: true)
            }
        }
    }

    private func compactGameRow(game: GameInfo, showApplicationHint: Bool) -> some View {
        Button {
            Task { await model.openGame(Int64(game.id)) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(GameTheme.text)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: rowSubline(game: game, showApplicationHint: showApplicationHint))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            .padding(14)
            .background(GameTheme.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(white: 0.15), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
        .accessibilityLabel("Перейти к игре")
    }

    private var domainSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Все игры домена")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.45))

            ForEach(filteredDomainGames) { game in
                domainGameRow(game: game)
            }
        }
    }

    private func domainGameRow(game: DomainGame) -> some View {
        Button {
            Task { await model.openGame(Int64(game.id)) }
        } label: {
            HStack(spacing: 12) {
                (
                    Text(game.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(GameTheme.text)
                        + Text(verbatim: " · #\(game.id)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.4))
                )
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.right")
                    .font(.system(size: 20))
                    .foregroundStyle(GameTheme.text)
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 14)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
        .accessibilityLabel("Перейти к игре")
        .task(id: game.id) {
            await model.ensureGameModerationLoadedForUI(gameID: Int64(game.id))
        }
    }

    // MARK: - Derived data

    private var filteredDomainGames: [DomainGame] {
        let ids = Set(model.games.map(\.id))
        return model.domainGames.filter { !ids.contains($0.id) }
    }

    private var currentActiveGame: GameInfo? {
        guard let selectedGameID = model.selectedGameID else { return nil }
        return model.activeGames.first { $0.id == Int(selectedGameID) }
    }

    /// Game shown in the "Идёт сейчас" hero card: the monitored one, otherwise the first active game.
    private var heroGame: GameInfo? {
        currentActiveGame ?? model.activeGames.first
    }

    private var otherActiveGames: [GameInfo] {
        guard let heroGame else { return [] }
        return model.activeGames.filter { $0.id != heroGame.id }
    }

    private func heroSubline(game: GameInfo) -> String {
        let descr = game.description.strippingHTML()
        if descr.isEmpty {
            return "#\(game.displayNumberText)"
        }
        return "#\(game.displayNumberText) · \(descr)"
    }

    private func rowSubline(game: GameInfo, showApplicationHint: Bool) -> String {
        var parts = ["#\(game.displayNumberText)"]
        let descr = game.description.strippingHTML()
        if !descr.isEmpty {
            parts.append(descr)
        }
        if showApplicationHint && game.isModerated {
            parts.append("нужна заявка")
        }
        return parts.joined(separator: " · ")
    }

    private var upcomingCountLabel: String {
        let count = model.upcomingGames.count
        return "\(count) \(gameWord(count))"
    }

    private func gameWord(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod10 == 1 && mod100 != 11 {
            return "игра"
        }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) {
            return "игры"
        }
        return "игр"
    }

    /// Live level progress, available only while the engine model belongs to the shown game.
    private func levelProgress(for game: GameInfo) -> (current: Int, total: Int)? {
        guard let current = model.currentModel,
              current.gameID == game.id,
              let level = current.level else {
            return nil
        }
        return (level.number, max(current.levels.count, level.number))
    }

    private func levelProgressText(for game: GameInfo) -> String {
        if let progress = levelProgress(for: game) {
            return "\(progress.current) из \(progress.total)"
        }
        if let total = game.levelNumber, total > 0 {
            return "— из \(total)"
        }
        return "—"
    }

    private func drainSeconds(for game: GameInfo) -> Int? {
        guard let current = model.currentModel,
              current.gameID == game.id,
              let level = current.level else {
            return nil
        }
        return level.timeoutSecondsRemain
    }

    private func closedSegments(for game: GameInfo) -> Int {
        guard let progress = levelProgress(for: game), progress.total > 0 else { return 0 }
        let ratio = Double(progress.current) / Double(progress.total)
        return min(5, max(0, Int((ratio * 5).rounded())))
    }

    private var loginHintSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Вы не вошли в аккаунт")
                        .font(.headline)
                        .foregroundStyle(GameTheme.text)
                    Text("Ниже показан общий список игр домена. Чтобы видеть свои активные игры и входить в них — выполните вход в настройках.")
                        .font(.caption)
                        .foregroundStyle(GameTheme.muted)
                }
                Spacer()
            }

            NavigationLink {
                SettingsView(model: model)
            } label: {
                Label("Открыть настройки для входа", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .tint(GameTheme.accent)
            .disabled(model.isBusy)
        }
        .sectionPanel()
    }
}

/// Compact `m:ss` drain countdown for the hero card, re-anchored whenever the engine reports a new value.
private struct HeroDrainCountdown: View {
    let remainSeconds: Int
    @State private var syncedAt = Date()

    var body: some View {
        TickingCountdownText(
            countdown: SyncedSecondsCountdown(remainSeconds: remainSeconds, syncedAt: syncedAt),
            label: GameDurationFormatter.compactDrain
        )
        .font(.system(size: 22, weight: .bold))
        .foregroundStyle(GameTheme.accent)
        .lineLimit(1)
        .onAppear { syncedAt = Date() }
        .onChange(of: remainSeconds) { _, _ in
            syncedAt = Date()
        }
    }
}
