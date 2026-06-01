import ActivityKit
import Foundation

enum QueueLiveActivityLayout {
    /// Lock Screen Live Activities are truncated above ~160 pt (ActivityKit).
    static let lockScreenMaxCodes = 2
    static let lockScreenMaxHintLines = 2
    static let dynamicIslandMaxCodes = 3
}

struct QueueActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var pendingCount: Int
        var status: String
        var isOnline: Bool
        var levelNumber: Int
        var levelName: String
        var teamName: String
        var sectorsPassed: Int
        var sectorsRequired: Int
        var bonusesPassed: Int
        var bonusesTotal: Int
        var recentCodes: [String]
        var hints: [String]
    }

    var gameTitle: String
}

extension QueueActivityAttributes.ContentState {
    static let preview = QueueActivityAttributes.ContentState(
        pendingCount: 2,
        status: "Ожидание отправки…",
        isOnline: true,
        levelNumber: 7,
        levelName: "Тайна старого дома",
        teamName: "Команда А",
        sectorsPassed: 2,
        sectorsRequired: 5,
        bonusesPassed: 1,
        bonusesTotal: 3,
        recentCodes: ["ответ1", "сектор2", "бонус"],
        hints: ["Посмотрите на табличку у входа", "Код спрятан в координатах"]
    )

    var levelTitle: String {
        guard levelNumber > 0 else { return "" }
        if levelName.isEmpty {
            return "Уровень \(levelNumber)"
        }
        return "Ур. \(levelNumber): \(levelName)"
    }

    var hasLevelHeader: Bool {
        levelNumber > 0
    }

    /// Single subtitle line for lock-screen Live Activity (saves vertical space).
    var lockScreenSubtitle: String {
        var parts: [String] = []
        if hasLevelHeader {
            parts.append(levelTitle)
        }
        if !teamName.isEmpty {
            parts.append(teamName)
        }
        return parts.joined(separator: " · ")
    }

    var sectorsSummary: String {
        guard sectorsRequired > 0 else { return "" }
        return "Секторы \(sectorsPassed)/\(sectorsRequired)"
    }

    var bonusesSummary: String {
        guard bonusesTotal > 0 else { return "" }
        return "Бонусы \(bonusesPassed)/\(bonusesTotal)"
    }

    var lastCode: String? {
        recentCodes.last
    }
}
