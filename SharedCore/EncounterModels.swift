import Foundation
import UIKit

nonisolated enum GameEvent {
    static let normal = 0
    static let gameNotFound = 2
    static let engineMismatch = 3
    static let playerNotLoggedIn = 4
    static let gameNotStarted = 5
    static let gameFinished = 6
    static let playerNoApplication = 7
    static let teamNoApplication = 8
    static let playerNotAccepted = 9
    static let playerNoTeam = 10
    static let playerInactive = 11
    static let noLevels = 12
    static let teamLimitExceeded = 13
    static let levelDismissed16 = 16
    static let gameEnded = 17
    static let levelDismissed18 = 18
    static let levelAutoAdvance = 19
    static let allSectorsSolved = 20
    static let levelDismissed21 = 21
    static let levelTimeout = 22
}

nonisolated struct FlexString: Decodable, Hashable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = ""
            return
        }
        if let string = try? container.decode(String.self) {
            value = string
            return
        }
        if let number = try? container.decode(Int.self) {
            value = String(number)
            return
        }
        if let number = try? container.decode(Double.self) {
            value = String(number)
            return
        }
        if let flag = try? container.decode(Bool.self) {
            value = flag ? "true" : "false"
            return
        }
        struct AnswerObject: Decodable {
            let answer: String?
            let answ: String?

            enum CodingKeys: String, CodingKey {
                case answer = "Answer"
                case answ = "Answ"
            }
        }
        if let object = try? container.decode(AnswerObject.self) {
            value = object.answer ?? object.answ ?? ""
            return
        }
        value = ""
    }
}

nonisolated struct SyncedSecondsCountdown: Equatable {
    let remainSeconds: Int
    let syncedAt: Date

    func remainingSeconds(at date: Date = Date()) -> Int {
        let elapsed = max(0, Int(date.timeIntervalSince(syncedAt)))
        return max(0, remainSeconds - elapsed)
    }
}

nonisolated struct LoginResponse: Decodable {
    let error: Int
    let message: String
    let captchaURL: String?

    enum CodingKeys: String, CodingKey {
        case error = "Error"
        case message = "Message"
        case captchaURL = "CaptchaUrl"
    }
}

nonisolated struct UserProfile: Decodable {
    let id: Int
    let login: String
    let domain: String
    let location: String?

    enum CodingKeys: String, CodingKey {
        case id
        case login
        case domain
        case location
    }
}

nonisolated struct TeamInfo: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String

    enum CodingKeys: String, CodingKey {
        case id = "teamId"
        case name
    }
}

nonisolated struct TeamInvitation: Decodable, Identifiable, Hashable {
    let teamID: Int
    let name: String
    let action: String

    var id: Int { teamID }
    var displayName: String { name.isEmpty ? "#\(teamID)" : name }

    enum CodingKeys: String, CodingKey {
        case teamID = "team_id"
        case name
        case action
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        teamID = try container.decode(Int.self, forKey: .teamID)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        action = try container.decodeIfPresent(String.self, forKey: .action) ?? ""
    }
}

nonisolated struct TeamPendingInvitation: Decodable, Identifiable, Hashable {
    let userID: Int
    let login: String

    var id: Int { userID }
    var displayName: String { login.isEmpty ? "User #\(userID)" : login }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case login
    }
}

nonisolated struct TeamManagementInfo: Decodable, Hashable {
    let teamID: Int
    let teamName: String
    let pendingInvitations: [TeamPendingInvitation]
    let actions: [String: String]

    enum CodingKeys: String, CodingKey {
        case teamID = "team_id"
        case teamName = "team_name"
        case pendingInvitations = "pending_invitations"
        case actions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        teamID = try container.decode(Int.self, forKey: .teamID)
        teamName = try container.decodeIfPresent(String.self, forKey: .teamName) ?? ""
        pendingInvitations = try container.decodeIfPresent([TeamPendingInvitation].self, forKey: .pendingInvitations) ?? []
        actions = try container.decodeIfPresent([String: String].self, forKey: .actions) ?? [:]
    }

    var canManageTeam: Bool {
        actions.keys.contains { key in
            let normalizedKey = key.lowercased()
            return normalizedKey.contains("invite")
                || normalizedKey.contains("rename")
                || normalizedKey.contains("site")
                || normalizedKey.contains("forum")
                || normalizedKey.contains("manage")
                || normalizedKey.contains("edit")
        }
    }

    var canLeave: Bool {
        actions.keys.contains { key in
            key.contains("leave") || key.contains("quit") || key.contains("exit")
        }
    }
}

