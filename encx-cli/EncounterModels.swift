import Foundation
import UIKit

struct SyncedSecondsCountdown: Equatable {
    let remainSeconds: Int
    let syncedAt: Date
}

struct LoginResponse: Decodable {
    let error: Int
    let message: String
    let captchaURL: String?

    enum CodingKeys: String, CodingKey {
        case error = "Error"
        case message = "Message"
        case captchaURL = "CaptchaUrl"
    }
}

struct UserProfile: Decodable {
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

struct DomainGame: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String

    enum CodingKeys: String, CodingKey {
        case id = "gameId"
        case title
    }
}

struct GameListResponse: Decodable {
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

struct GameInfo: Decodable, Identifiable, Hashable {
    let id: Int
    let number: Int
    let title: String
    let description: String
    let started: Bool
    let finished: Bool
    let inProgress: Bool
    let levelNumber: Int?

    enum CodingKeys: String, CodingKey {
        case id = "GameID"
        case number = "GameNum"
        case title = "Title"
        case description = "Descr"
        case started = "Started"
        case finished = "Finished"
        case inProgress = "InProgress"
        case levelNumber = "LevelNumber"
    }
}

struct GameModel: Decodable {
    let gameID: Int
    let gameTitle: String
    let login: String
    let teamName: String
    let levels: [LevelSummary]
    let level: Level?
    let engineAction: EngineAction?

    enum CodingKeys: String, CodingKey {
        case gameID = "GameId"
        case gameTitle = "GameTitle"
        case login = "Login"
        case teamName = "TeamName"
        case levels = "Levels"
        case level = "Level"
        case engineAction = "EngineAction"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gameID = try container.decode(Int.self, forKey: .gameID)
        gameTitle = try container.decodeIfPresent(String.self, forKey: .gameTitle) ?? ""
        login = try container.decodeIfPresent(String.self, forKey: .login) ?? ""
        teamName = try container.decodeIfPresent(String.self, forKey: .teamName) ?? ""
        levels = try container.decodeIfPresent([LevelSummary].self, forKey: .levels) ?? []
        level = try container.decodeIfPresent(Level.self, forKey: .level)
        engineAction = try container.decodeIfPresent(EngineAction.self, forKey: .engineAction)
    }
}

struct LevelSummary: Decodable, Identifiable, Hashable {
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

struct Level: Decodable {
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
}

struct LevelTask: Decodable, Hashable {
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

struct AdminMessage: Decodable, Identifiable, Hashable {
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

struct Sector: Decodable, Identifiable, Hashable {
    let sectorID: Int
    let order: Int
    let name: String
    let isAnswered: Bool
    let answer: String

    var id: Int { sectorID }

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

struct Bonus: Decodable, Identifiable, Hashable {
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

struct Help: Decodable, Identifiable, Hashable {
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

struct CodeAction: Decodable, Identifiable, Hashable {
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

struct EngineAction: Decodable {
    let levelAction: ActionResult?
    let bonusAction: ActionResult?

    enum CodingKeys: String, CodingKey {
        case levelAction = "LevelAction"
        case bonusAction = "BonusAction"
    }
}

struct ActionResult: Decodable {
    let answer: String?
    let isCorrectAnswer: Bool?

    enum CodingKeys: String, CodingKey {
        case answer = "Answer"
        case isCorrectAnswer = "IsCorrectAnswer"
    }
}

struct GameStatisticsResponse: Decodable {
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

struct LevelStatInfo: Decodable, Identifiable, Hashable {
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

struct LevelPlayerCount: Decodable, Hashable {
    let levelNum: Int
    let count: Int

    enum CodingKeys: String, CodingKey {
        case levelNum = "LevelNum"
        case count = "Count"
    }
}

struct StatItem: Decodable, Identifiable, Hashable {
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

enum SpentTimeFormatter {
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
    func strippingHTML() -> String {
        var text = replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\r", with: "\n")
        let lineBreakTags = #"(?i)<br\s*/?>|</p>|</div>|</li>|</tr>|</h[1-6]>"#
        text = text.replacingOccurrences(of: lineBreakTags, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
