import Foundation

#if canImport(Encx)
import Encx
#endif

nonisolated enum EncounterTimeouts {
    /// HTTP client timeout for login and game loads (0 = Go default 15s).
    static let httpSeconds: Int64 = 0
    /// Per-request timeout for code send and engine probes (enforced in Go via context).
    static let codeSendSeconds: Int64 = 1
}

enum EncounterClientError: LocalizedError {
    case bindingsUnavailable
    case clientCreationFailed
    case loginFailed(String)

    var errorDescription: String? {
        switch self {
        case .bindingsUnavailable:
            return "Encx.xcframework не подключен к target."
        case .clientCreationFailed:
            return "Не удалось создать Encounter-клиент."
        case .loginFailed(let message):
            return message
        }
    }
}

nonisolated struct LiveActivityDisplayOptions: Codable, Equatable {
    var showGameTitle = true
    var showLevel = true
    var showTeam = true
    var showProgress = true
    var showQueue = true
    var showCodes = true
    var showHints = true
    var showStatus = true
}

nonisolated struct DomainSettings: Codable, Equatable {
    /// Default Encounter host for development (public mock at https://encounter.exe.xyz).
    static let defaultDomain = "encounter.exe.xyz"

    var domain = DomainSettings.defaultDomain
    /// Player's home/registered Encounter domain (aka "прописка"), if known.
    var homeDomain: String?
    var insecureTLS = false
    var useHTTP = false
    var liveActivityEnabled = true
    var liveActivityDisplay = LiveActivityDisplayOptions()
    var pushOnNewLevel = true
    var pushOnNewHint = true
    /// Records Encounter HTTP traffic as HAR 1.2 for debugging and mock-server development.
    var harRecordingEnabled = false
}