nonisolated struct DomainGame: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String

    enum CodingKeys: String, CodingKey {
        case id = "gameId"
        case title
    }
}

nonisolated struct GameListResponse: Decodable {
    let comingGames: [GameInfo]
    let activeGames: [GameInfo]

    enum CodingKeys: String, CodingKey {
        case comingGames = "ComingGames"
        case activeGames = "ActiveGames"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        comingGames = try container.decodeIfPresent([GameInfo].self, forKey: .comingGames) ?? []
        activeGames = try container.decodeIfPresent([GameInfo].self, forKey: .activeGames) ?? []
    }
}

nonisolated struct GameInfo: Decodable, Identifiable, Hashable {
    let id: Int
    let number: Int
    let title: String
    let description: String
    let started: Bool
    let finished: Bool
    let inProgress: Bool
    let isModerated: Bool
    let levelNumber: Int?

    enum CodingKeys: String, CodingKey {
        case id = "GameID"
        case number = "GameNum"
        case title = "Title"
        case description = "Descr"
        case started = "Started"
        case finished = "Finished"
        case inProgress = "InProgress"
        case isModerated = "IsModerated"
        case levelNumber = "LevelNumber"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        number = try container.decodeIfPresent(Int.self, forKey: .number) ?? 0
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        started = try container.decodeIfPresent(Bool.self, forKey: .started) ?? false
        finished = try container.decodeIfPresent(Bool.self, forKey: .finished) ?? false
        inProgress = try container.decodeIfPresent(Bool.self, forKey: .inProgress) ?? false
        isModerated = try container.decodeIfPresent(Bool.self, forKey: .isModerated) ?? false
        levelNumber = try container.decodeIfPresent(Int.self, forKey: .levelNumber)
    }

    /// Public game number for UI (`GameNum`), without locale-specific grouping.
    var displayNumberText: String {
        String(number > 0 ? number : id)
    }
}

