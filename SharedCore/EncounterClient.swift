import Foundation

#if canImport(Encx)
import Encx
#endif

nonisolated enum EncounterTimeouts {
    /// HTTP client timeout for login and game loads (0 = Go default 15s).
    static let httpSeconds: Int64 = 0
    /// Per-request timeout for code send and engine probes (enforced in Go via context).
    /// One second caused false failures on LTE even while the server was still processing the code.
    static let codeSendSeconds: Int64 = 3
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
    static let defaultHARUploadEndpoint = "https://enkapp-telemetry.exe.xyz/api/har"
    static let defaultHARRecordingEnabled = false
    static let defaultHARUploadEnabled = false

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
    var harRecordingEnabled = DomainSettings.defaultHARRecordingEnabled
    /// Tracks whether HAR recording was enabled implicitly by developer upload.
    var harRecordingAutoEnabledByUpload = false
    /// Sends captured HAR traffic to the developer diagnostics endpoint.
    var harUploadEnabled = DomainSettings.defaultHARUploadEnabled
    var harUploadEndpoint = DomainSettings.defaultHARUploadEndpoint

    var harCaptureEnabled: Bool {
        harRecordingEnabled || harUploadEnabled
    }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case domain
        case homeDomain
        case insecureTLS
        case useHTTP
        case liveActivityEnabled
        case liveActivityDisplay
        case pushOnNewLevel
        case pushOnNewHint
        case harRecordingEnabled
        case harRecordingAutoEnabledByUpload
        case harUploadEnabled
        case harUploadEndpoint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        domain = try container.decodeIfPresent(String.self, forKey: .domain) ?? Self.defaultDomain
        homeDomain = try container.decodeIfPresent(String.self, forKey: .homeDomain)
        insecureTLS = try container.decodeIfPresent(Bool.self, forKey: .insecureTLS) ?? false
        useHTTP = try container.decodeIfPresent(Bool.self, forKey: .useHTTP) ?? false
        liveActivityEnabled = try container.decodeIfPresent(Bool.self, forKey: .liveActivityEnabled) ?? true
        liveActivityDisplay = try container.decodeIfPresent(
            LiveActivityDisplayOptions.self,
            forKey: .liveActivityDisplay
        ) ?? LiveActivityDisplayOptions()
        pushOnNewLevel = try container.decodeIfPresent(Bool.self, forKey: .pushOnNewLevel) ?? true
        pushOnNewHint = try container.decodeIfPresent(Bool.self, forKey: .pushOnNewHint) ?? true
        harRecordingEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .harRecordingEnabled
        ) ?? Self.defaultHARRecordingEnabled
        harRecordingAutoEnabledByUpload = try container.decodeIfPresent(
            Bool.self,
            forKey: .harRecordingAutoEnabledByUpload
        ) ?? false
        harUploadEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .harUploadEnabled
        ) ?? Self.defaultHARUploadEnabled
        harUploadEndpoint = try container.decodeIfPresent(
            String.self,
            forKey: .harUploadEndpoint
        ) ?? Self.defaultHARUploadEndpoint
    }
}

nonisolated enum HARUploadError: LocalizedError {
    case invalidEndpoint
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Некорректный адрес сервера для HAR."
        case .httpStatus(let status):
            return "Сервер HAR вернул HTTP \(status)."
        }
    }
}

