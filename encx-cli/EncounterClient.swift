import Foundation

#if canImport(Encx)
import Encx
#endif

enum EncounterTimeouts {
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

struct LiveActivityDisplayOptions: Codable, Equatable {
    var showGameTitle = true
    var showLevel = true
    var showTeam = true
    var showProgress = true
    var showQueue = true
    var showCodes = true
    var showHints = true
    var showStatus = true
}

struct DomainSettings: Codable, Equatable {
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

final class EncounterClient {
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
        try await Task.detached(priority: .userInitiated) {
            try self.sendCode(submission)
        }.value
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

    func gameModel(gameID: Int64) async throws -> GameModel {
        try await Task.detached(priority: .userInitiated) {
            try self.gameModel(gameID: gameID)
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
        case GameEvent.gameFinished: return "Игра завершена"
        case GameEvent.gameEnded: return "Игра окончена"
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