nonisolated struct GameModel: Decodable {
    let event: Int
    let gameID: Int
    let gameTitle: String
    let gameDateTimeStart: Date?
    let login: String
    let teamName: String
    let finishPlace: Int?
    let levels: [LevelSummary]
    let level: Level?
    let engineAction: EngineAction?

    var isPlayable: Bool { event == GameEvent.normal }
    var isGameFinished: Bool { event == GameEvent.gameFinished }
    var isGameEnded: Bool { event == GameEvent.gameEnded }
    var isGameComplete: Bool { isGameFinished || isGameEnded }

    var startCountdown: SyncedSecondsCountdown? {
        guard level == nil,
              !isGameComplete,
              let gameDateTimeStart else {
            return nil
        }
        let now = Date()
        let remainSeconds = Int(ceil(gameDateTimeStart.timeIntervalSince(now)))
        guard remainSeconds > 0 else { return nil }
        return SyncedSecondsCountdown(remainSeconds: remainSeconds, syncedAt: now)
    }

    /// Player is in the game but the engine has not opened a level yet (normal event, no level payload).
    var isAwaitingLevelOpen: Bool {
        level == nil && event == GameEvent.normal && !isGameComplete
    }

    /// Non-transient event status that should be shown instead of a generic waiting message.
    var shouldShowEventStatus: Bool {
        guard level == nil, !isGameComplete else { return false }
        switch event {
        case GameEvent.normal, GameEvent.gameNotStarted, GameEvent.playerNotAccepted:
            return false
        default:
            return true
        }
    }

    enum CodingKeys: String, CodingKey {
        case event = "Event"
        case gameID = "GameId"
        case gameTitle = "GameTitle"
        case gameDateTimeStart = "GameDateTimeStart"
        case login = "Login"
        case teamName = "TeamName"
        case finishPlace = "FinishPlace"
        case levels = "Levels"
        case level = "Level"
        case engineAction = "EngineAction"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intEvent = try container.decodeIfPresent(Int.self, forKey: .event) {
            event = intEvent
        } else if let stringEvent = try container.decodeIfPresent(String.self, forKey: .event),
                  let parsed = Int(stringEvent) {
            event = parsed
        } else {
            event = GameEvent.normal
        }
        gameID = try container.decode(Int.self, forKey: .gameID)
        gameTitle = try container.decodeIfPresent(String.self, forKey: .gameTitle) ?? ""
        gameDateTimeStart = Self.decodeUnixDate(from: container, forKey: .gameDateTimeStart)
        login = try container.decodeIfPresent(String.self, forKey: .login) ?? ""
        teamName = try container.decodeIfPresent(String.self, forKey: .teamName) ?? ""
        finishPlace = Self.decodeFinishPlace(from: decoder)
        levels = try container.decodeIfPresent([LevelSummary].self, forKey: .levels) ?? []
        level = try container.decodeIfPresent(Level.self, forKey: .level)
        engineAction = try container.decodeIfPresent(EngineAction.self, forKey: .engineAction)
    }

    private static func decodeUnixDate(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Date? {
        if let value = try? container.decodeIfPresent(Int.self, forKey: key), value > 0 {
            return Date(timeIntervalSince1970: TimeInterval(value))
        }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key), value > 0 {
            return Date(timeIntervalSince1970: value)
        }
        if let string = try? container.decodeIfPresent(String.self, forKey: key),
           let value = TimeInterval(string.trimmingCharacters(in: .whitespacesAndNewlines)),
           value > 0 {
            return Date(timeIntervalSince1970: value)
        }
        return nil
    }

    private static func decodeFinishPlace(from decoder: Decoder) -> Int? {
        struct DynamicKey: CodingKey {
            let stringValue: String
            let intValue: Int? = nil

            init?(stringValue: String) {
                self.stringValue = stringValue
            }

            init?(intValue: Int) {
                return nil
            }
        }

        guard let container = try? decoder.container(keyedBy: DynamicKey.self) else { return nil }
        let possibleKeys = [
            "FinishPlace",
            "FinishedPlace",
            "TeamPlace",
            "Place",
            "Position",
            "Rank"
        ]
        for keyName in possibleKeys {
            guard let key = DynamicKey(stringValue: keyName) else { continue }
            if let value = try? container.decodeIfPresent(Int.self, forKey: key), value > 0 {
                return value
            }
            if let string = try? container.decodeIfPresent(String.self, forKey: key),
               let value = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)),
               value > 0 {
                return value
            }
        }
        return nil
    }
}

nonisolated struct LevelSummary: Decodable, Identifiable, Hashable {
    let levelID: Int
    let levelNumber: Int
    let levelName: String
    let dismissed: Bool
    let isPassed: Bool

    var id: Int { levelID }

    enum CodingKeys: String, CodingKey {
        case levelID = "LevelId"
        case levelNumber = "LevelNumber"
        case levelName = "LevelName"
        case dismissed = "Dismissed"
        case isPassed = "IsPassed"
    }
}

