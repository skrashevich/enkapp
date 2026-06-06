import Foundation

enum EncounterShortcutError: LocalizedError {
    case notLoggedIn
    case noActiveGame
    case noActiveTeam
    case gameNotPlayable
    case levelAnswerBlocked(String)
    case emptyCode
    case emptyTeamName
    case emptyPlayerLogin
    case invalidTeamID
    case invalidUserID
    case teamActionUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "Войдите в приложении, чтобы использовать автоматизации."
        case .noActiveGame:
            return "Откройте игру в приложении — автоматизации работают с активной игрой."
        case .noActiveTeam:
            return "Команда не выбрана. Откройте раздел команды в приложении."
        case .gameNotPlayable:
            return "Игра сейчас недоступна для отправки кодов."
        case .levelAnswerBlocked(let message):
            return message
        case .emptyCode:
            return "Код не может быть пустым."
        case .emptyTeamName:
            return "Название команды не может быть пустым."
        case .emptyPlayerLogin:
            return "Логин игрока не может быть пустым."
        case .invalidTeamID:
            return "ID команды должен быть больше нуля."
        case .invalidUserID:
            return "ID игрока должен быть больше нуля."
        case .teamActionUnavailable(let message):
            return message
        }
    }
}

struct EncounterGameStatusSummary: Equatable {
    let summary: String
    let gameTitle: String
    let levelNumber: Int
    let levelName: String
    let teamName: String
    let pendingQueueCount: Int
}

struct EncounterTeamStatusSummary: Equatable {
    let summary: String
    let teamID: Int64
    let teamName: String
    let teamsCount: Int
    let incomingInvitationsCount: Int
    let pendingInvitationsCount: Int
}

@MainActor
final class EncounterShortcutService {
    static let shared = EncounterShortcutService()

    private var client: EncounterClient?
    private var queue: CodeQueueStore { CodeQueueStore.shared }

    private init() {}

    func submitCode(_ text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EncounterShortcutError.emptyCode }

        let model = try await loadPlayableGameModel()
        guard let level = model.level else { throw EncounterShortcutError.gameNotPlayable }
        if let message = Self.levelSubmissionBlockMessage(for: level) {
            throw EncounterShortcutError.levelAnswerBlocked(message)
        }

        let submission = CodeSubmission(
            gameID: Int64(model.gameID),
            levelID: Int64(level.levelID),
            levelNumber: Int64(level.number),
            code: trimmed
        )

        guard queue.isOnline else {
            queue.enqueue(submission)
            BackgroundQueueService.shared.scheduleProcessing()
            return queueAddedMessage()
        }

