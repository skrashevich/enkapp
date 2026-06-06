import Foundation
import Observation

enum AppClipError: LocalizedError {
    case missingGameID
    case notLoggedIn
    case gameNotPlayable
    case emptyCode

    var errorDescription: String? {
        switch self {
        case .missingGameID:
            return "Укажите ID игры или откройте блиц-приложение по ссылке на игру."
        case .notLoggedIn:
            return "Войдите в Encounter, чтобы смотреть уровень и отправлять коды."
        case .gameNotPlayable:
            return "Сейчас нельзя отправлять коды в эту игру."
        case .emptyCode:
            return "Код не может быть пустым."
        }
    }
}

@Observable
@MainActor
final class AppClipViewModel {
    var settings = EncounterSessionStore.loadSettings()
    var login = EncounterSessionStore.loadLogin()
    var password = ""
    var gameIDText = ""
    var currentModel: GameModel?
    var statusMessage = ""
    var errorMessage: String?
    var isBusy = false

    let queue = CodeQueueStore.shared

    private var client: EncounterClient?

    init(invocation: AppClipInvocation = .fallback) {
        apply(invocation: invocation, loadImmediately: false)
    }

    var gameID: Int64? {
        Int64(gameIDText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var hasStoredSession: Bool {
        EncounterSessionStore.hasStoredSession(settings: settings, login: login)
    }

    var canSubmitCode: Bool {
        currentModel?.isPlayable == true && currentModel?.level != nil
    }

    var needsLogin: Bool {
        !hasStoredSession || currentModel?.event == GameEvent.playerNotLoggedIn
    }

    func apply(invocation: AppClipInvocation, loadImmediately: Bool = true) {
        settings.domain = invocation.domain
        if let gameID = invocation.gameID {
            gameIDText = String(gameID)
            EncounterSessionStore.saveSelectedGameID(gameID)
        }
        persistSessionHints()
        client = nil
        guard loadImmediately else { return }
        Task { await loadGame() }
    }

    func loadGame() async {
        guard let gameID else {
            errorMessage = AppClipError.missingGameID.localizedDescription
            return
        }

        await runBusy("Загрузка игры...") {
            currentModel = try await withSessionRecovery { try await $0.gameModel(gameID: gameID) }
            try saveCookies(from: try ensureClient())
            EncounterSessionStore.saveSelectedGameID(gameID)
            statusMessage = statusText(for: currentModel)
            if !queue.pending.isEmpty {
                await flushQueue(silent: true)
            }
        }
    }

    @discardableResult
    func loginAction() async -> Bool {
        await runBusy("Вход...") {
            persistSessionHints()
            let client = try rebuildClient()
            _ = try client.login(user: login, password: password)
            try saveCookies(from: client)
            try KeychainCredentialsStore.save(
                password: password,
                domain: settings.domain,
                login: login.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            password = ""
            currentModel = try await client.gameModel(gameID: try requireGameID())
            statusMessage = "Вход выполнен"
        }
    }

    func enterGame() async {
        await runBusy("Вход в игру...") {
            let gameID = try requireGameID()
            _ = try await withSessionRecovery { client in
                try client.submitGameApplication(gameID)
            }
            currentModel = try await withSessionRecovery { try await $0.gameModel(gameID: gameID) }
            try saveCookies(from: try ensureClient())
            statusMessage = statusText(for: currentModel)
        }
    }

    func submitCode(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = AppClipError.emptyCode.localizedDescription
            return
        }
        guard let model = currentModel, model.isPlayable, let level = model.level else {
            errorMessage = AppClipError.gameNotPlayable.localizedDescription
            return
        }
        if let message = Self.levelSubmissionBlockMessage(for: level) {
            statusMessage = message
            return
        }

        let submission = CodeSubmission(
            gameID: Int64(model.gameID),
            levelID: Int64(level.levelID),
            levelNumber: Int64(level.number),
            code: trimmed
        )

        guard queue.isOnline else {
            queue.enqueue(submission)
            statusMessage = queueAddedMessage()
            return
        }

        do {
            currentModel = try await withSessionRecovery { try await $0.sendCode(submission) }
            try saveCookies(from: try ensureClient())
            statusMessage = Self.resultMessage(from: currentModel)
        } catch {
            queue.enqueue(submission)
            statusMessage = queueAddedMessage(error: error)
        }
    }

    func flushQueue(silent: Bool = false) async {
        guard queue.isOnline else {
            if !silent { statusMessage = "Нет сети. В очереди: \(queue.pending.count)" }
            return
        }
        guard !queue.pending.isEmpty else {
            if !silent { statusMessage = "Очередь пуста" }
            return
        }

        await runBusy(silent ? "" : "Отправка очереди...", showBusy: !silent) {
            currentModel = try await queue.flush { submission in
                try await self.withSessionRecovery { try await $0.sendCode(submission) }
            } ?? currentModel
            try saveCookies(from: try ensureClient())
            statusMessage = queue.pending.isEmpty
                ? "Очередь отправлена"
                : "В очереди осталось: \(queue.pending.count)"
        }
    }

    private func requireGameID() throws -> Int64 {
        guard let gameID else { throw AppClipError.missingGameID }
        return gameID
    }

    private func persistSessionHints() {
        EncounterSessionStore.saveSettings(settings)
        EncounterSessionStore.saveLogin(login.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func ensureClient() throws -> EncounterClient {
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

    private func rebuildClient() throws -> EncounterClient {
        let newClient = try EncounterClient(settings: settings)
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
        let trimmedLogin = login.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLogin.isEmpty else { throw AppClipError.notLoggedIn }
        guard let password = KeychainCredentialsStore.loadPassword(domain: settings.domain, login: trimmedLogin) else {
            throw AppClipError.notLoggedIn
        }

        client = try EncounterClient(settings: settings)
        _ = try client!.login(user: trimmedLogin, password: password)
        try saveCookies(from: client!)
    }

    @discardableResult
    private func runBusy(
        _ message: String,
        showBusy: Bool = true,
        _ operation: () async throws -> Void
    ) async -> Bool {
        if showBusy {
            isBusy = true
            statusMessage = message
        }
        defer {
            if showBusy { isBusy = false }
        }
        do {
            try await operation()
            return true
        } catch {
            errorMessage = EncounterClient.userFacingDescription(for: error)
            return false
        }
    }

    private func statusText(for model: GameModel?) -> String {
        guard let model else { return "" }
        if model.isPlayable, model.level != nil {
            return "Уровень загружен"
        }
        return EncounterClient.eventText(for: model.event)
    }

    private func queueAddedMessage(error: Error? = nil) -> String {
        let count = queue.pending.count
        guard let error else { return "Нет сети. В очереди: \(count)" }
        if EncounterClient.isTimeoutError(error) {
            return "Нет ответа за 1 сек. В очереди: \(count)"
        }
        if EncounterClient.isAntiSpamError(error) {
            return "Антиспам. В очереди: \(count)"
        }
        if EncounterClient.isSessionExpiredError(error) {
            return "Сессия истекла. В очереди: \(count)"
        }
        return "Движок недоступен. В очереди: \(count)"
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