nonisolated struct Level: Decodable {
    let levelID: Int
    let number: Int
    let name: String
    let timeoutSecondsRemain: Int
    let isPassed: Bool
    let dismissed: Bool
    let hasAnswerBlockRule: Bool
    let blockDuration: Int
    let attemtsNumber: Int
    let attemtsPeriod: Int
    let requiredSectorsCount: Int
    let passedSectorsCount: Int
    let passedBonusesCount: Int
    let sectorsLeftToClose: Int
    let tasks: [LevelTask]
    let task: LevelTask?
    let messages: [AdminMessage]
    let sectors: [Sector]
    let helps: [Help]
    let bonuses: [Bonus]
    let penaltyHelps: [Help]
    let mixedActions: [CodeAction]

    enum CodingKeys: String, CodingKey {
        case levelID = "LevelId"
        case number = "Number"
        case name = "Name"
        case timeoutSecondsRemain = "TimeoutSecondsRemain"
        case isPassed = "IsPassed"
        case dismissed = "Dismissed"
        case hasAnswerBlockRule = "HasAnswerBlockRule"
        case blockDuration = "BlockDuration"
        case attemtsNumber = "AttemtsNumber"
        case attemtsPeriod = "AttemtsPeriod"
        case requiredSectorsCount = "RequiredSectorsCount"
        case passedSectorsCount = "PassedSectorsCount"
        case passedBonusesCount = "PassedBonusesCount"
        case sectorsLeftToClose = "SectorsLeftToClose"
        case tasks = "Tasks"
        case task = "Task"
        case messages = "Messages"
        case sectors = "Sectors"
        case helps = "Helps"
        case bonuses = "Bonuses"
        case penaltyHelps = "PenaltyHelps"
        case mixedActions = "MixedActions"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        levelID = try container.decode(Int.self, forKey: .levelID)
        number = try container.decode(Int.self, forKey: .number)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        timeoutSecondsRemain = try container.decodeIfPresent(Int.self, forKey: .timeoutSecondsRemain) ?? 0
        isPassed = try container.decodeIfPresent(Bool.self, forKey: .isPassed) ?? false
        dismissed = try container.decodeIfPresent(Bool.self, forKey: .dismissed) ?? false
        hasAnswerBlockRule = try container.decodeIfPresent(Bool.self, forKey: .hasAnswerBlockRule) ?? false
        blockDuration = try container.decodeIfPresent(Int.self, forKey: .blockDuration) ?? 0
        attemtsNumber = try container.decodeIfPresent(Int.self, forKey: .attemtsNumber) ?? 0
        attemtsPeriod = try container.decodeIfPresent(Int.self, forKey: .attemtsPeriod) ?? 0
        requiredSectorsCount = try container.decodeIfPresent(Int.self, forKey: .requiredSectorsCount) ?? 0
        passedSectorsCount = try container.decodeIfPresent(Int.self, forKey: .passedSectorsCount) ?? 0
        passedBonusesCount = try container.decodeIfPresent(Int.self, forKey: .passedBonusesCount) ?? 0
        sectorsLeftToClose = try container.decodeIfPresent(Int.self, forKey: .sectorsLeftToClose) ?? 0
        tasks = try container.decodeIfPresent([LevelTask].self, forKey: .tasks) ?? []
        task = try container.decodeIfPresent(LevelTask.self, forKey: .task)
        messages = try container.decodeIfPresent([AdminMessage].self, forKey: .messages) ?? []
        sectors = try container.decodeIfPresent([Sector].self, forKey: .sectors) ?? []
        helps = try container.decodeIfPresent([Help].self, forKey: .helps) ?? []
        bonuses = try container.decodeIfPresent([Bonus].self, forKey: .bonuses) ?? []
        penaltyHelps = try container.decodeIfPresent([Help].self, forKey: .penaltyHelps) ?? []
        mixedActions = try container.decodeIfPresent([CodeAction].self, forKey: .mixedActions) ?? []
    }

    /// Seconds until the nearest hint that is still locked (`RemainSeconds` > 0, no text yet).
    var nearestLockedHintRemainSeconds: Int {
        (helps + penaltyHelps)
            .filter { $0.remainSeconds > 0 && $0.unlockedText == nil }
            .map(\.remainSeconds)
            .min() ?? 0
    }
}

nonisolated struct LevelTask: Decodable, Hashable {
    let taskText: String
    let formattedText: String

    var displayText: String {
        (formattedText.isEmpty ? taskText : formattedText).strippingHTML()
    }

    enum CodingKeys: String, CodingKey {
        case taskText = "TaskText"
        case formattedText = "TaskTextFormatted"
    }
}

nonisolated struct AdminMessage: Decodable, Identifiable, Hashable {
    let messageID: Int
    let ownerLogin: String
    let messageText: String
    let wrappedText: String

    var id: Int { messageID }
    var displayText: String { (wrappedText.isEmpty ? messageText : wrappedText).strippingHTML() }

    enum CodingKeys: String, CodingKey {
        case messageID = "MessageId"
        case ownerLogin = "OwnerLogin"
        case messageText = "MessageText"
        case wrappedText = "WrappedText"
    }
}

nonisolated struct Sector: Decodable, Identifiable, Hashable {
    let sectorID: Int
    let order: Int
    let name: String
    let isAnswered: Bool
    let answer: String

    var id: Int { sectorID }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sectorID = try container.decode(Int.self, forKey: .sectorID)
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        isAnswered = try container.decodeIfPresent(Bool.self, forKey: .isAnswered) ?? false
        answer = try container.decodeIfPresent(FlexString.self, forKey: .answer)?.value ?? ""
    }

    /// Player-facing sector number (from «Сектор 18» in `name`). API `Order` is often closure sequence, not this index.
    var displayOrder: Int {
        Self.sectorNumber(from: name) ?? order
    }

    private static func sectorNumber(from name: String) -> Int? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let pattern = #"(?i)(?:сектор|sector)\s*(\d+)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: trimmed,
                  range: NSRange(trimmed.startIndex..., in: trimmed)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: trimmed)
        else { return nil }

        return Int(trimmed[range])
    }

    enum CodingKeys: String, CodingKey {
        case sectorID = "SectorId"
        case order = "Order"
        case name = "Name"
        case isAnswered = "IsAnswered"
        case answer = "Answer"
    }
}