        do {
            let updated = try await withSessionRecovery { try await $0.sendCode(submission) }
            try saveCookies(from: try ensureClient())
            BackgroundQueueService.shared.scheduleProcessing()
            return Self.resultMessage(from: updated)
        } catch {
            queue.enqueue(submission)
            BackgroundQueueService.shared.scheduleProcessing()
            return queueAddedMessage(error: error)
        }
    }

    func gameStatusSummary() async throws -> EncounterGameStatusSummary {
        let model = try await loadActiveGameModel()
        let level = model.level
        let pending = queue.pending.count

        var parts: [String] = [model.gameTitle]
        if !model.teamName.isEmpty {
            parts.append(model.teamName)
        }
        if let level {
            parts.append("Ур.\(level.number): \(level.name)")
            parts.append("Секторы \(level.passedSectorsCount)/\(level.requiredSectorsCount)")
        }
        if pending > 0 {
            parts.append("В очереди: \(pending)")
        }

        let summary = parts.joined(separator: " · ")
        return EncounterGameStatusSummary(
            summary: summary,
            gameTitle: model.gameTitle,
            levelNumber: level?.number ?? 0,
            levelName: level?.name ?? "",
            teamName: model.teamName,
            pendingQueueCount: pending
        )
    }

    func flushQueue() async throws -> String {
        guard queue.isOnline else {
            return "Нет сети. В очереди: \(queue.pending.count)"
        }
        guard !queue.pending.isEmpty else {
            return "Очередь пуста"
        }

        let updated = try await queue.flush { submission in
            try await withSessionRecovery { try await $0.sendCode(submission) }
        }
        try saveCookies(from: try ensureClient())
        if let updated {
            return Self.resultMessage(from: updated)
        }
        return "Отправлено из очереди. Осталось: \(queue.pending.count)"
    }

    func teamStatusSummary() async throws -> EncounterTeamStatusSummary {
        let snapshot = try await loadTeamSnapshot()
        var parts: [String] = []

        if let team = snapshot.team {
            let name = team.name.isEmpty ? "Команда #\(team.id)" : team.name
            parts.append(name)
        } else {
            parts.append("Команда не выбрана")
        }

        parts.append("Команд: \(snapshot.teams.count)")
        if !snapshot.invitations.isEmpty {
            parts.append("Входящие: \(snapshot.invitations.count)")
        }
        if let info = snapshot.info, !info.pendingInvitations.isEmpty {
            parts.append("Исходящие: \(info.pendingInvitations.count)")
        }

        return EncounterTeamStatusSummary(
            summary: parts.joined(separator: " · "),
            teamID: snapshot.teamID ?? 0,
            teamName: snapshot.team?.name ?? "",
            teamsCount: snapshot.teams.count,
            incomingInvitationsCount: snapshot.invitations.count,
            pendingInvitationsCount: snapshot.info?.pendingInvitations.count ?? 0
        )
    }

    func requestTeamMembership(_ teamName: String) async throws -> String {
        let trimmed = teamName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EncounterShortcutError.emptyTeamName }
        try await requireStoredSession()
        try await withSessionRecovery { try await $0.requestTeamMembership(teamName: trimmed) }
        try saveCookies(from: try ensureClient())
        return "Заявка в команду отправлена: \(trimmed)"
    }

    func acceptTeamInvitation(teamID: Int64) async throws -> String {
        guard teamID > 0 else { throw EncounterShortcutError.invalidTeamID }
        try await requireStoredSession()
        try await withSessionRecovery { try await $0.acceptTeamInvitation(teamID: teamID) }
        try saveCookies(from: try ensureClient())
        return "Приглашение принято: команда #\(teamID)"
    }

    func rejectTeamInvitation(teamID: Int64) async throws -> String {
        guard teamID > 0 else { throw EncounterShortcutError.invalidTeamID }
        try await requireStoredSession()
        try await withSessionRecovery { try await $0.rejectTeamInvitation(teamID: teamID) }
        try saveCookies(from: try ensureClient())
        return "Приглашение отклонено: команда #\(teamID)"
    }

    func inviteTeamMember(login: String) async throws -> String {
        let trimmed = login.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EncounterShortcutError.emptyPlayerLogin }
        let snapshot = try await loadTeamSnapshot()
        guard let teamID = snapshot.teamID else { throw EncounterShortcutError.noActiveTeam }

        try await withSessionRecovery {
            try await $0.inviteTeamMember(teamID: teamID, login: trimmed)
        }
        try saveCookies(from: try ensureClient())
        return "Приглашение отправлено игроку \(trimmed)"
    }

    func removeTeamInvitation(userID: Int64) async throws -> String {
        guard userID > 0 else { throw EncounterShortcutError.invalidUserID }
        let snapshot = try await loadTeamSnapshot()
        guard let teamID = snapshot.teamID else { throw EncounterShortcutError.noActiveTeam }

        try await withSessionRecovery {
            try await $0.removeTeamInvitation(teamID: teamID, userID: userID)
        }
        try saveCookies(from: try ensureClient())
        return "Приглашение игроку #\(userID) отозвано"
    }

    func leaveCurrentTeam() async throws -> String {
        let snapshot = try await loadTeamSnapshot()
        guard let teamID = snapshot.teamID else { throw EncounterShortcutError.noActiveTeam }
        if snapshot.info?.canLeave == false {
            throw EncounterShortcutError.teamActionUnavailable("Для этой команды выход недоступен.")
        }

        try await withSessionRecovery { try await $0.leaveTeam(teamID: teamID) }
        try saveCookies(from: try ensureClient())
        return "Вы вышли из команды"
    }

    func renameCurrentTeam(_ name: String) async throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EncounterShortcutError.emptyTeamName }
        let teamID = try await currentTeamID()

        try await withSessionRecovery { try await $0.renameTeam(teamID: teamID, name: trimmed) }
        try saveCookies(from: try ensureClient())
        return "Название команды обновлено: \(trimmed)"
    }

    func updateCurrentTeamSite(_ site: String) async throws -> String {
        let trimmed = site.trimmingCharacters(in: .whitespacesAndNewlines)
        let teamID = try await currentTeamID()

        try await withSessionRecovery { try await $0.setTeamSite(teamID: teamID, site: trimmed) }
        try saveCookies(from: try ensureClient())
        return trimmed.isEmpty ? "Сайт команды очищен" : "Сайт команды обновлён"
    }

    func updateCurrentTeamForum(_ forum: String) async throws -> String {
        let trimmed = forum.trimmingCharacters(in: .whitespacesAndNewlines)
        let teamID = try await currentTeamID()

        try await withSessionRecovery { try await $0.setTeamForum(teamID: teamID, forum: trimmed) }
        try saveCookies(from: try ensureClient())
        return trimmed.isEmpty ? "Форум команды очищен" : "Форум команды обновлён"
    }

    private func loadActiveGameModel() async throws -> GameModel {
        try await requireStoredSession()
        guard let gameID = EncounterSessionStore.loadSelectedGameID() else {
            throw EncounterShortcutError.noActiveGame
        }
        return try await withSessionRecovery { try await $0.gameModel(gameID: gameID) }
    }

    private func loadPlayableGameModel() async throws -> GameModel {
        let model = try await loadActiveGameModel()
        guard model.isPlayable, model.level != nil else {
            throw EncounterShortcutError.gameNotPlayable
        }
        return model
    }

    private func requireStoredSession() async throws {
        guard EncounterSessionStore.hasStoredSession(
            settings: EncounterSessionStore.loadSettings(),
            login: EncounterSessionStore.loadLogin()
        ) else {
            throw EncounterShortcutError.notLoggedIn
        }
    }

    private func currentTeamID() async throws -> Int64 {
        let snapshot = try await loadTeamSnapshot()
        guard let teamID = snapshot.teamID else { throw EncounterShortcutError.noActiveTeam }
        return teamID
    }

    private struct TeamSnapshot {
        let teams: [TeamInfo]
        let invitations: [TeamInvitation]
        let teamID: Int64?
        let team: TeamInfo?
        let info: TeamManagementInfo?
    }

    private func loadTeamSnapshot(preferredTeamID: Int64? = nil) async throws -> TeamSnapshot {
        try await requireStoredSession()
        return try await withSessionRecovery { client in
            async let invitationsResult = client.teamInvitations()
            async let htmlResult = client.myTeamDetailsHTML()

            let html = try await htmlResult
            let teams = try await client.teamLinks(from: html)
            let invitations = try await invitationsResult
            let teamID = preferredTeamID.flatMap { id in teams.contains { Int64($0.id) == id } ? id : nil }
                ?? teams.first.map { Int64($0.id) }
            let team = teamID.flatMap { id in teams.first { Int64($0.id) == id } }
            let info: TeamManagementInfo?
            if let teamID {
                info = try await client.teamManagementInfo(teamID: teamID)
            } else {
                info = nil
            }

            try saveCookies(from: client)
            return TeamSnapshot(
                teams: teams,
                invitations: invitations,
                teamID: teamID,
                team: team,
                info: info
            )
        }
    }

    private static func levelSubmissionBlockMessage(for level: Level) -> String? {
        if level.isPassed {
            return "Уровень уже пройден — ответы больше не отправляются."
        }
        if level.dismissed {
            return "Уровень снят — дождитесь следующего уровня."
        }
        if level.hasAnswerBlockRule, level.blockDuration > 0 {
            return "Ответы на уровень заблокированы ещё на \(level.blockDuration) сек."
        }
        return nil
    }

    private func ensureClient() throws -> EncounterClient {
        let settings = EncounterSessionStore.loadSettings()
        if let client, client.settings == settings {
            return client
        }
        let newClient = try EncounterClient(settings: settings)
        if let cookies = EncounterSessionStore.loadSessionCookies() {
            try? newClient.importCookies(cookies)
        }
        client = newClient
        return newClient
    }

    private func saveCookies(from client: EncounterClient) throws {
        EncounterSessionStore.saveSessionCookies(try client.exportCookies())
    }

    private func withSessionRecovery<T>(
        _ operation: (EncounterClient) async throws -> T
    ) async throws -> T {
        do {
            return try await operation(try ensureClient())
        } catch {
            guard EncounterClient.isSessionExpiredError(error) else { throw error }
            try performRelogin()
            return try await operation(try ensureClient())
        }
    }

    private func performRelogin() throws {
        let settings = EncounterSessionStore.loadSettings()
        let login = EncounterSessionStore.loadLogin().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !login.isEmpty else { throw EncounterShortcutError.notLoggedIn }
        guard let password = KeychainCredentialsStore.loadPassword(domain: settings.domain, login: login) else {
            throw EncounterShortcutError.notLoggedIn
        }

        client = try EncounterClient(settings: settings)
        _ = try client!.login(user: login, password: password)
        try saveCookies(from: client!)
    }

    private func queueAddedMessage(error: Error? = nil) -> String {
        let count = queue.pending.count
        if let error {
            if EncounterClient.isTimeoutError(error) {
                return "Нет ответа за 1 сек. В очереди: \(count)"
            }
            if EncounterClient.isSessionExpiredError(error) {
                return "Сессия истекла. В очереди: \(count)"
            }
            if EncounterClient.isAntiSpamError(error) {
                return "Антиспам. В очереди: \(count)"
            }
            return "Движок недоступен. В очереди: \(count)"
        }
        return "Нет сети. В очереди: \(count)"
    }

    static func resultMessage(from model: GameModel?) -> String {
        guard let engineAction = model?.engineAction else { return "Код отправлен" }
        let result = [engineAction.levelAction, engineAction.bonusAction]
            .compactMap { $0 }
            .first { $0.answer != nil && $0.isCorrectAnswer != nil }
        guard let result, let answer = result.answer, let isCorrect = result.isCorrectAnswer else {
            return "Код отправлен"
        }
        return isCorrect ? "Код принят: \(answer)" : "Код не подошёл: \(answer)"
    }
}
