import Foundation
import WidgetKit

enum GameWidgetSnapshotStore {
    static let appGroupID = "group.com.svk-team.encx-cli"
    static let snapshotKey = "encx.widget.snapshot"
    static let widgetKind = "GameHomeScreenWidget"

    private static var isRunningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private static let snapshotURL: URL? = {
        guard !isRunningInPreview else { return nil }
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            return nil
        }
        let directory = containerURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("GameWidgetSnapshotStore", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent("snapshot.json")
    }()

    static func load() -> GameWidgetSnapshot? {
        guard let snapshotURL,
              let data = try? Data(contentsOf: snapshotURL),
              let decoded = try? JSONDecoder().decode(GameWidgetSnapshot.self, from: data) else {
            return nil
        }
        return decoded
    }

    static func save(_ snapshot: GameWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot),
              let snapshotURL else {
            return
        }
        try? data.write(to: snapshotURL, options: .atomic)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    static func clear() {
        if let snapshotURL {
            try? FileManager.default.removeItem(at: snapshotURL)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}

struct GameWidgetSnapshot: Codable, Equatable {
    var updatedAt: Date
    var isLoggedIn: Bool
    var hasActiveGame: Bool
    var gameTitle: String
    var levelNumber: Int
    var levelName: String
    var teamName: String
    var sectorsPassed: Int
    var sectorsRequired: Int
    var bonusesPassed: Int
    var bonusesTotal: Int
    var pendingQueueCount: Int
    var isOnline: Bool
    var status: String
    var recentCodes: [String]
    var hints: [String]
    var levelEndsAt: Date?
    var nextHintUnlocksAt: Date?

    static let loggedOut = GameWidgetSnapshot(
        updatedAt: .distantPast,
        isLoggedIn: false,
        hasActiveGame: false,
        gameTitle: "",
        levelNumber: 0,
        levelName: "",
        teamName: "",
        sectorsPassed: 0,
        sectorsRequired: 0,
        bonusesPassed: 0,
        bonusesTotal: 0,
        pendingQueueCount: 0,
        isOnline: false,
        status: "",
        recentCodes: [],
        hints: [],
        levelEndsAt: nil,
        nextHintUnlocksAt: nil
    )

    var levelTitle: String {
        guard levelNumber > 0 else { return "" }
        if levelName.isEmpty {
            return "Уровень \(levelNumber)"
        }
        return "Ур. \(levelNumber): \(levelName)"
    }

    var sectorsSummary: String {
        guard sectorsRequired > 0 else { return "" }
        return "Секторы \(sectorsPassed)/\(sectorsRequired)"
    }

    var sectorProgress: Double {
        guard sectorsRequired > 0 else { return 0 }
        return Double(sectorsPassed) / Double(sectorsRequired)
    }

    var placeholderMessage: String {
        if !isLoggedIn {
            return "Войдите в enkapp, чтобы видеть игру на рабочем столе."
        }
        if !hasActiveGame {
            return "Откройте игру в enkapp — виджет покажет уровень и прогресс."
        }
        return ""
    }

    var nextRefreshDate: Date {
        let now = Date()
        var candidates: [Date] = [updatedAt.addingTimeInterval(15 * 60)]
        if let levelEndsAt, levelEndsAt > now {
            candidates.append(levelEndsAt)
        }
        if let nextHintUnlocksAt, nextHintUnlocksAt > now {
            candidates.append(nextHintUnlocksAt)
        }
        return candidates.min() ?? now.addingTimeInterval(15 * 60)
    }

    static let previewActiveGame = GameWidgetSnapshot(
        updatedAt: Date(),
        isLoggedIn: true,
        hasActiveGame: true,
        gameTitle: "Ночной город",
        levelNumber: 7,
        levelName: "Тайна старого дома",
        teamName: "Команда А",
        sectorsPassed: 2,
        sectorsRequired: 5,
        bonusesPassed: 1,
        bonusesTotal: 3,
        pendingQueueCount: 2,
        isOnline: true,
        status: "В очереди 2",
        recentCodes: ["ответ1", "сектор2"],
        hints: ["Посмотрите на табличку у входа"],
        levelEndsAt: Date().addingTimeInterval(42 * 60),
        nextHintUnlocksAt: Date().addingTimeInterval(7 * 60)
    )
}