extension Array where Element == Sector {
    var sortedForDisplay: [Sector] {
        sorted {
            if $0.displayOrder != $1.displayOrder {
                return $0.displayOrder < $1.displayOrder
            }
            return $0.sectorID < $1.sectorID
        }
    }
}

nonisolated struct Bonus: Decodable, Identifiable, Hashable {
    let bonusID: Int
    let name: String
    let number: Int
    let task: String
    let help: String
    let isAnswered: Bool
    let answer: String
    let expired: Bool
    let secondsToStart: Int
    let secondsLeft: Int
    let awardTime: Int
    let negative: Bool

    var id: Int { bonusID }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bonusID = try container.decode(Int.self, forKey: .bonusID)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        number = try container.decodeIfPresent(Int.self, forKey: .number) ?? 0
        task = try container.decodeIfPresent(String.self, forKey: .task) ?? ""
        help = try container.decodeIfPresent(String.self, forKey: .help) ?? ""
        isAnswered = try container.decodeIfPresent(Bool.self, forKey: .isAnswered) ?? false
        answer = try container.decodeIfPresent(FlexString.self, forKey: .answer)?.value ?? ""
        expired = try container.decodeIfPresent(Bool.self, forKey: .expired) ?? false
        secondsToStart = try container.decodeIfPresent(Int.self, forKey: .secondsToStart) ?? 0
        secondsLeft = try container.decodeIfPresent(Int.self, forKey: .secondsLeft) ?? 0
        awardTime = try container.decodeIfPresent(Int.self, forKey: .awardTime) ?? 0
        negative = try container.decodeIfPresent(Bool.self, forKey: .negative) ?? false
    }

    enum CodingKeys: String, CodingKey {
        case bonusID = "BonusId"
        case name = "Name"
        case number = "Number"
        case task = "Task"
        case help = "Help"
        case isAnswered = "IsAnswered"
        case answer = "Answer"
        case expired = "Expired"
        case secondsToStart = "SecondsToStart"
        case secondsLeft = "SecondsLeft"
        case awardTime = "AwardTime"
        case negative = "Negative"
    }
}

nonisolated struct Help: Decodable, Identifiable, Hashable {
    let helpID: Int
    let number: Int
    let helpText: String?
    let isPenalty: Bool
    let penalty: Int
    let requestConfirm: Bool
    let penaltyHelpState: Int
    let remainSeconds: Int
    let penaltyMessage: String?

    var id: Int { helpID }

    var unlockedText: String? {
        guard let text = helpText, !text.isEmpty else { return nil }
        let stripped = text.strippingHTML()
        guard !stripped.isEmpty, !Self.isUnlockPlaceholder(stripped) else { return nil }
        return text
    }

    var canRequestPenalty: Bool {
        isPenalty
            && penaltyHelpState != 2
            && remainSeconds <= 0
            && unlockedText == nil
    }

    static func isUnlockPlaceholder(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("откроется") && normalized.contains("через")
    }

    enum CodingKeys: String, CodingKey {
        case helpID = "HelpId"
        case number = "Number"
        case helpText = "HelpText"
        case isPenalty = "IsPenalty"
        case penalty = "Penalty"
        case requestConfirm = "RequestConfirm"
        case penaltyHelpState = "PenaltyHelpState"
        case remainSeconds = "RemainSeconds"
        case penaltyMessage = "PenaltyMessage"
    }
}

nonisolated struct CodeAction: Decodable, Identifiable, Hashable {
    let actionID: Int
    let levelNumber: Int
    let kind: Int
    let login: String
    let answer: String
    let isCorrect: Bool
    let locDateTime: String

    var id: Int { actionID }

    enum CodingKeys: String, CodingKey {
        case actionID = "ActionId"
        case levelNumber = "LevelNumber"
        case kind = "Kind"
        case login = "Login"
        case answer = "Answer"
        case isCorrect = "IsCorrect"
        case locDateTime = "LocDateTime"
    }
}

