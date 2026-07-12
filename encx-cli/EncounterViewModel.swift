import Foundation
import Observation
import UIKit

enum AppScreen: Hashable {
    case games
    case game
    case team

    var title: String {
        switch self {
        case .games: return "Игры"
        case .game: return "Игра"
        case .team: return "Команда"
        }
    }
}

enum AppRoute: Hashable {
    case codes
    case statistics(Int64)
}

struct CodeResultFeedback: Equatable {
    let message: String
    let isCorrect: Bool
    let id: UUID
}

struct TeammateCodePopup: Equatable {
    let title: String
    let message: String
    let isCorrect: Bool
    let id: UUID
}

struct NewHintPopup: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

struct FinalTeamStanding: Equatable {
    let place: Int
    let teamsCount: Int

    var displayText: String {
        if teamsCount > 0 {
            return "Место команды: \(place) из \(teamsCount)"
        }
        return "Место команды: \(place)"
    }
}

enum SessionRecoveryError: LocalizedError {
    case reloginRequired

    var errorDescription: String? {
        switch self {
        case .reloginRequired:
            return "Сессия истекла. Войдите снова в настройках."
        }
    }
}

enum QueueConnectionStatus {
    case offline
    case serverUnreachable
    case ready

    var label: String {
        switch self {
        case .offline: return "Нет сети"
        case .serverUnreachable: return "Сервер недоступен"
        case .ready: return "Связь есть"
        }
    }

    var systemImage: String {
        switch self {
        case .offline: return "wifi.slash"
        case .serverUnreachable: return "exclamationmark.triangle"
        case .ready: return "wifi"
        }
    }
}

@Observable
@MainActor
final class EncounterViewModel {
    var settings = DomainSettings()
    var login = ""
    var password = ""
    var games: [GameInfo] = []
    var domainGames: [DomainGame] = []
    var myTeams: [TeamInfo] = []
    var selectedTeamID: Int64?
    var teamManagementInfo: TeamManagementInfo?
    var teamInvitations: [TeamInvitation] = []
    @ObservationIgnored private var moderationByGameID: [Int: Bool] = [:]
    var selectedGameID: Int64?
    var currentModel: GameModel?
    /// Countdown until game start derived from the latest game model.
    var gameStartCountdown: SyncedSecondsCountdown?
    var selectedScreen: AppScreen = .games
    var navigationPath: [AppRoute] = []
    var isBusy = false
    var statusMessage = ""
    var errorMessage: String?
    var antiSpamVerificationURL: URL?
    var showAntiSpamVerification = false
    var showToolsSheet = false
    var lastCodeResult: CodeResultFeedback?
    var teammateCodePopup: TeammateCodePopup?
    var newHintPopup: NewHintPopup?
    var codeLogActions: [CodeAction] = []
    var isCodeLogLoading = false
    var codeLogStatusMessage = ""
    var knownDomains: [String] = []
    var finalTeamStanding: FinalTeamStanding?
    /// Last successful engine round-trip (ping or code send), for the Codes tab.
    var serverRoundTripMs: Int?
    /// Number of captured HAR entries (updated from settings/debug actions).
    var harEntryCount = 0
    var harUploadStatusMessage = ""

    let queue = CodeQueueStore.shared
    private let liveActivity = QueueLiveActivityManager()

    private var client: EncounterClient?
    private let settingsKey = "encx.domainSettings"
    private let loginKey = "encx.login"
    private let knownDomainsKey = "encx.knownDomains"
    private let sessionCookiesKey = "encx.session.cookies"
    private var busyCounter = 0
    private var queueProcessorTask: Task<Void, Never>?
    private var engineReachable = true
    private var keepScreenAwake = false
    private var reloginTask: Task<Void, Error>?
    private var lastGamePollDate: Date?
    private var codeLogLoadedGameID: Int64?
    private var finalStandingLoadedGameID: Int64?
    private var finalStandingTask: Task<Void, Never>?
    private let gamePollInterval: TimeInterval = 20
    /// Steady-state poll interval for an active level on screen. Kept well above the transient 5s cadence
    /// so ordinary play does not trip the Encounter server anti-spam ("NotHumanRequest") wall.
    private let activeLevelPollInterval: TimeInterval = 12
    /// Floor for the hint/level-timeout self-rescheduling refreshes so a small (or clock-skewed) server
    /// `RemainSeconds` cannot spin a tight ~2s refresh loop.
    private let minTimerRefreshInterval: TimeInterval = 15
    /// While set to a future date, background polling is suspended because the server returned the
    /// anti-spam wall; hammering it further only prolongs the block.
    private var antiSpamBackoffUntil: Date?
    /// How long background polling pauses after an anti-spam response.
    private let antiSpamBackoffSeconds: TimeInterval = 90
    /// Backoff for queue retries while the engine is unreachable (cap keeps UI responsive).
    private var queueRetryBackoffSeconds: TimeInterval = 0.4
    /// Anchor for Live Activity countdowns; updated when `currentModel` changes, not on every sync.
    private var liveActivityModelAnchor = Date()
    private var lastSyncedLiveActivityState: QueueActivityAttributes.ContentState?
    private var hintUnlockRefreshTask: Task<Void, Never>?
    private var levelTimeoutRefreshTask: Task<Void, Never>?
    private var harEntryCountRefreshTask: Task<Void, Never>?
    private var harUploadTask: Task<Void, Never>?
    private var lastUploadedHAREntryCount = 0
    private var teammateCodePopupDismissTask: Task<Void, Never>?

    var shouldKeepScreenAwake: Bool {
        get { keepScreenAwake }
        set { keepScreenAwake = newValue }
    }

    var queueConnectionStatus: QueueConnectionStatus {
        if !queue.isOnline { return .offline }
        if !engineReachable { return .serverUnreachable }
        return .ready
    }

    var codesConnectionStatusLabel: String {
        switch queueConnectionStatus {
        case .ready:
            if let serverRoundTripMs {
                return "Связь есть · \(serverRoundTripMs) ms"
            }
            return QueueConnectionStatus.ready.label
        case .offline, .serverUnreachable:
            return queueConnectionStatus.label
        }
    }

    func measureServerLatency() async {
        guard queue.isOnline, let gameID = selectedGameID else {
            serverRoundTripMs = nil
            return
        }
        let started = DispatchTime.now()
        do {
            _ = try await withSessionRecovery { try await $0.pingGame(gameID: gameID) }
            recordServerRoundTrip(since: started)
            markEngineReachable()
        } catch {
            if EncounterClient.isSessionExpiredError(error) {
                return
            }
            markEngineUnreachable()
        }
    }

    var activeGames: [GameInfo] {
        games.filter { $0.inProgress || $0.started && !$0.finished }
    }

    var upcomingGames: [GameInfo] {
        games.filter { !$0.started && !$0.finished }
    }

    var selectedTeam: TeamInfo? {
        guard let selectedTeamID else { return myTeams.first }
        return myTeams.first { Int64($0.id) == selectedTeamID }
    }

    var currentTeamID: Int64? {
        if let selectedTeamID { return selectedTeamID }
        if let teamManagementInfo { return Int64(teamManagementInfo.teamID) }
        return myTeams.first.map { Int64($0.id) }
    }

    var currentTeamName: String {
        if let teamManagementInfo, !teamManagementInfo.teamName.isEmpty {
            return teamManagementInfo.teamName
        }
        return selectedTeam?.name ?? ""
    }

    func isGameActive(_ game: GameInfo) -> Bool {
        game.inProgress || (game.started && !game.finished)
    }

    func isGameActive(gameID: Int64) -> Bool {
        games.first { $0.id == Int(gameID) }.map(isGameActive) ?? false
    }

    func hasUserJoined(_ model: GameModel) -> Bool {
        switch model.event {
        case GameEvent.playerNoApplication,
             GameEvent.teamNoApplication,
             GameEvent.playerNotAccepted,
             GameEvent.playerNotLoggedIn,
             GameEvent.playerNoTeam,
             GameEvent.playerInactive,
             GameEvent.gameNotFound,
             GameEvent.engineMismatch:
            return false
        default:
            break
        }
        return !model.login.isEmpty || !model.teamName.isEmpty
    }

    func hasUserJoined(gameID: Int64) -> Bool {
        guard let model = currentModel, model.gameID == gameID else {
            return false
        }
        return hasUserJoined(model)
    }

    func needsGameEntry(gameID: Int64) -> Bool {
        guard let model = currentModel, model.gameID == gameID else {
            return true
        }
        return needsGameEntry(model)
    }

    func needsGameEntry(_ model: GameModel) -> Bool {
        if isApplicationPending(model) {
            return false
        }
        switch model.event {
        case GameEvent.playerNoApplication, GameEvent.teamNoApplication:
            return true
        case GameEvent.playerNotLoggedIn,
             GameEvent.playerNoTeam,
             GameEvent.playerInactive,
             GameEvent.gameNotFound,
             GameEvent.engineMismatch:
            return false
        default:
            return !hasUserJoined(model)
        }
    }

    func isGameModerated(gameID: Int64) -> Bool {
        if let game = games.first(where: { $0.id == Int(gameID) }) {
            return game.isModerated
        }
        return moderationByGameID[Int(gameID)] ?? false
    }

    func isApplicationPending(_ game: GameModel) -> Bool {
        game.event == GameEvent.playerNotAccepted
    }

    func entryActionTitle(gameID: Int64) -> String {
        isGameModerated(gameID: gameID) ? "Подать заявку на игру" : "Войти в игру"
    }