nonisolated final class EncounterClient {
    private let decoder = JSONDecoder()

    #if canImport(Encx)
    private let client: EncxmobileEncClient
    #endif

    let settings: DomainSettings

    init(settings: DomainSettings) throws {
        self.settings = settings
        #if canImport(Encx)
        guard let client = EncxmobileNewClientWithOptions(
            settings.domain,
            settings.insecureTLS,
            settings.useHTTP,
            EncounterTimeouts.httpSeconds,
            "ru"
        ) else {
            throw EncounterClientError.clientCreationFailed
        }
        client.setCodeSendTimeoutSeconds(EncounterTimeouts.codeSendSeconds)
        client.setHARRecordingEnabled(settings.harRecordingEnabled)
        self.client = client
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func login(user: String, password: String) throws -> LoginResponse {
        #if canImport(Encx)
        var error: NSError?
        let json = client.login(user, password: password, error: &error)
        if let error { throw error }
        let response = try decode(LoginResponse.self, from: json)
        if response.error != 0 {
            throw EncounterClientError.loginFailed(response.message)
        }
        return response
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func exportCookies() throws -> Data {
        #if canImport(Encx)
        return try client.exportCookies()
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func importCookies(_ data: Data) throws {
        #if canImport(Encx)
        try client.importCookies(data)
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func setHARRecordingEnabled(_ enabled: Bool) {
        #if canImport(Encx)
        client.setHARRecordingEnabled(enabled)
        #endif
    }

    func harEntryCount() -> Int {
        #if canImport(Encx)
        return Int(client.harEntryCount())
        #else
        return 0
        #endif
    }

    func clearHAR() {
        #if canImport(Encx)
        client.clearHAR()
        #endif
    }

    func exportHAR() throws -> String {
        #if canImport(Encx)
        var error: NSError?
        let json = client.exportHAR(&error)
        if let error { throw error }
        return json
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func domainGames() throws -> [DomainGame] {
        #if canImport(Encx)
        var error: NSError?
        let json = client.getDomainGames(&error)
        if let error { throw error }
        return try decode([DomainGame].self, from: json)
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func profile() throws -> UserProfile {
        #if canImport(Encx)
        var error: NSError?
        let json = client.getProfile(&error)
        if let error { throw error }
        return try decode(UserProfile.self, from: json)
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func teamLinks(from html: String) throws -> [TeamInfo] {
        #if canImport(Encx)
        var error: NSError?
        let json = EncxmobileParseTeamLinks(html, &error)
        if let error { throw error }
        return try decode([TeamInfo].self, from: json)
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func myTeamDetailsHTML() throws -> String {
        #if canImport(Encx)
        var error: NSError?
        let html = client.getMyTeamDetails(&error)
        if let error { throw error }
        return html
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func teamManagementInfo(teamID: Int64) throws -> TeamManagementInfo {
        #if canImport(Encx)
        var error: NSError?
        let json = client.getTeamManagementInfo(teamID, error: &error)
        if let error { throw error }
        return try decode(TeamManagementInfo.self, from: json)
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func teamInvitations() throws -> [TeamInvitation] {
        #if canImport(Encx)
        var error: NSError?
        let json = client.getTeamInvitations(&error)
        if let error { throw error }
        return try decode([TeamInvitation].self, from: json)
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func acceptTeamInvitation(teamID: Int64) throws {
        #if canImport(Encx)
        try client.acceptTeamInvitation(teamID)
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func rejectTeamInvitation(teamID: Int64) throws {
        #if canImport(Encx)
        try client.rejectTeamInvitation(teamID)
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func requestTeamMembership(teamName: String) throws {
        #if canImport(Encx)
        try client.requestTeamMembership(teamName)
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func inviteTeamMember(teamID: Int64, login: String) throws {
        #if canImport(Encx)
        try client.inviteTeamMember(teamID, login: login)
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func removeTeamInvitation(teamID: Int64, userID: Int64) throws {
        #if canImport(Encx)
        try client.removeTeamInvitation(teamID, userID: userID)
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func leaveTeam(teamID: Int64) throws {
        #if canImport(Encx)
        try client.leaveTeam(teamID)
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func renameTeam(teamID: Int64, name: String) throws {
        #if canImport(Encx)
        try client.renameTeam(teamID, name: name)
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func setTeamSite(teamID: Int64, site: String) throws {
        #if canImport(Encx)
        try client.setTeamSite(teamID, site: site)
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func setTeamForum(teamID: Int64, forum: String) throws {
        #if canImport(Encx)
        try client.setTeamForum(teamID, forum: forum)
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func gameList(page: Int64 = 0) throws -> GameListResponse {
        #if canImport(Encx)
        var error: NSError?
        let json = client.getGameList(page, error: &error)
        if let error { throw error }
        return try decode(GameListResponse.self, from: json)
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    /// Submits a player application via encx EnterGame (MakeGameFee.aspx in Go).
    func submitGameApplication(_ gameID: Int64) throws -> String {
        #if canImport(Encx)
        var error: NSError?
        let response = client.enterGame(gameID, error: &error)
        if let error { throw error }
        return response
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func gameModel(gameID: Int64) throws -> GameModel {
        #if canImport(Encx)
        var error: NSError?
        let json = client.getGameModel(gameID, error: &error)
        if let error { throw error }
        return try decode(GameModel.self, from: json)
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func gameModelLevel(gameID: Int64, levelNumber: Int64) throws -> GameModel {
        #if canImport(Encx)
        var error: NSError?
        let json = client.getGameModelLevel(gameID, levelNumber: levelNumber, error: &error)
        if let error { throw error }
        return try decode(GameModel.self, from: json)
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func pingGame(gameID: Int64) throws -> GameModel {
        #if canImport(Encx)
        var error: NSError?
        let json = client.pingGame(gameID, error: &error)
        if let error { throw error }
        return try decode(GameModel.self, from: json)
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func sendCode(_ submission: CodeSubmission) throws -> GameModel {
        guard submission.kind == .level else {
            throw EncounterClientError.bindingsUnavailable
        }
        #if canImport(Encx)
        var error: NSError?
        let json = client.sendCode(
            submission.gameID,
            levelID: submission.levelID,
            levelNumber: submission.levelNumber,
            code: submission.code,
            error: &error
        )
        if let error { throw error }
        return try decode(GameModel.self, from: json)
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func sendCode(_ submission: CodeSubmission) async throws -> GameModel {
        if submission.kind == .bonus {
            return try await sendBonusCode(submission)
        }
        return try await Task.detached(priority: .userInitiated) {
            try self.sendCode(submission)
        }.value
    }

    func penaltyHint(gameID: Int64, penaltyID: Int64) throws -> GameModel {
        throw EncounterClientError.bindingsUnavailable
    }

    func penaltyHint(gameID: Int64, penaltyID: Int64) async throws -> GameModel {
        try await requestGameModel(
            gameID: gameID,
            method: "GET",
            queryItems: [
                URLQueryItem(name: "json", value: "1"),
                URLQueryItem(name: "pid", value: String(penaltyID)),
                URLQueryItem(name: "pact", value: "1"),
            ],
            formItems: nil,
            timeout: TimeInterval(max(EncounterTimeouts.httpSeconds, 15))
        )
    }

    private func sendBonusCode(_ submission: CodeSubmission) async throws -> GameModel {
        try await requestGameModel(
            gameID: submission.gameID,
            method: "POST",
            queryItems: [URLQueryItem(name: "json", value: "1")],
            formItems: [
                URLQueryItem(name: "LevelId", value: String(submission.levelID)),
                URLQueryItem(name: "LevelNumber", value: String(submission.levelNumber)),
                URLQueryItem(name: "BonusAction.Answer", value: submission.code),
            ],
            timeout: TimeInterval(EncounterTimeouts.codeSendSeconds)
        )
    }

    private struct ExportedCookie: Decodable {
        let name: String
        let value: String
    }

    private func requestGameModel(
        gameID: Int64,
        method: String,
        queryItems: [URLQueryItem],
        formItems: [URLQueryItem]?,
        timeout: TimeInterval
    ) async throws -> GameModel {
        var components = URLComponents()
        components.scheme = settings.useHTTP ? "http" : "https"
        components.host = settings.domain
        components.path = "/GameEngines/Encounter/Play/\(gameID)"
        components.queryItems = queryItems
        guard let url = components.url else {
            throw EncounterClientError.clientCreationFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue(try cookieHeader(), forHTTPHeaderField: "Cookie")

        if let formItems {
            var formComponents = URLComponents()
            formComponents.queryItems = formItems
            request.httpBody = formComponents.percentEncodedQuery?.data(using: .utf8)
            request.setValue(
                "application/x-www-form-urlencoded; charset=utf-8",
                forHTTPHeaderField: "Content-Type"
            )
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw NSError(
                domain: "EncounterClient",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"]
            )
        }
        guard let json = String(data: data, encoding: .utf8) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid UTF-8 JSON"))
        }
        return try decode(GameModel.self, from: json)
    }

    private func cookieHeader() throws -> String {
        let cookies = try decoder.decode([ExportedCookie].self, from: exportCookies())
        return cookies
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }

    func gameStatistics(gameID: Int64) throws -> GameStatisticsResponse {
        #if canImport(Encx)
        var error: NSError?
        let json = client.getGameStatistics(gameID, error: &error)
        if let error { throw error }
        return try decode(GameStatisticsResponse.self, from: json)
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func gameStatistics(gameID: Int64) async throws -> GameStatisticsResponse {
        try await Task.detached(priority: .userInitiated) {
            try self.gameStatistics(gameID: gameID)
        }.value
    }

    func teamLinks(from html: String) async throws -> [TeamInfo] {
        try await Task.detached(priority: .userInitiated) {
            try self.teamLinks(from: html)
        }.value
    }

    func myTeamDetailsHTML() async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try self.myTeamDetailsHTML()
        }.value
    }

    func teamManagementInfo(teamID: Int64) async throws -> TeamManagementInfo {
        try await Task.detached(priority: .userInitiated) {
            try self.teamManagementInfo(teamID: teamID)
        }.value
    }

    func teamInvitations() async throws -> [TeamInvitation] {
        try await Task.detached(priority: .userInitiated) {
            try self.teamInvitations()
        }.value
    }

    func acceptTeamInvitation(teamID: Int64) async throws {
        try await Task.detached(priority: .userInitiated) {
            try self.acceptTeamInvitation(teamID: teamID)
        }.value
    }

    func rejectTeamInvitation(teamID: Int64) async throws {
        try await Task.detached(priority: .userInitiated) {
            try self.rejectTeamInvitation(teamID: teamID)
        }.value
    }

    func requestTeamMembership(teamName: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            try self.requestTeamMembership(teamName: teamName)
        }.value
    }

    func inviteTeamMember(teamID: Int64, login: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            try self.inviteTeamMember(teamID: teamID, login: login)
        }.value
    }

    func removeTeamInvitation(teamID: Int64, userID: Int64) async throws {
        try await Task.detached(priority: .userInitiated) {
            try self.removeTeamInvitation(teamID: teamID, userID: userID)
        }.value
    }

    func leaveTeam(teamID: Int64) async throws {
        try await Task.detached(priority: .userInitiated) {
            try self.leaveTeam(teamID: teamID)
        }.value
    }

    func renameTeam(teamID: Int64, name: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            try self.renameTeam(teamID: teamID, name: name)
        }.value
    }

    func setTeamSite(teamID: Int64, site: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            try self.setTeamSite(teamID: teamID, site: site)
        }.value
    }

    func setTeamForum(teamID: Int64, forum: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            try self.setTeamForum(teamID: teamID, forum: forum)
        }.value
    }

    func gameModel(gameID: Int64) async throws -> GameModel {
        try await Task.detached(priority: .userInitiated) {
            try self.gameModel(gameID: gameID)
        }.value
    }

    func gameModelLevel(gameID: Int64, levelNumber: Int64) async throws -> GameModel {
        try await Task.detached(priority: .userInitiated) {
            try self.gameModelLevel(gameID: gameID, levelNumber: levelNumber)
        }.value
    }

    func pingGame(gameID: Int64) async throws -> GameModel {
        try await Task.detached(priority: .userInitiated) {
            try self.pingGame(gameID: gameID)
        }.value
    }

    /// Seconds until game start, or `-1` when the server provides no countdown.
    func timeoutToGame(gameID: Int64) throws -> Int64 {
        #if canImport(Encx)
        var seconds: Int64 = -1
        try client.getTimeoutToGame(gameID, ret0_: &seconds)
        return seconds
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func timeoutToGame(gameID: Int64) async throws -> Int64 {
        try await Task.detached(priority: .userInitiated) {
            try self.timeoutToGame(gameID: gameID)
        }.value
    }

    static func isTimeoutError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorTimedOut {
            return true
        }
        let message = ns.localizedDescription.lowercased()
        return message.contains("deadline") || message.contains("timeout") || message.contains("timed out")
    }

    static func isSessionExpiredError(_ error: Error) -> Bool {
        let message = (error as NSError).localizedDescription.lowercased()
        return message.contains("session expired") || message.contains("html instead of json")
    }

    static func isServerUnreachableError(_ error: Error) -> Bool {
        if isTimeoutError(error) {
            return true
        }
        let message = (error as NSError).localizedDescription.lowercased()
        return message.contains("empty response")
            || message.contains("eof")
            || message.contains("unexpected end of json")
            || message.contains("decode game model")
            || message.contains("decode game list")
            || message.contains("connection refused")
            || message.contains("network connection was lost")
            || message.contains("could not connect")
            || message.contains("cannot connect")
            || message.contains("server unreachable")
    }

    static func isAntiSpamError(_ error: Error) -> Bool {
        let message = (error as NSError).localizedDescription.lowercased()
        return message.contains("anti-spam") || message.contains("nothumanrequest")
    }

    static func antiSpamURL(from error: Error, settings: DomainSettings) -> URL? {
        guard isAntiSpamError(error) else { return nil }
        let message = (error as NSError).localizedDescription
        if let range = message.range(of: "https://") ?? message.range(of: "http://") {
            let tail = message[range.lowerBound...]
            let urlString = tail.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? String(tail)
            if let url = URL(string: urlString) {
                return url
            }
        }
        return defaultAntiSpamURL(settings: settings)
    }

    static func defaultAntiSpamURL(settings: DomainSettings) -> URL {
        let scheme = settings.useHTTP ? "http" : "https"
        var components = URLComponents()
        components.scheme = scheme
        components.host = settings.domain
        components.path = "/NotHumanRequest.aspx"
        components.queryItems = [URLQueryItem(name: "return", value: "/")]
        return components.url!
    }

    static func userFacingDescription(for error: Error) -> String {
        if isAntiSpamError(error) {
            return "Сработала антиспам-защита. Пройдите проверку на сайте и повторите действие."
        }
        if isSessionExpiredError(error) {
            return "Сессия истекла. Войдите снова в настройках."
        }
        if isServerUnreachableError(error) {
            return "Сервер недоступен. Повторите позже."
        }
        return error.localizedDescription
    }

    static func eventText(for code: Int) -> String {
        #if canImport(Encx)
        return EncxmobileEventText(Int64(code))
        #else
        switch code {
        case GameEvent.normal: return "Игра в процессе"
        case GameEvent.gameNotFound: return "Игра с таким ID не существует"
        case GameEvent.engineMismatch: return "Игра не соответствует движку"
        case GameEvent.playerNotLoggedIn: return "Игрок не авторизован"
        case GameEvent.gameNotStarted: return "Игра ещё не началась"
        case GameEvent.gameFinished: return "Игра завершена"
        case GameEvent.playerNoApplication: return "Заявка игрока не подана"
        case GameEvent.teamNoApplication: return "Заявка команды не подана"
        case GameEvent.playerNotAccepted: return "Заявка игрока ещё не принята"
        case GameEvent.playerNoTeam: return "Игрок не состоит в команде"
        case GameEvent.playerInactive: return "Игрок неактивен в команде"
        case GameEvent.noLevels: return "В игре нет уровней"
        case GameEvent.teamLimitExceeded: return "Превышен лимит участников в команде"
        case GameEvent.levelDismissed16, GameEvent.levelDismissed18, GameEvent.levelDismissed21:
            return "Уровень снят — запросите заново"
        case GameEvent.gameEnded: return "Игра окончена"
        case GameEvent.levelAutoAdvance: return "Уровень пройден по автопереходу"
        case GameEvent.allSectorsSolved: return "Все сектора разгаданы"
        case GameEvent.levelTimeout: return "Таймаут уровня"
        default: return "Неизвестный статус"
        }
        #endif
    }

    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        guard let data = json.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid UTF-8 JSON"))
        }
        return try decoder.decode(T.self, from: data)
    }
}