nonisolated struct EngineAction: Decodable {
    let levelAction: ActionResult?
    let bonusAction: ActionResult?

    enum CodingKeys: String, CodingKey {
        case levelAction = "LevelAction"
        case bonusAction = "BonusAction"
    }
}

nonisolated struct ActionResult: Decodable {
    let answer: String?
    let isCorrectAnswer: Bool?

    enum CodingKeys: String, CodingKey {
        case answer = "Answer"
        case isCorrectAnswer = "IsCorrectAnswer"
    }
}

nonisolated struct GameStatisticsResponse: Decodable {
    let game: GameInfo?
    let levels: [LevelStatInfo]
    let statItems: [[StatItem]]
    let levelPlayers: [LevelPlayerCount]
    let isLevelNamesVisible: Bool

    enum CodingKeys: String, CodingKey {
        case game = "Game"
        case levels = "Levels"
        case statItems = "StatItems"
        case levelPlayers = "LevelPlayers"
        case isLevelNamesVisible = "IsLevelNamesVisible"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        game = try container.decodeIfPresent(GameInfo.self, forKey: .game)
        levels = try container.decodeIfPresent([LevelStatInfo].self, forKey: .levels) ?? []
        statItems = try container.decodeIfPresent([[StatItem]].self, forKey: .statItems) ?? []
        levelPlayers = try container.decodeIfPresent([LevelPlayerCount].self, forKey: .levelPlayers) ?? []
        isLevelNamesVisible = try container.decodeIfPresent(Bool.self, forKey: .isLevelNamesVisible) ?? true
    }
}

nonisolated struct LevelStatInfo: Decodable, Identifiable, Hashable {
    let levelID: Int
    let levelNumber: Int
    let levelName: String
    let dismissed: Bool
    let passedPlayers: Int

    var id: Int { levelID }

    enum CodingKeys: String, CodingKey {
        case levelID = "LevelId"
        case levelNumber = "LevelNumber"
        case levelName = "LevelName"
        case dismissed = "Dismissed"
        case passedPlayers = "PassedPlayers"
    }
}

nonisolated struct LevelPlayerCount: Decodable, Hashable {
    let levelNum: Int
    let count: Int

    enum CodingKeys: String, CodingKey {
        case levelNum = "LevelNum"
        case count = "Count"
    }
}

nonisolated struct StatItem: Decodable, Identifiable, Hashable {
    let userName: String
    let teamName: String
    let levelNum: Int
    let spentSeconds: Int
    let scores: Int

    var id: String { "\(levelNum)-\(teamName)-\(userName)-\(spentSeconds)" }

    enum CodingKeys: String, CodingKey {
        case userName = "UserName"
        case teamName = "TeamName"
        case levelNum = "LevelNum"
        case spentSeconds = "SpentSeconds"
        case scores = "Scores"
    }
}

nonisolated enum SpentTimeFormatter {
    static func format(seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%dh%02dm%02ds", h, m, s)
        }
        return String(format: "%dm%02ds", m, s)
    }
}

extension String {
    nonisolated func removingHTMLScriptAndStyleBlocks() -> String {
        replacingOccurrences(
            of: #"(?is)<(script|style)\b[^>]*>.*?</\1>"#,
            with: " ",
            options: .regularExpression
        )
    }

    nonisolated func replacingNumericHTMLEntities() -> String {
        guard let regex = try? NSRegularExpression(pattern: "&#(\\d+);") else { return self }
        var result = self
        for match in regex.matches(in: self, range: NSRange(startIndex..., in: self)).reversed() {
            guard match.numberOfRanges >= 2,
                  let numberRange = Range(match.range(at: 1), in: self),
                  let code = Int(self[numberRange]),
                  let scalar = Unicode.Scalar(code),
                  let fullRange = Range(match.range, in: result) else { continue }
            result.replaceSubrange(fullRange, with: String(Character(scalar)))
        }
        return result
    }

    nonisolated func strippingHTML() -> String {
        var text = replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\r", with: "\n")
        text = text.removingHTMLScriptAndStyleBlocks()
        let lineBreakTags = #"(?i)<br\s*/?>|</p>|</div>|</li>|</tr>|</h[1-6]>"#
        text = text.replacingOccurrences(of: lineBreakTags, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingNumericHTMLEntities()
        text = text.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