    func ensureGameModerationLoadedForUI(gameID: Int64) async {
        await ensureGameModerationLoaded(gameID: gameID)
    }

    func refreshGameRegistrationState(gameID: Int64) async {
        guard hasStoredSession else { return }
        guard selectedGameID == nil || selectedGameID == gameID else { return }

        do {
            let model = try await withSessionRecovery { try await $0.gameModel(gameID: gameID) }
            selectGame(gameID)
            setCurrentModel(model)
            try saveCookies(from: try ensureClient())
            await refreshAfterTransientLevelEventIfNeeded(gameID: gameID)
            updateGameStartCountdown(from: currentModel, gameID: gameID)
        } catch {
            // Keep the current UI if the probe fails.
        }
    }

    var isCurrentGameComplete: Bool {
        currentModel?.isGameComplete == true
    }

    var isMonitoringGame: Bool {
        selectedGameID != nil
    }

    var hasStoredSession: Bool {
        loadSessionCookies() != nil || hasStoredCredentials
    }

    var hasStoredCredentials: Bool {
        let trimmedLogin = login.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLogin.isEmpty else { return false }
        return KeychainCredentialsStore.loadPassword(domain: settings.domain, login: trimmedLogin) != nil
    }

    init() {
        EncounterSessionStore.migrateLegacyStorageIfNeeded()
        let hadSavedSettings = EncounterSharedStorage.data(forKey: settingsKey) != nil
        settings = EncounterSessionStore.loadSettings()
        login = EncounterSessionStore.loadLogin()
        if let saved = UserDefaults.standard.stringArray(forKey: knownDomainsKey), !saved.isEmpty {
            knownDomains = saved
        } else {
            knownDomains = [
                DomainSettings.defaultDomain,
                "demo.en.cx",
                "tech.en.cx",
                "moscow.en.cx",
                "world.en.cx",
            ]
        }
        applyDefaultDomainIfNeeded(hadSavedSettings: hadSavedSettings)
        rememberDomain(settings.domain)
        selectedGameID = EncounterSessionStore.loadSelectedGameID()
        queue.onBackOnline = { [weak self] in
            Task { @MainActor in
                await self?.flushQueueNow(silent: true)
            }
        }
        queue.onPendingAdded = { [weak self] in
            Task { @MainActor in
                await self?.syncLiveActivity()
                BackgroundQueueService.shared.scheduleProcessing()
                guard self?.engineReachable == true else { return }
                await self?.flushQueueNow(silent: true)
            }
        }
        if !queue.pending.isEmpty {
            engineReachable = false
        }
        configureBackgroundDelivery()
        startQueueProcessor()
    }

    private func selectGame(_ gameID: Int64?) {
        if selectedGameID != gameID {
            finalTeamStanding = nil
            finalStandingLoadedGameID = nil
            finalStandingTask?.cancel()
            finalStandingTask = nil
        }
        selectedGameID = gameID
        EncounterSessionStore.saveSelectedGameID(gameID)
        scheduleHintUnlockRefresh(for: currentModel)
    }

    private func applyDefaultDomainIfNeeded(hadSavedSettings: Bool) {
        let normalizedHome = settings.homeDomain?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let normalizedHome, !normalizedHome.isEmpty {
            if !Self.isMockDomain(settings.domain),
               (!hadSavedSettings || settings.domain.isEmpty || Self.isLegacyPlaceholderDomain(settings.domain)) {
                settings.domain = normalizedHome
            }
            return
        }

        if !hadSavedSettings || settings.domain.isEmpty || settings.domain == "demo.en.cx" {
            settings.domain = DomainSettings.defaultDomain
        }
    }

    /// Built-in Encounter hosts used only until the player's home domain is known.
    private static func isLegacyPlaceholderDomain(_ domain: String) -> Bool {
        switch domain.lowercased() {
        case "world.en.cx", "demo.en.cx":
            return true
        default:
            return false
        }
    }

    private static func isMockDomain(_ domain: String) -> Bool {
        domain.lowercased() == DomainSettings.defaultDomain
    }

    func configureBackgroundDelivery() {
        BackgroundQueueService.shared.flushHandler = { [weak self] in
            guard let self else { return true }
            let queueIsEmpty = await self.flushQueueNow(silent: true)
            if queueIsEmpty {
                await self.pollActiveGameIfNeeded(skipWhenQueuePending: true)
            }
            return queueIsEmpty || self.isAntiSpamBackoffActive
        }
    }

    func requestNotificationAuthorizationIfNeeded() async {
        guard settings.pushOnNewLevel || settings.pushOnNewHint || settings.liveActivityEnabled else { return }
        _ = await GameEventNotificationService.shared.requestAuthorizationIfNeeded()
    }

    func handleAppBackground() {
        BackgroundQueueService.shared.scheduleProcessing()
        if !queue.pending.isEmpty {
            BackgroundQueueService.shared.runAggressiveFlushLoop { [weak self] in
                guard let self else { return true }
                let queueIsEmpty = await self.flushQueueNow(silent: true)
                if queueIsEmpty {
                    await self.pollActiveGameIfNeeded(skipWhenQueuePending: true)
                }
                return queueIsEmpty || self.isAntiSpamBackoffActive
            }
        }
        if selectedGameID != nil,
           settings.pushOnNewLevel || settings.pushOnNewHint || currentModel?.isGameFinished == true {
            Task { await pollActiveGameWhileInBackground() }
        }
    }

    func updateScreenWakeLock() {
        let shouldStayAwake = selectedScreen == .game
            && selectedGameID != nil
            && !isCurrentGameComplete
        guard shouldStayAwake != keepScreenAwake else { return }
        keepScreenAwake = shouldStayAwake
        UIApplication.shared.isIdleTimerDisabled = shouldStayAwake
    }

    func restoreSession() async {
        guard loadSessionCookies() != nil || hasStoredCredentials else { return }

        do {
            if let cookies = loadSessionCookies() {
                let client = try ensureClient()
                try client.importCookies(cookies)
                updateHomeDomainIfPossible(using: client)
            }
            try await refreshGamesNow()
            statusMessage = ""
        } catch {
            guard EncounterClient.isSessionExpiredError(error) || error is SessionRecoveryError else {
                presentError(error)
                return
            }
            do {
                try await reloginSilently()
                updateHomeDomainIfPossible(using: try ensureClient())
                try await refreshGamesNow()
                statusMessage = ""
            } catch {
                presentError(error)
            }
        }
        syncWidgetSnapshot()
    }

    @discardableResult
    func loginAction() async -> Bool {
        let succeeded = await runBusy("Авторизация...") {
            persistAuthorizationSettings()
            let client = try rebuildClient()
            _ = try client.login(user: login, password: password)
            try saveCookies(from: client)
            try saveCredentials(password: password)
            updateHomeDomainIfPossible(using: client)
            rememberDomain(settings.domain)
            statusMessage = "Вход выполнен"
            password = ""
            try await refreshGamesNow()
        }
        if succeeded {
            selectedScreen = .games
            syncWidgetSnapshot()
        }
        return succeeded
    }

    private func updateHomeDomainIfPossible(using client: EncounterClient) {
        guard let profile = try? client.profile() else { return }
        let normalized = profile.domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }

        if settings.homeDomain?.lowercased() != normalized {
            settings.homeDomain = normalized
            saveSettings()
        }

        // Stay on the dev mock host; do not follow "прописка" onto production domains.
        guard !Self.isMockDomain(settings.domain) else { return }