nonisolated enum HARRemoteUploader {
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func upload(
        harJSON: String,
        settings: DomainSettings,
        login: String,
        entryCount: Int? = nil
    ) async throws {
        guard settings.harUploadEnabled else { return }
        let endpoint = settings.harUploadEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: endpoint), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            throw HARUploadError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = Data(harJSON.utf8)
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(settings.domain, forHTTPHeaderField: "X-Enkapp-Domain")
        let trimmedLogin = login.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLogin.isEmpty {
            request.setValue(trimmedLogin, forHTTPHeaderField: "X-Enkapp-Login")
        }
        request.setValue(dateFormatter.string(from: Date()), forHTTPHeaderField: "X-Enkapp-Captured-At")
        if let entryCount {
            request.setValue(String(entryCount), forHTTPHeaderField: "X-Enkapp-HAR-Entry-Count")
        }
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            request.setValue(version, forHTTPHeaderField: "X-Enkapp-Version")
        }
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            request.setValue(build, forHTTPHeaderField: "X-Enkapp-Build")
        }

        let (_, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw HARUploadError.httpStatus(httpResponse.statusCode)
        }
    }
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
        client.setHARRecordingEnabled(settings.harCaptureEnabled)
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

    func exportHARSnapshot() throws -> (json: String, entryCount: Int) {
        #if canImport(Encx)
        let snapshot = try client.exportHARSnapshot()
        return (json: snapshot.json, entryCount: Int(snapshot.entryCount))
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func clearHARFirst(_ count: Int) {
        #if canImport(Encx)
        client.clearHARFirst(Int64(count))
        #endif
    }

    func uploadHARSnapshot(login: String) async throws -> Int {
        // Снимок и очистка по количеству атомарны на стороне Go: записи,
        // накопленные за время сетевой выгрузки, не стираются.
        let snapshot = try exportHARSnapshot()
        guard snapshot.entryCount > 0 else { return 0 }
        try await HARRemoteUploader.upload(
            harJSON: snapshot.json,
            settings: settings,
            login: login,
            entryCount: snapshot.entryCount
        )
        clearHARFirst(snapshot.entryCount)
        return snapshot.entryCount
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
        #if canImport(Encx)
        var error: NSError?
        let json: String
        switch submission.kind {
        case .level:
            json = client.sendCode(
                submission.gameID,
                levelID: submission.levelID,
                levelNumber: submission.levelNumber,
                code: submission.code,
                error: &error
            )
        case .bonus:
            json = client.sendBonusCode(
                submission.gameID,
                levelID: submission.levelID,
                levelNumber: submission.levelNumber,
                code: submission.code,
                error: &error
            )
        }
        if let error { throw error }
        return try decode(GameModel.self, from: json)
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func sendCode(_ submission: CodeSubmission) async throws -> GameModel {
        return try await Task.detached(priority: .userInitiated) {
            try self.sendCode(submission)
        }.value
    }

    func penaltyHint(gameID: Int64, penaltyID: Int64) throws -> GameModel {
        #if canImport(Encx)
        var error: NSError?
        let json = client.getPenaltyHint(gameID, penaltyID: penaltyID, error: &error)
        if let error { throw error }
        return try decode(GameModel.self, from: json)
        #else
        throw EncounterClientError.bindingsUnavailable
        #endif
    }

    func penaltyHint(gameID: Int64, penaltyID: Int64) async throws -> GameModel {
        try await Task.detached(priority: .userInitiated) {
            try self.penaltyHint(gameID: gameID, penaltyID: penaltyID)
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

    /// The server responded, but the payload didn't match the expected schema
    /// (e.g. tech.en.cx returns fractional AFC). Distinct from connectivity failures.
    static func isMalformedResponseError(_ error: Error) -> Bool {
        let message = (error as NSError).localizedDescription.lowercased()
        return message.contains("cannot unmarshal")
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
        let nsError = error as NSError
        #if canImport(Encx)
        if EncxmobileIsAntiSpamError(nsError) {
            return true
        }
        #endif

        let message = nsError.localizedDescription.lowercased()
        return message.contains("nothumanrequest")
            || message.contains("not human request")
            || message.contains("/nothumanrequest.aspx")
            || message.contains("anti-spam verification required")
            || message.contains("anti spam verification required")
            || (
                message.contains("requests have been classified")
                    && message.contains("robot")
            )
            || message.contains("запросы классифицированы как запросы робота")
    }

    static func antiSpamURL(from error: Error, settings: DomainSettings) -> URL? {
        guard isAntiSpamError(error) else { return nil }
        let nsError = error as NSError
        #if canImport(Encx)
        let frameworkURL = EncxmobileAntiSpamURLFromError(nsError)
        if !frameworkURL.isEmpty, let url = URL(string: frameworkURL) {
            return url
        }
        #endif

        let message = nsError.localizedDescription
        for scheme in ["https://", "http://"] {
            guard let range = message.range(of: scheme) else { continue }
            let tail = message[range.lowerBound...]
            let urlString = tail
                .split(whereSeparator: { $0.isWhitespace || $0 == "\"" || $0 == "'" || $0 == "<" })
                .first
                .map(String.init) ?? String(tail)
            guard urlString.localizedCaseInsensitiveContains("NotHumanRequest.aspx"),
                  let url = URL(string: urlString) else {
                continue
            }
            return url
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
        if isMalformedResponseError(error) {
            return "Сервер вернул данные в неожиданном формате. Проверьте, нет ли обновления приложения, и повторите позже."
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