        // If we are on a built-in placeholder, switch to the player's home domain.
        if Self.isLegacyPlaceholderDomain(settings.domain) {
            settings.domain = normalized
            rememberDomain(normalized)
            persistAuthorizationSettings()
            self.client = nil
        }
    }

    func selectDomain(_ domain: String) async {
        let normalized = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }
        guard normalized != settings.domain else { return }

        settings.domain = normalized
        rememberDomain(normalized)
        persistAuthorizationSettings()
        client = nil
        await refreshGames()
    }

    func rememberDomain(_ domain: String) {
        let normalized = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }
        var domains = knownDomains.filter { $0 != normalized }
        domains.insert(normalized, at: 0)
        knownDomains = Array(domains.prefix(20))
        UserDefaults.standard.set(knownDomains, forKey: knownDomainsKey)
    }

    func refreshGames() async {
        await runBusy("Загрузка игр...") {
            try await refreshGamesNow()
        }
    }

    func refreshTeam() async {
        guard hasStoredSession else {
            myTeams = []
            selectedTeamID = nil
            teamManagementInfo = nil
            teamInvitations = []
            errorMessage = "Войдите в аккаунт в настройках, чтобы управлять командой."
            return
        }

        await runBusy("Загрузка команды...") {
            try await refreshTeamNow()
        }
    }

    func selectTeam(_ teamID: Int64) async {
        selectedTeamID = teamID
        await runBusy("Загрузка команды...") {
            teamManagementInfo = try await withSessionRecovery {
                try await $0.teamManagementInfo(teamID: teamID)
            }
            try saveCookies(from: try ensureClient())
            statusMessage = "Команда загружена"
        }
    }

    func requestTeamMembership(_ teamName: String) async {
        let trimmed = teamName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Введите название команды"
            return
        }
        await runBusy("Отправка заявки...") {
            try await withSessionRecovery { try await $0.requestTeamMembership(teamName: trimmed) }
            try saveCookies(from: try ensureClient())
            try await refreshTeamNow()
            statusMessage = "Заявка отправлена"
        }
    }

    func acceptTeamInvitation(_ invitation: TeamInvitation) async {
        await runBusy("Принятие приглашения...") {
            try await withSessionRecovery { try await $0.acceptTeamInvitation(teamID: Int64(invitation.teamID)) }
            try saveCookies(from: try ensureClient())
            try await refreshTeamNow(preferredTeamID: Int64(invitation.teamID))
            statusMessage = "Приглашение принято"
        }
    }

    func rejectTeamInvitation(_ invitation: TeamInvitation) async {
        await runBusy("Отклонение приглашения...") {
            try await withSessionRecovery { try await $0.rejectTeamInvitation(teamID: Int64(invitation.teamID)) }
            try saveCookies(from: try ensureClient())
            try await refreshTeamNow()
            statusMessage = "Приглашение отклонено"
        }
    }

    func inviteTeamMember(login: String) async {
        guard let teamID = currentTeamID else {
            statusMessage = "Команда не выбрана"
            return
        }
        let trimmed = login.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Введите логин игрока"
            return
        }
        await runBusy("Отправка приглашения...") {
            try await withSessionRecovery {
                try await $0.inviteTeamMember(teamID: teamID, login: trimmed)
            }
            try saveCookies(from: try ensureClient())
            try await refreshTeamNow(preferredTeamID: teamID)
            statusMessage = "Приглашение отправлено"
        }
    }

    func removeTeamInvitation(_ invitation: TeamPendingInvitation) async {
        guard let teamID = currentTeamID else { return }
        await runBusy("Отзыв приглашения...") {
            try await withSessionRecovery {
                try await $0.removeTeamInvitation(teamID: teamID, userID: Int64(invitation.userID))
            }
            try saveCookies(from: try ensureClient())
            try await refreshTeamNow(preferredTeamID: teamID)
            statusMessage = "Приглашение отозвано"
        }
    }

    func leaveCurrentTeam() async {
        guard let teamID = currentTeamID else { return }
        await runBusy("Выход из команды...") {
            try await withSessionRecovery { try await $0.leaveTeam(teamID: teamID) }
            try saveCookies(from: try ensureClient())
            try await refreshTeamNow()
            statusMessage = "Вы вышли из команды"
        }
    }

    func renameCurrentTeam(_ name: String) async {
        guard let teamID = currentTeamID else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Введите название команды"
            return
        }
        await runBusy("Переименование команды...") {
            try await withSessionRecovery { try await $0.renameTeam(teamID: teamID, name: trimmed) }
            try saveCookies(from: try ensureClient())
            try await refreshTeamNow(preferredTeamID: teamID)
            statusMessage = "Название обновлено"
        }
    }

    func updateCurrentTeamSite(_ site: String) async {
        guard let teamID = currentTeamID else { return }
        await runBusy("Обновление сайта...") {
            try await withSessionRecovery { try await $0.setTeamSite(teamID: teamID, site: site.trimmingCharacters(in: .whitespacesAndNewlines)) }
            try saveCookies(from: try ensureClient())
            statusMessage = "Сайт команды обновлён"
            try await refreshTeamNow(preferredTeamID: teamID)
        }
    }

    func updateCurrentTeamForum(_ forum: String) async {
        guard let teamID = currentTeamID else { return }
        await runBusy("Обновление форума...") {
            try await withSessionRecovery { try await $0.setTeamForum(teamID: teamID, forum: forum.trimmingCharacters(in: .whitespacesAndNewlines)) }
            try saveCookies(from: try ensureClient())
            statusMessage = "Форум команды обновлён"
            try await refreshTeamNow(preferredTeamID: teamID)
        }
    }

    func submitGameApplication(_ gameID: Int64) async {
        await enterGame(gameID)
    }

    func enterGame(_ gameID: Int64) async {
        await ensureGameModerationLoaded(gameID: gameID)
        let moderated = isGameModerated(gameID: gameID)

        guard hasStoredSession else {
            errorMessage = moderated
                ? "Войдите в аккаунт в настройках, чтобы подать заявку на игру."
                : "Войдите в аккаунт в настройках, чтобы войти в игру."
            return
        }

        await runBusy(moderated ? "Подача заявки..." : "Вход в игру...") {
            if needsGameEntry(gameID: gameID) {
                try await submitGameEntry(gameID: gameID)
            }

            selectGame(gameID)
            gameStartCountdown = nil
            setCurrentModel(try await withSessionRecovery { try await $0.gameModel(gameID: gameID) })
            try saveCookies(from: try ensureClient())
            markEngineReachable()
            await refreshAfterTransientLevelEventIfNeeded(gameID: gameID)
            statusMessage = Self.waitingStatusMessage(for: currentModel)
            lastCodeResult = nil
            selectedScreen = .game
            updateScreenWakeLock()
            updateGameStartCountdown(from: currentModel, gameID: gameID)
            await processGameEvents(for: gameID)
            await flushQueueNow(silent: true)
            await syncLiveActivity()
        }
    }

    func stopGameMonitoring() async {
        let stoppedGameID = selectedGameID
        selectGame(nil)
        currentModel = nil
        finalTeamStanding = nil
        finalStandingLoadedGameID = nil
        finalStandingTask?.cancel()
        finalStandingTask = nil
        resetCodeLog()
        gameStartCountdown = nil
        hintUnlockRefreshTask?.cancel()
        hintUnlockRefreshTask = nil
        levelTimeoutRefreshTask?.cancel()
        levelTimeoutRefreshTask = nil
        lastGamePollDate = nil
        lastSyncedLiveActivityState = nil
        lastCodeResult = nil
        teammateCodePopup = nil
        teammateCodePopupDismissTask?.cancel()
        teammateCodePopupDismissTask = nil
        newHintPopup = nil
        serverRoundTripMs = nil
        statusMessage = ""
        selectedScreen = .games
        updateScreenWakeLock()
        if let stoppedGameID {
            GameEventNotificationService.shared.clearSnapshot(gameID: stoppedGameID)
        }
        await liveActivity.end()
        syncWidgetSnapshot()
    }

    func openGame(_ gameID: Int64, presentErrors: Bool = true) async -> Bool {
        await ensureGameModerationLoaded(gameID: gameID)

        return await runBusy("Загрузка уровня...", presentErrors: presentErrors) {
            selectGame(gameID)
            gameStartCountdown = nil
            setCurrentModel(try await withSessionRecovery { try await $0.gameModel(gameID: gameID) })
            try saveCookies(from: try ensureClient())
            markEngineReachable()
            await refreshAfterTransientLevelEventIfNeeded(gameID: gameID)
            if currentModel?.level != nil {
                statusMessage = ""
            }
            lastCodeResult = nil
            selectedScreen = .game
            updateScreenWakeLock()
            updateGameStartCountdown(from: currentModel, gameID: gameID)
            await processGameEvents(for: gameID)
            await flushQueueNow(silent: true)
            await syncLiveActivity()
        }
    }

    func refreshLevel() async {
        await refreshLevel(showUI: true)
    }

    func refreshCodeLog() async {
        guard let model = currentModel else { return }
        let gameID = Int64(model.gameID)
        guard !isCodeLogLoading else { return }
        guard queue.isOnline else {
            codeLogStatusMessage = cachedLevelStatusMessage(reason: .offline)
            return
        }

        isCodeLogLoading = true
        codeLogStatusMessage = "Загрузка журнала..."
        defer { isCodeLogLoading = false }

        var actionsByID: [Int: CodeAction] = [:]
        for action in model.level?.mixedActions ?? [] {
            actionsByID[action.actionID] = action
        }

        let levelNumbers = Set(
            model.levels
                .map(\.levelNumber)
                .filter { $0 > 0 }
        )

        var skippedLevels = 0
        do {
            for levelNumber in levelNumbers.sorted() {
                if Task.isCancelled { return }
                if model.level?.number == levelNumber {
                    continue
                }
                do {
                    let levelModel = try await withSessionRecovery {
                        try await $0.gameModelLevel(gameID: gameID, levelNumber: Int64(levelNumber))
                    }
                    for action in levelModel.level?.mixedActions ?? [] {
                        actionsByID[action.actionID] = action
                    }
                } catch {
                    skippedLevels += 1
                }
            }

            guard selectedGameID == gameID else { return }
            codeLogActions = actionsByID.values.sorted {
                if $0.levelNumber != $1.levelNumber {
                    return $0.levelNumber > $1.levelNumber
                }
                return $0.actionID > $1.actionID
            }
            codeLogLoadedGameID = gameID
            if skippedLevels > 0 {
                codeLogStatusMessage = "Часть уровней не удалось загрузить: \(skippedLevels)"
            } else {
                codeLogStatusMessage = codeLogActions.isEmpty ? "Пробитых кодов пока нет" : ""
            }
            try saveCookies(from: try ensureClient())
            markEngineReachable()
        } catch {
            codeLogStatusMessage = EncounterClient.userFacingDescription(for: error)
        }
    }

    func refreshLevelSilently() async {
        await refreshLevel(showUI: false)
    }

    func pollWaitingGameState(gameID: Int64) async {
        if currentModel?.gameID != Int(gameID) {
            await refreshLevelSilently()
        }

        while !Task.isCancelled {
            guard shouldContinueWaitingPoll(gameID: gameID) else { return }

            let delay = waitingPollInterval(for: gameID)
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled, shouldContinueWaitingPoll(gameID: gameID) else { return }
            await refreshLevelSilently()
        }
    }

    private func shouldContinueWaitingPoll(gameID: Int64) -> Bool {
        selectedScreen == .game
            && selectedGameID == gameID
            && currentModel?.gameID == Int(gameID)
            && currentModel?.level == nil
            && currentModel?.isGameComplete != true
    }

    private func waitingPollInterval(for gameID: Int64) -> TimeInterval {
        if let model = currentModel, isApplicationPending(model) {
            return 20
        }
        if let countdown = gameStartCountdown {
            let remaining = countdown.remainingSeconds()
            if remaining <= 0 { return 2 }
            if remaining <= 15 { return 3 }
            if remaining <= 60 { return 8 }
            return min(30, max(10, Double(remaining / 4)))
        }
        if isGameActive(gameID: gameID), hasUserJoined(gameID: gameID) {
            return 5
        }
        return 15
    }

    private func refreshLevel(showUI: Bool) async {
        guard let selectedGameID else { return }
        if !queue.isOnline {
            if showUI, currentModel != nil {
                statusMessage = cachedLevelStatusMessage(reason: .offline)
            }
            return
        }
        if !engineReachable, currentModel != nil {
            if showUI {
                statusMessage = cachedLevelStatusMessage(reason: .serverUnreachable)
            }
            return
        }
        if !showUI, isBusy { return }
        // Background refreshes must respect the anti-spam backoff; only an explicit user refresh may retry.
        if !showUI, isAntiSpamBackoffActive { return }

        let hadCachedLevel = currentModel != nil
        let succeeded = await runBusy(
            showUI ? "Обновление уровня..." : "",
            showBusy: showUI,
            presentErrors: showUI && !hadCachedLevel
        ) {
            setCurrentModel(try await withSessionRecovery { try await $0.gameModel(gameID: selectedGameID) })
            lastGamePollDate = Date()
            try saveCookies(from: try ensureClient())
            markEngineReachable()
            await refreshAfterTransientLevelEventIfNeeded(gameID: selectedGameID)
            if currentModel?.level != nil {
                statusMessage = ""
            }
            updateGameStartCountdown(from: currentModel, gameID: selectedGameID)
            await processGameEvents(for: selectedGameID)
            await syncLiveActivity()
        }
        if !succeeded {
            markEngineUnreachable()
            if showUI, hadCachedLevel {
                errorMessage = nil
                statusMessage = cachedLevelStatusMessage(reason: .serverUnreachable)
            }
        }
    }

    private func updateGameStartCountdown(from model: GameModel?, gameID: Int64) {
        guard let model,
              model.gameID == Int(gameID),
              let countdown = model.startCountdown else {
            gameStartCountdown = nil
            return
        }
        gameStartCountdown = countdown
    }

    private enum CachedLevelStatusReason {
        case offline
        case serverUnreachable
    }

    private func cachedLevelStatusMessage(reason: CachedLevelStatusReason) -> String {
        switch reason {
        case .offline:
            return "Нет сети. Показаны сохранённые данные уровня."
        case .serverUnreachable:
            return "Сервер недоступен. Показаны сохранённые данные уровня."
        }
    }

    func canSubmitLevelCode(on level: Level) -> Bool {
        levelSubmissionBlockMessage(for: level) == nil
    }

    func canSubmitBonusCode(on level: Level) -> Bool {
        bonusSubmissionBlockMessage(for: level) == nil
    }

    func submitCode(_ text: String, kind: CodeSubmissionKind = .level) {
        guard let model = currentModel, model.isPlayable, let level = model.level else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let message = submissionBlockMessage(for: level, kind: kind) {
            statusMessage = message
            return
        }

        let submission = CodeSubmission(
            gameID: Int64(model.gameID),
            levelID: Int64(level.levelID),
            levelNumber: Int64(level.number),
            code: trimmed,
            kind: kind
        )

        if !queue.isOnline {
            queue.enqueue(submission)
            statusMessage = queueAddedMessage()
            Task { await syncLiveActivity() }
            BackgroundQueueService.shared.scheduleProcessing()
            return
        }

        // Skip a 1s network attempt when we already know the engine is down — enqueue immediately.
        if !engineReachable {
            queue.enqueue(submission)
            statusMessage = queueAddedMessage(engineUnreachable: true)
            Task { await syncLiveActivity() }
            BackgroundQueueService.shared.scheduleProcessing()
            return
        }

        Task { await sendCodeNow(submission) }
    }

    private func sendCodeNow(_ submission: CodeSubmission) async {
        do {
            let started = DispatchTime.now()
            let updated = try await withSessionRecovery { try await $0.sendCode(submission) }
            recordServerRoundTrip(since: started)
            setCurrentModel(updated)
            try saveCookies(from: try ensureClient())
            markEngineReachable()
            statusMessage = resultMessage(from: updated)
            lastCodeResult = feedback(from: updated)
            await refreshAfterTransientLevelEventIfNeeded(gameID: submission.gameID)
            updateScreenWakeLock()
            if let gameID = selectedGameID {
                await processGameEvents(for: gameID)
            }
            await syncLiveActivity()
        } catch {
            markEngineUnreachable()
            queue.enqueue(submission)
            statusMessage = queueAddedMessage(error: error)
            await syncLiveActivity()
            BackgroundQueueService.shared.scheduleProcessing()
        }
    }

    private func submissionBlockMessage(for level: Level, kind: CodeSubmissionKind) -> String? {
        switch kind {
        case .level:
            return levelSubmissionBlockMessage(for: level)
        case .bonus:
            return bonusSubmissionBlockMessage(for: level)
        }
    }

    private func levelSubmissionBlockMessage(for level: Level) -> String? {
        if level.isPassed {
            return "Уровень уже пройден — ответы больше не отправляются."
        }
        if level.dismissed {
            return "Уровень снят — дождитесь следующего уровня."
        }
        if level.hasAnswerBlockRule, level.blockDuration > 0 {
            return "Ответы на уровень заблокированы ещё на \(level.blockDuration) сек. Бонусные ответы можно отправить отдельно."
        }
        return nil
    }

    private func bonusSubmissionBlockMessage(for level: Level) -> String? {
        if level.isPassed {
            return "Уровень уже пройден — бонусные ответы больше не отправляются."
        }
        if level.dismissed {
            return "Уровень снят — бонусные ответы больше не отправляются."
        }
        if level.bonuses.allSatisfy(\.isAnswered) {
            return "На уровне нет неразгаданных бонусов."
        }
        return nil
    }

    func requestPenaltyHelp(_ help: Help) async {
        guard let model = currentModel, model.isPlayable, model.level != nil else { return }
        guard help.isPenalty else { return }
        if help.remainSeconds > 0 {
            statusMessage = "Штрафная подсказка ещё недоступна."
            return
        }
        if help.unlockedText != nil || help.penaltyHelpState == 2 {
            statusMessage = "Штрафная подсказка уже открыта."
            return
        }

        let gameID = Int64(model.gameID)
        await runBusy("Открытие штрафной подсказки...") {
            let updated = try await withSessionRecovery {
                try await $0.penaltyHint(gameID: gameID, penaltyID: Int64(help.helpID))
            }
            setCurrentModel(updated)
            try saveCookies(from: try ensureClient())
            markEngineReachable()
            statusMessage = "Штрафная подсказка открыта"
            await refreshAfterTransientLevelEventIfNeeded(gameID: gameID)
            await processGameEvents(for: gameID)
            await syncLiveActivity()
        }
    }

    func flushQueue(silent: Bool = false) async {
        await runBusy(silent ? "" : "Отправка очереди...", showBusy: !silent) {
            guard queue.isOnline else {
                if !silent {
                    statusMessage = "Нет сети для отправки очереди"
                }
                return
            }
            guard !queue.pending.isEmpty else {
                if !silent {
                    statusMessage = "Очередь пуста"
                }
                return
            }
            await flushQueueNow(silent: silent)
        }
    }

    func flushQueueOnResume() async {
        _ = await flushQueueNow(silent: true)
        if let selectedGameID, shouldContinueWaitingPoll(gameID: selectedGameID) {
            await refreshLevelSilently()
        }
    }

    func clearQueue() {
        queue.clear()
        statusMessage = "Очередь очищена"
        Task { await syncLiveActivity() }
    }

    func persistAuthorizationSettings() {
        saveSettings()
        EncounterSessionStore.saveLogin(login)
    }

    func applyHARRecordingSetting() {
        do {
            if settings.harUploadEnabled {
                if !settings.harRecordingEnabled {
                    settings.harRecordingEnabled = true
                    settings.harRecordingAutoEnabledByUpload = true
                }
            } else if settings.harRecordingAutoEnabledByUpload {
                settings.harRecordingEnabled = false
                settings.harRecordingAutoEnabledByUpload = false
            } else if !settings.harRecordingEnabled {
                settings.harRecordingAutoEnabledByUpload = false
            }
            try ensureClient().setHARRecordingEnabled(settings.harCaptureEnabled)
            refreshHAREntryCount()
        } catch {
            // Client is created on first login or session restore.
        }
    }

    func refreshHAREntryCount() {
        harEntryCount = client?.harEntryCount() ?? 0
    }

    func clearHARCapture() {
        client?.clearHAR()
        lastUploadedHAREntryCount = 0
        refreshHAREntryCount()
        statusMessage = "HAR очищен"
    }

    func exportHARFileURL() throws -> URL {
        let client = try ensureClient()
        let json = try client.exportHAR()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let safeDomain = settings.domain
            .lowercased()
            .replacingOccurrences(of: "/", with: "-")
        let filename = "encounter-\(safeDomain)-\(timestamp).har"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try json.write(to: url, atomically: true, encoding: .utf8)
        refreshHAREntryCount()
        return url
    }

    private func startQueueProcessor() {
        queueProcessorTask?.cancel()
        queueProcessorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.processQueueIfNeeded()
                let delay = await MainActor.run {
                    self?.queueProcessorDelay() ?? 6.0
                }
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    private func queueProcessorDelay() -> TimeInterval {
        guard !queue.pending.isEmpty else { return 6.0 }
        return engineReachable ? 0.4 : queueRetryBackoffSeconds
    }

    private func recordQueueRetryFailure() {
        queueRetryBackoffSeconds = min(max(queueRetryBackoffSeconds * 1.5, 1.0), 8.0)
    }

    private func resetQueueRetryBackoff() {
        queueRetryBackoffSeconds = 0.4
    }

    private func processQueueIfNeeded() async {
        guard queue.isOnline, !queue.pending.isEmpty else {
            await pollActiveGameIfNeeded()
            return
        }
        guard !isAntiSpamBackoffActive else { return }
        _ = await flushQueueNow(silent: true)
    }

    private func pollActiveGameIfNeeded(force: Bool = false, skipWhenQueuePending: Bool = false) async {
        guard let gameID = selectedGameID else { return }
        let waitingForFinishTransition = currentModel?.isGameFinished == true
        let waitingForLevelOrStart = selectedScreen == .game
            && currentModel?.level == nil
            && currentModel?.isGameComplete != true
        let activeLevelOnScreen = selectedScreen == .game
            && currentModel?.level != nil
            && currentModel?.isGameComplete != true
        guard settings.pushOnNewLevel || settings.pushOnNewHint || settings.liveActivityEnabled
            || waitingForFinishTransition || waitingForLevelOrStart || activeLevelOnScreen else {
            return
        }
        guard queue.isOnline, !queue.isFlushing else { return }
        if skipWhenQueuePending, !queue.pending.isEmpty { return }
        if isAntiSpamBackoffActive { return }

        let pollInterval: TimeInterval
        if waitingForFinishTransition || waitingForLevelOrStart {
            // Transient transitions (level being swapped, game about to start) resolve quickly.
            pollInterval = 5.0
        } else if activeLevelOnScreen {
            // Steady play on an open level: poll far less aggressively to stay under anti-spam limits.
            pollInterval = activeLevelPollInterval
        } else {
            pollInterval = gamePollInterval
        }
        if !force, let lastGamePollDate,
           Date().timeIntervalSince(lastGamePollDate) < pollInterval {
            return
        }
        lastGamePollDate = Date()

        do {
            let model = try await withSessionRecovery { try await $0.gameModel(gameID: gameID) }
            setCurrentModel(model)
            try saveCookies(from: try ensureClient())
            markEngineReachable()
            await refreshAfterTransientLevelEventIfNeeded(gameID: gameID)
            updateGameStartCountdown(from: currentModel, gameID: gameID)
            await processGameEvents(for: gameID)
            await syncLiveActivity()
        } catch {
            if EncounterClient.isSessionExpiredError(error) {
                return
            }
        }
    }

    private func pollActiveGameWhileInBackground() async {
        let deadline = Date().addingTimeInterval(28)
        while Date() < deadline {
            await pollActiveGameIfNeeded(force: true, skipWhenQueuePending: true)
            try? await Task.sleep(for: .seconds(8))
        }
    }

    private func processGameEvents(for gameID: Int64) async {
        guard let model = currentModel else { return }
        await GameEventNotificationService.shared.processModelUpdate(
            gameID: gameID,
            gameTitle: model.gameTitle,
            model: model,
            notifyNewLevel: settings.pushOnNewLevel,
            notifyNewHint: settings.pushOnNewHint
        )
    }

    @discardableResult
    private func flushQueueNow(silent: Bool) async -> Bool {
        guard queue.isOnline, !queue.pending.isEmpty else {
            await syncLiveActivity()
            return queue.pending.isEmpty
        }
        guard !isAntiSpamBackoffActive else { return false }
        guard !queue.isFlushing else { return queue.pending.isEmpty }

        let pendingBefore = queue.pending.count
        var shouldSyncLiveActivity = false

        do {
            // When codes are queued, send them immediately (1s timeout each). A pre-flush ping only
            // blocked real code attempts after the first timeout (e.g. mock PZDC network drop).
            if !engineReachable, queue.pending.isEmpty, let probeGameID = selectedGameID {
                let started = DispatchTime.now()
                setCurrentModel(try await withSessionRecovery { try await $0.pingGame(gameID: probeGameID) })
                recordServerRoundTrip(since: started)
                try saveCookies(from: try ensureClient())
                markEngineReachable()
                await refreshAfterTransientLevelEventIfNeeded(gameID: probeGameID)
                if let gameID = selectedGameID {
                    await processGameEvents(for: gameID)
                }
            }

            if let model = try await queue.flush(send: { submission in
                let started = DispatchTime.now()
                let updated = try await self.withSessionRecovery { try await $0.sendCode(submission) }
                self.recordServerRoundTrip(since: started)
                return updated
            }) {
                setCurrentModel(model)
                try saveCookies(from: try ensureClient())
                markEngineReachable()
                resetQueueRetryBackoff()
                if let gameID = selectedGameID {
                    await refreshAfterTransientLevelEventIfNeeded(gameID: gameID)
                }
                if let gameID = selectedGameID {
                    await processGameEvents(for: gameID)
                }
                let message = queue.pending.isEmpty
                    ? "Очередь отправлена"
                    : "Отправлено частично, в очереди \(queue.pending.count)"
                if !silent || queue.pending.isEmpty {
                    statusMessage = message
                }
                lastCodeResult = feedback(from: model)
                shouldSyncLiveActivity = true
            } else if !queue.pending.isEmpty {
                markEngineUnreachable()
                recordQueueRetryFailure()
                if !silent {
                    statusMessage = "Движок недоступен, очередь сохранена"
                    shouldSyncLiveActivity = true
                }
            }
        } catch {
            markEngineUnreachable()
            recordQueueRetryFailure()
            if !silent {
                presentError(error)
                shouldSyncLiveActivity = true
            } else if EncounterClient.isAntiSpamError(error) {
                antiSpamVerificationURL = EncounterClient.antiSpamURL(from: error, settings: settings)
                    ?? EncounterClient.defaultAntiSpamURL(settings: settings)
                showAntiSpamVerification = true
                shouldSyncLiveActivity = true
            }
        }

        if shouldSyncLiveActivity || queue.pending.count != pendingBefore {
            await syncLiveActivity()
        }
        return queue.pending.isEmpty
    }

    func applyLiveActivitySetting() async {
        saveSettings()
        guard settings.liveActivityEnabled else {
            await liveActivity.end()
            return
        }
        await syncLiveActivity()
    }

    private func syncLiveActivity() async {
        syncWidgetSnapshot()

        guard settings.liveActivityEnabled else {
            lastSyncedLiveActivityState = nil
            await liveActivity.end()
            return
        }

        let display = settings.liveActivityDisplay
        let rawTitle = currentModel?.gameTitle
            ?? games.first { $0.id == selectedGameID.map(Int.init) }?.title
            ?? "Encounter"
        let gameTitle = display.showGameTitle ? rawTitle : ""

        if let state = liveActivityContentState() {
            if state == lastSyncedLiveActivityState { return }
            lastSyncedLiveActivityState = state
            await liveActivity.sync(state: state, gameTitle: gameTitle)
            return
        }

        // No playable level right now (e.g. between levels). Keep an already-running plate
        // alive with a minimal "waiting" state instead of tearing it down — otherwise the
        // Dynamic Island / Live Activity vanishes entirely mid-game. Never create a new one here.
        if let waiting = liveActivityWaitingState() {
            if waiting == lastSyncedLiveActivityState { return }
            lastSyncedLiveActivityState = waiting
            await liveActivity.updateIfActive(state: waiting, gameTitle: gameTitle)
            return
        }

        lastSyncedLiveActivityState = nil
        await liveActivity.end()
    }

    /// Minimal Live Activity state for transient no-level moments while the game is still in play.
    /// Returns nil once the game is complete (so the plate is allowed to end).
    private func liveActivityWaitingState() -> QueueActivityAttributes.ContentState? {
        guard selectedGameID != nil, let model = currentModel else { return nil }
        guard !model.isGameComplete else { return nil }

        let display = settings.liveActivityDisplay
        return QueueActivityAttributes.ContentState(
            pendingCount: display.showQueue ? queue.pending.count : 0,
            status: "Ждём открытия уровня…",
            isOnline: queueConnectionStatus == .ready,
            levelNumber: 0,
            levelName: "",
            teamName: display.showTeam ? model.teamName : "",
            sectorsPassed: 0,
            sectorsRequired: 0,
            bonusesPassed: 0,
            bonusesTotal: 0,
            recentCodes: [],
            hints: [],
            levelEndsAt: nil,
            nextHintUnlocksAt: nil
        )
    }

    private func refreshAfterTransientLevelEventIfNeeded(gameID: Int64) async {
        guard selectedGameID == gameID,
              let model = currentModel,
              model.gameID == Int(gameID),
              Self.isTransientLevelChangeEvent(model.event),
              queue.isOnline else {
            return
        }

        let transitionStatus = EncounterClient.eventText(for: model.event)
        do {
            let refreshed = try await withSessionRecovery { try await $0.gameModel(gameID: gameID) }
            setCurrentModel(refreshed)
            try saveCookies(from: try ensureClient())
            markEngineReachable()
        } catch {
            statusMessage = transitionStatus
        }
    }

    private static func isTransientLevelChangeEvent(_ event: Int) -> Bool {
        switch event {
        case GameEvent.levelDismissed16,
             GameEvent.levelDismissed18,
             GameEvent.levelAutoAdvance,
             GameEvent.allSectorsSolved,
             GameEvent.levelDismissed21,
             GameEvent.levelTimeout:
            return true
        default:
            return false
        }
    }

    private func setCurrentModel(_ model: GameModel) {
        guard let selectedGameID, selectedGameID == Int64(model.gameID) else { return }

        let previousModel = currentModel
        let wasPlayable = currentModel?.isPlayable ?? true
        currentModel = model
        updateNewHintPopup(previousModel: previousModel, currentModel: model)
        updateTeammateCodePopup(previousModel: previousModel, currentModel: model)
        mergeCodeLogActions(model.level?.mixedActions ?? [], gameID: selectedGameID)
        liveActivityModelAnchor = Date()
        lastSyncedLiveActivityState = nil
        scheduleHintUnlockRefresh(for: model)
        scheduleLevelTimeoutRefresh(for: model)

        if model.isGameComplete {
            updateFinalStanding(from: model)
            if wasPlayable {
                statusMessage = EncounterClient.eventText(for: model.event)
                Task { try? await refreshGamesNow() }
            }
            if model.isGameEnded {
                GameEventNotificationService.shared.clearSnapshot(gameID: Int64(model.gameID))
            }
            updateScreenWakeLock()
        } else if model.level == nil {
            finalTeamStanding = nil
            finalStandingLoadedGameID = nil
            finalStandingTask?.cancel()
            finalStandingTask = nil
            teammateCodePopupDismissTask?.cancel()
            teammateCodePopupDismissTask = nil
            teammateCodePopup = nil
            statusMessage = Self.waitingStatusMessage(for: model)
        }
    }

    private func updateFinalStanding(from model: GameModel) {
        if let place = model.finishPlace, place > 0 {
            finalTeamStanding = FinalTeamStanding(place: place, teamsCount: 0)
            return
        }

        let gameID = Int64(model.gameID)
        guard finalStandingLoadedGameID != gameID else { return }
        guard finalStandingTask == nil || finalStandingTask?.isCancelled == true else { return }

        finalStandingTask = Task { [weak self, gameID, teamName = model.teamName, login = model.login] in
            await self?.loadFinalStanding(gameID: gameID, teamName: teamName, login: login)
        }
    }

    private func loadFinalStanding(gameID: Int64, teamName: String, login: String) async {
        defer { finalStandingTask = nil }
        guard queue.isOnline else { return }

        do {
            let stats = try await withSessionRecovery { try await $0.gameStatistics(gameID: gameID) }
            guard selectedGameID == gameID else { return }
            finalStandingLoadedGameID = gameID
            finalTeamStanding = Self.finalStanding(from: stats, teamName: teamName, login: login)
            try saveCookies(from: try ensureClient())
            markEngineReachable()
        } catch {
            // Keep retrying on later refreshes; the finish screen can still be shown without standings.
        }
    }

    private static func finalStanding(from stats: GameStatisticsResponse, teamName: String, login: String) -> FinalTeamStanding? {
        let rows = stats.statItems.filter { !$0.isEmpty }
        guard !rows.isEmpty else { return nil }

        let normalizedTeamName = normalizeStandingName(teamName)
        let normalizedLogin = normalizeStandingName(login)

        for (index, row) in rows.enumerated() {
            let matchesTeam = !normalizedTeamName.isEmpty
                && row.contains { normalizeStandingName($0.teamName) == normalizedTeamName }
            let matchesLogin = normalizedTeamName.isEmpty
                && !normalizedLogin.isEmpty
                && row.contains { normalizeStandingName($0.userName) == normalizedLogin }
            if matchesTeam || matchesLogin {
                return FinalTeamStanding(place: index + 1, teamsCount: rows.count)
            }
        }

        return nil
    }

    private static func normalizeStandingName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func scheduleHintUnlockRefresh(for model: GameModel?) {
        hintUnlockRefreshTask?.cancel()
        hintUnlockRefreshTask = nil

        guard let selectedGameID,
              let model,
              model.gameID == Int(selectedGameID),
              model.isPlayable,
              let level = model.level else {
            return
        }

        let nearestHintRemain = level.nearestLockedHintRemainSeconds
        guard nearestHintRemain > 0 else { return }

        // Floor the delay: a persistently small (or clock-skewed) server RemainSeconds must not spin a tight loop.
        let delay = max(TimeInterval(nearestHintRemain) + 1, minTimerRefreshInterval)
        hintUnlockRefreshTask = Task { [weak self, selectedGameID] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.refreshAfterHintUnlock(gameID: selectedGameID)
        }
    }

    private func refreshAfterHintUnlock(gameID: Int64) async {
        guard selectedGameID == gameID,
              selectedScreen == .game,
              currentModel?.gameID == Int(gameID),
              (currentModel?.level?.nearestLockedHintRemainSeconds ?? 0) > 0,
              queue.isOnline else {
            return
        }

        await refreshLevel(showUI: false)
    }

    private func scheduleLevelTimeoutRefresh(for model: GameModel?) {
        levelTimeoutRefreshTask?.cancel()
        levelTimeoutRefreshTask = nil

        guard let selectedGameID,
              let model,
              model.gameID == Int(selectedGameID),
              model.isPlayable,
              let level = model.level,
              level.timeoutSecondsRemain > 0 else {
            return
        }

        let delay = max(TimeInterval(level.timeoutSecondsRemain) + 1, minTimerRefreshInterval)
        levelTimeoutRefreshTask = Task { [weak self, selectedGameID, levelID = level.levelID] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.refreshAfterLevelTimeout(gameID: selectedGameID, levelID: levelID)
        }
    }

    private func refreshAfterLevelTimeout(gameID: Int64, levelID: Int) async {
        guard selectedGameID == gameID,
              selectedScreen == .game,
              currentModel?.gameID == Int(gameID),
              currentModel?.level?.levelID == levelID,
              currentModel?.isGameComplete != true,
              queue.isOnline else {
            return
        }

        await refreshLevel(showUI: false)
    }

    private func updateNewHintPopup(previousModel: GameModel?, currentModel: GameModel) {
        guard selectedScreen == .game,
              currentModel.isPlayable,
              let previousLevel = previousModel?.level,
              let currentLevel = currentModel.level,
              previousLevel.levelID == currentLevel.levelID else {
            if previousModel?.level?.levelID != currentModel.level?.levelID {
                teammateCodePopupDismissTask?.cancel()
                teammateCodePopupDismissTask = nil
                teammateCodePopup = nil
            }
            return
        }

        let previousHintIDs = Set(Self.visibleUnlockedHints(in: previousLevel).map(\.helpID))
        let newHints = Self.visibleUnlockedHints(in: currentLevel)
            .filter { !previousHintIDs.contains($0.helpID) }
            .sorted { $0.number < $1.number }

        guard !newHints.isEmpty else { return }

        let title = newHints.count == 1
            ? "Новая подсказка \(newHints[0].number)"
            : "Новые подсказки"
        let message = newHints
            .map { help in
                let text = help.unlockedText?.strippingHTML()
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return "Подсказка \(help.number): \(text)"
            }
            .joined(separator: "\n\n")

        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        newHintPopup = NewHintPopup(title: title, message: message)
    }

    private static func visibleUnlockedHints(in level: Level) -> [Help] {
        (level.helps + level.penaltyHelps).filter { $0.unlockedText != nil }
    }

    private func updateTeammateCodePopup(previousModel: GameModel?, currentModel: GameModel) {
        guard selectedScreen == .game,
              currentModel.isPlayable,
              let previousLevel = previousModel?.level,
              let currentLevel = currentModel.level,
              previousLevel.levelID == currentLevel.levelID else {
            return
        }

        let previousActionIDs = Set(previousLevel.mixedActions.map(\.actionID))
        let currentLogin = currentModel.login.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let newActions = currentLevel.mixedActions
            .filter { !previousActionIDs.contains($0.actionID) }
            .filter { action in
                let actionLogin = action.login.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return actionLogin.isEmpty || actionLogin != currentLogin
            }
            .sorted { $0.actionID > $1.actionID }

        guard let latest = newActions.first else { return }

        let answer = latest.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let login = latest.login.trimmingCharacters(in: .whitespacesAndNewlines)
        let codeText = answer.isEmpty ? "код" : answer
        let author = login.isEmpty ? "Игрок команды" : login
        let levelPrefix = latest.levelNumber > 0 ? "Ур. \(latest.levelNumber) · " : ""
        let title = latest.isCorrect ? "Код принят" : "Код не подошёл"
        let suffix = newActions.count > 1 ? "  +\(newActions.count - 1)" : ""
        let message = "\(levelPrefix)\(author): \(codeText)\(suffix)"
        let popup = TeammateCodePopup(
            title: title,
            message: message,
            isCorrect: latest.isCorrect,
            id: UUID()
        )

        teammateCodePopupDismissTask?.cancel()
        teammateCodePopup = popup
        teammateCodePopupDismissTask = Task { [weak self, popupID = popup.id] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self?.teammateCodePopup?.id == popupID else { return }
                self?.teammateCodePopup = nil
                self?.teammateCodePopupDismissTask = nil
            }
        }
    }

    private func mergeCodeLogActions(_ actions: [CodeAction], gameID: Int64) {
        if codeLogLoadedGameID != gameID {
            codeLogActions = []
            codeLogLoadedGameID = gameID
            codeLogStatusMessage = ""
        }
        guard !actions.isEmpty else { return }

        var actionsByID = Dictionary(uniqueKeysWithValues: codeLogActions.map { ($0.actionID, $0) })
        for action in actions {
            actionsByID[action.actionID] = action
        }
        codeLogActions = actionsByID.values.sorted {
            if $0.levelNumber != $1.levelNumber {
                return $0.levelNumber > $1.levelNumber
            }
            return $0.actionID > $1.actionID
        }
    }

    private func resetCodeLog() {
        codeLogActions = []
        isCodeLogLoading = false
        codeLogStatusMessage = ""
        codeLogLoadedGameID = nil
    }

    private func liveActivityContentState() -> QueueActivityAttributes.ContentState? {
        guard selectedGameID != nil, let model = currentModel, let level = model.level else {
            return nil
        }
        guard model.isPlayable else { return nil }

        let display = settings.liveActivityDisplay

        let recentCodes: [String] = display.showCodes
            ? level.mixedActions
                .filter(\.isCorrect)
                .sorted { $0.actionID > $1.actionID }
                .prefix(QueueLiveActivityLayout.lockScreenMaxCodes)
                .map(\.answer)
            : []

        let hints: [String] = display.showHints
            ? (level.helps + level.penaltyHelps)
                .sorted { $0.number > $1.number }
                .compactMap { help -> String? in
                    guard let text = help.helpText?.strippingHTML(), !text.isEmpty else { return nil }
                    return String(text.prefix(140))
                }
                .prefix(1)
                .map { String($0) }
            : []

        let status = display.showStatus ? liveActivityStatus(for: level) : ""

        let syncedAt = liveActivityModelAnchor
        let levelEndsAt: Date? = level.timeoutSecondsRemain > 0
            ? syncedAt.addingTimeInterval(TimeInterval(level.timeoutSecondsRemain))
            : nil
        let nearestHintRemain = level.nearestLockedHintRemainSeconds
        let nextHintUnlocksAt: Date? = nearestHintRemain > 0
            ? syncedAt.addingTimeInterval(TimeInterval(nearestHintRemain))
            : nil

        return QueueActivityAttributes.ContentState(
            pendingCount: display.showQueue ? queue.pending.count : 0,
            status: status,
            isOnline: queueConnectionStatus == .ready,
            levelNumber: display.showLevel ? level.number : 0,
            levelName: display.showLevel ? level.name : "",
            teamName: display.showTeam ? model.teamName : "",
            sectorsPassed: display.showProgress ? level.passedSectorsCount : 0,
            sectorsRequired: display.showProgress ? level.requiredSectorsCount : 0,
            bonusesPassed: display.showProgress ? level.passedBonusesCount : 0,
            bonusesTotal: display.showProgress ? level.bonuses.count : 0,
            recentCodes: Array(recentCodes),
            hints: Array(hints),
            levelEndsAt: levelEndsAt,
            nextHintUnlocksAt: nextHintUnlocksAt
        )
    }

    private func liveActivityStatus(for level: Level) -> String {
        if !queue.pending.isEmpty {
            switch queueConnectionStatus {
            case .offline:
                return "В очереди \(queue.pending.count) · нет сети"
            case .serverUnreachable:
                return "В очереди \(queue.pending.count) · сервер недоступен"
            case .ready:
                return "В очереди \(queue.pending.count)"
            }
        }
        if let result = lastCodeResult {
            return result.message
        }
        if level.sectorsLeftToClose > 0 {
            return "Осталось секторов: \(level.sectorsLeftToClose)"
        }
        if level.requiredSectorsCount > 0 {
            return "Секторы \(level.passedSectorsCount)/\(level.requiredSectorsCount)"
        }
        if !level.bonuses.isEmpty {
            return "Бонусы \(level.passedBonusesCount)/\(level.bonuses.count)"
        }
        if level.timeoutSecondsRemain > 0 {
            return GameDurationFormatter.levelDrainLabel(seconds: level.timeoutSecondsRemain)
        }
        return queueConnectionStatus.label
    }

    func handleWidgetURL(_ url: URL) async {
        guard url.scheme?.lowercased() == "encx-cli" else { return }

        switch url.host?.lowercased() {
        case "game":
            if let gameID = selectedGameID {
                _ = await openGame(gameID, presentErrors: false)
            } else {
                selectedScreen = .games
            }
        case "flush-queue":
            if selectedGameID != nil {
                selectedScreen = .game
                _ = await flushQueueNow(silent: false)
            }
        case "codes":
            await openCodesFromWidget()
        default:
            if selectedGameID != nil {
                selectedScreen = .game
            }
        }
    }

    private func openCodesFromWidget() async {
        guard let gameID = selectedGameID else {
            selectedScreen = .games
            navigationPath.removeAll()
            return
        }

        selectedScreen = .game
        navigationPath.removeAll()

        if currentModel?.gameID != Int(gameID) || currentModel?.level == nil {
            _ = await openGame(gameID, presentErrors: false)
        }

        selectedScreen = .game
        navigationPath = [.codes]
    }

    private func syncWidgetSnapshot() {
        let loggedIn = hasStoredCredentials || loadSessionCookies() != nil
        guard loggedIn else {
            GameWidgetSnapshotStore.clear()
            return
        }

        guard selectedGameID != nil else {
            GameWidgetSnapshotStore.save(
                GameWidgetSnapshot(
                    updatedAt: Date(),
                    isLoggedIn: true,
                    hasActiveGame: false,
                    gameTitle: "",
                    levelNumber: 0,
                    levelName: "",
                    teamName: "",
                    sectorsPassed: 0,
                    sectorsRequired: 0,
                    bonusesPassed: 0,
                    bonusesTotal: 0,
                    pendingQueueCount: queue.pending.count,
                    isOnline: queue.isOnline,
                    status: "",
                    recentCodes: [],
                    hints: [],
                    levelEndsAt: nil,
                    nextHintUnlocksAt: nil
                )
            )
            return
        }

        guard let state = liveActivityContentState(), let model = currentModel else {
            let title = games.first { $0.id == selectedGameID.map(Int.init) }?.title ?? "Encounter"
            GameWidgetSnapshotStore.save(
                GameWidgetSnapshot(
                    updatedAt: Date(),
                    isLoggedIn: true,
                    hasActiveGame: false,
                    gameTitle: title,
                    levelNumber: 0,
                    levelName: "",
                    teamName: currentModel?.teamName ?? "",
                    sectorsPassed: 0,
                    sectorsRequired: 0,
                    bonusesPassed: 0,
                    bonusesTotal: 0,
                    pendingQueueCount: queue.pending.count,
                    isOnline: queueConnectionStatus == .ready,
                    status: statusMessage,
                    recentCodes: [],
                    hints: [],
                    levelEndsAt: nil,
                    nextHintUnlocksAt: nil
                )
            )
            return
        }

        let display = settings.liveActivityDisplay
        let rawTitle = model.gameTitle
            .isEmpty ? (games.first { $0.id == selectedGameID.map(Int.init) }?.title ?? "Encounter") : model.gameTitle
        let gameTitle = display.showGameTitle ? rawTitle : ""

        GameWidgetSnapshotStore.save(
            GameWidgetSnapshot(
                updatedAt: Date(),
                isLoggedIn: true,
                hasActiveGame: true,
                gameTitle: gameTitle,
                levelNumber: state.levelNumber,
                levelName: state.levelName,
                teamName: state.teamName,
                sectorsPassed: state.sectorsPassed,
                sectorsRequired: state.sectorsRequired,
                bonusesPassed: state.bonusesPassed,
                bonusesTotal: state.bonusesTotal,
                pendingQueueCount: state.pendingCount,
                isOnline: state.isOnline,
                status: state.status,
                recentCodes: state.recentCodes,
                hints: state.hints,
                levelEndsAt: state.levelEndsAt,
                nextHintUnlocksAt: state.nextHintUnlocksAt
            )
        )
    }

    private func markEngineReachable() {
        let wasUnreachable = !engineReachable
        engineReachable = true
        if wasUnreachable && !queue.pending.isEmpty {
            Task { _ = await flushQueueNow(silent: true) }
        }
    }

    private func markEngineUnreachable() {
        engineReachable = false
        serverRoundTripMs = nil
    }

    private func recordServerRoundTrip(since started: DispatchTime) {
        let nanos = DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds
        serverRoundTripMs = max(1, Int(nanos / 1_000_000))
    }

    private func submitGameEntry(gameID: Int64) async throws {
        do {
            let body = try await withSessionRecovery { try $0.submitGameApplication(gameID) }
            try saveCookies(from: try ensureClient())
            statusMessage = Self.applicationStatusMessage(from: body)
            try? await refreshGamesNow()
        } catch {
            let message = error.localizedDescription
            guard message.contains("404") else { throw error }
        }
    }

    private func ensureGameModerationLoaded(gameID: Int64) async {
        guard games.first(where: { $0.id == Int(gameID) }) == nil,
              moderationByGameID[Int(gameID)] == nil else { return }

        do {
            let stats = try await withSessionRecovery { try await $0.gameStatistics(gameID: gameID) }
            if let game = stats.game {
                moderationByGameID[Int(gameID)] = game.isModerated
            }
        } catch {
            // Keep the default (instant entry) when moderation metadata is unavailable.
        }
    }

    static func waitingStatusMessage(for model: GameModel?) -> String {
        guard let model, model.shouldShowEventStatus else { return "" }
        return EncounterClient.eventText(for: model.event)
    }

    private static func applicationStatusMessage(from body: String) -> String {
        let text = body.strippingHTML()
        if text.isEmpty {
            return "Заявка отправлена"
        }
        if text.count > 220 {
            return String(text.prefix(220)) + "…"
        }
        return text
    }

    private func refreshGamesNow() async throws {
        try await withSessionRecovery { client in
            let list = try client.gameList()
            games = list.activeGames + list.comingGames
            domainGames = (try? client.domainGames()) ?? []
            try saveCookies(from: client)
            statusMessage = games.isEmpty && domainGames.isEmpty ? "Игры не найдены" : "Игры загружены"
        }
    }

    private func refreshTeamNow(preferredTeamID: Int64? = nil) async throws {
        try await withSessionRecovery { client in
            async let invitationsResult = client.teamInvitations()
            async let htmlResult = client.myTeamDetailsHTML()

            let html = try await htmlResult
            let teams = try await client.teamLinks(from: html)
            let invitations = try await invitationsResult

            myTeams = teams
            teamInvitations = invitations

            let nextTeamID = preferredTeamID
                ?? selectedTeamID.flatMap { id in teams.contains { Int64($0.id) == id } ? id : nil }
                ?? teams.first.map { Int64($0.id) }
            selectedTeamID = nextTeamID

            if let nextTeamID {
                teamManagementInfo = try await client.teamManagementInfo(teamID: nextTeamID)
            } else {
                teamManagementInfo = nil
            }

            try saveCookies(from: client)
            if let nextTeamID {
                let name = currentTeamName.isEmpty ? "#\(nextTeamID)" : currentTeamName
                statusMessage = "Команда загружена: \(name)"
            } else if !invitations.isEmpty {
                statusMessage = "Есть приглашения в команду"
            } else {
                statusMessage = "Команда не найдена"
            }
        }
    }

    private func ensureClient() throws -> EncounterClient {
        if let client, client.settings == settings {
            return client
        }
        return try rebuildClient()
    }

    private func rebuildClient() throws -> EncounterClient {
        saveSettings()
        let newClient = try EncounterClient(settings: settings)
        if let cookies = loadSessionCookies() {
            try? newClient.importCookies(cookies)
        }
        client = newClient
        refreshHAREntryCount()
        return newClient
    }

    private func saveSettings() {
        EncounterSessionStore.saveSettings(settings)
    }

    private func saveCookies(from client: EncounterClient) throws {
        EncounterSessionStore.saveSessionCookies(try client.exportCookies())
    }

    private func loadSessionCookies() -> Data? {
        EncounterSessionStore.loadSessionCookies()
    }

    @discardableResult
    private func runBusy(
        _ message: String,
        showBusy: Bool = true,
        presentErrors: Bool = true,
        operation: () async throws -> Void
    ) async -> Bool {
        if showBusy {
            busyCounter += 1
            isBusy = busyCounter > 0
        }
        if !message.isEmpty {
            statusMessage = message
        }
        errorMessage = nil
        defer {
            if showBusy {
                busyCounter = max(0, busyCounter - 1)
                isBusy = busyCounter > 0
            }
        }

        do {
            try await operation()
            return true
        } catch {
            if presentErrors {
                presentError(error)
            }
            return false
        }
    }

    func presentError(_ error: Error) {
        if EncounterClient.isAntiSpamError(error) {
            antiSpamVerificationURL = EncounterClient.antiSpamURL(from: error, settings: settings)
                ?? EncounterClient.defaultAntiSpamURL(settings: settings)
            showAntiSpamVerification = true
        }
        let description = EncounterClient.userFacingDescription(for: error)
        if shouldSuppressErrorAlert(for: error) {
            statusMessage = description
            return
        }
        errorMessage = description
    }

    /// Catalog refresh can fail while the player is on a cached level screen; use status text instead of a modal.
    private func shouldSuppressErrorAlert(for error: Error) -> Bool {
        if EncounterClient.isAntiSpamError(error) || EncounterClient.isSessionExpiredError(error) {
            return false
        }
        guard selectedScreen == .game, currentModel != nil else { return false }
        return EncounterClient.isServerUnreachableError(error)
    }

    func dismissAntiSpamVerification() {
        showAntiSpamVerification = false
        antiSpamVerificationURL = nil
    }

    var sessionCookiesData: Data? {
        loadSessionCookies()
    }

    private func withSessionRecovery<T>(
        _ operation: (EncounterClient) async throws -> T
    ) async throws -> T {
        let client = try ensureClient()
        do {
            let result = try await operation(client)
            handleHARCaptureUpdate(client: client)
            return result
        } catch {
            handleHARCaptureUpdate(client: client)
            if EncounterClient.isAntiSpamError(error) {
                noteAntiSpam(error)
                throw error
            }
            guard EncounterClient.isSessionExpiredError(error) else { throw error }
            try await reloginSilently()
            let recoveredClient = try ensureClient()
            do {
                let result = try await operation(recoveredClient)
                handleHARCaptureUpdate(client: recoveredClient)
                return result
            } catch {
                handleHARCaptureUpdate(client: recoveredClient)
                if EncounterClient.isAntiSpamError(error) {
                    noteAntiSpam(error)
                }
                throw error
            }
        }
    }

    /// True while background polling is suspended by an active anti-spam backoff window.
    private var isAntiSpamBackoffActive: Bool {
        guard let antiSpamBackoffUntil else { return false }
        return Date() < antiSpamBackoffUntil
    }

    /// Records an anti-spam response: pauses background polling and surfaces the verification sheet once.
    private func noteAntiSpam(_ error: Error) {
        antiSpamBackoffUntil = Date().addingTimeInterval(antiSpamBackoffSeconds)
        guard !showAntiSpamVerification else { return }
        antiSpamVerificationURL = EncounterClient.antiSpamURL(from: error, settings: settings)
            ?? EncounterClient.defaultAntiSpamURL(settings: settings)
        showAntiSpamVerification = true
    }

    private func handleHARCaptureUpdate(client: EncounterClient) {
        scheduleHAREntryCountRefresh()
        scheduleHARUploadIfNeeded(client: client)
    }

    private func scheduleHAREntryCountRefresh() {
        guard settings.harCaptureEnabled else { return }
        harEntryCountRefreshTask?.cancel()
        harEntryCountRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            refreshHAREntryCount()
        }
    }

    private func scheduleHARUploadIfNeeded(client: EncounterClient) {
        guard settings.harUploadEnabled else { return }
        let entryCount = client.harEntryCount()
        guard entryCount > lastUploadedHAREntryCount else { return }
        harUploadTask?.cancel()
        harUploadTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                let uploadedCount = try await client.uploadHARSnapshot(login: login)
                guard uploadedCount > 0 else { return }
                lastUploadedHAREntryCount = 0
                refreshHAREntryCount()
                harUploadStatusMessage = "HAR отправлен: \(uploadedCount)"
            } catch {
                harUploadStatusMessage = "HAR не отправлен: \(error.localizedDescription)"
            }
        }
    }

    private func reloginSilently() async throws {
        if let reloginTask {
            try await reloginTask.value
            return
        }

        let task = Task<Void, Error> { @MainActor in
            try self.performRelogin()
        }
        reloginTask = task
        defer { reloginTask = nil }
        try await task.value
    }

    private func performRelogin() throws {
        let trimmedLogin = login.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLogin.isEmpty else { throw SessionRecoveryError.reloginRequired }
        guard let storedPassword = KeychainCredentialsStore.loadPassword(
            domain: settings.domain,
            login: trimmedLogin
        ) else {
            throw SessionRecoveryError.reloginRequired
        }

        let client = try rebuildClient()
        _ = try client.login(user: trimmedLogin, password: storedPassword)
        try saveCookies(from: client)
        try saveCredentials(password: storedPassword)
    }

    private func saveCredentials(password: String) throws {
        let trimmedLogin = login.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLogin.isEmpty, !password.isEmpty else { return }
        try KeychainCredentialsStore.save(
            password: password,
            domain: settings.domain,
            login: trimmedLogin
        )
    }

    private func queueAddedMessage(error: Error? = nil, engineUnreachable: Bool = false) -> String {
        let count = queue.pending.count
        if engineUnreachable {
            return "Движок недоступен. В очереди: \(count)"
        }
        if let error {
            if EncounterClient.isTimeoutError(error) {
                return "Нет ответа за 1 сек. В очереди: \(count)"
            }
            if EncounterClient.isSessionExpiredError(error) || error is SessionRecoveryError {
                return "Сессия истекла. В очереди: \(count)"
            }
            if EncounterClient.isAntiSpamError(error) {
                return "Антиспам. В очереди: \(count)"
            }
            return "Движок недоступен. В очереди: \(count)"
        }
        return "Нет сети. В очереди: \(count)"
    }

    func statisticsPageURL(for gameID: Int64) -> URL {
        let scheme = settings.useHTTP ? "http" : "https"
        return URL(string: "\(scheme)://\(settings.domain)/GameStat.aspx?gid=\(gameID)")!
    }

    func exportSessionCookies() async throws -> Data {
        try await withSessionRecovery { client in
            try client.exportCookies()
        }
    }

    private func feedback(from model: GameModel?) -> CodeResultFeedback? {
        guard let engineAction = model?.engineAction else { return nil }
        let result = [engineAction.levelAction, engineAction.bonusAction]
            .compactMap { $0 }
            .first { $0.answer != nil && $0.isCorrectAnswer != nil }
        guard let result, let answer = result.answer, let isCorrect = result.isCorrectAnswer else {
            return nil
        }
        let message = isCorrect ? "Код принят: \(answer)" : "Код не подошёл: \(answer)"
        return CodeResultFeedback(message: message, isCorrect: isCorrect, id: UUID())
    }

    private func resultMessage(from model: GameModel?) -> String {
        feedback(from: model)?.message ?? "Код отправлен"
    }
}
