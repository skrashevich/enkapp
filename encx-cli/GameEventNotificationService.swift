import Foundation
import UserNotifications

@MainActor
final class GameEventNotificationService {
    static let shared = GameEventNotificationService()

    private let snapshotsKey = "encx.gameEventSnapshots"

    private struct Snapshot: Codable, Equatable {
        var levelID: Int
        var levelNumber: Int
        var visibleHintIDs: [Int]
    }

    private init() {}

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default:
            return false
        }
    }

    func processModelUpdate(
        gameID: Int64,
        gameTitle: String,
        model: GameModel,
        notifyNewLevel: Bool,
        notifyNewHint: Bool
    ) async {
        guard notifyNewLevel || notifyNewHint else { return }
        guard await requestAuthorizationIfNeeded() else { return }
        guard let level = model.level else { return }

        let currentHintIDs = Self.visibleHintIDs(in: level)
        let previous = loadSnapshot(gameID: gameID)

        if let previous {
            if notifyNewLevel, level.levelID != previous.levelID {
                await post(
                    identifier: "level-\(gameID)-\(level.levelID)",
                    title: gameTitle.isEmpty ? "Новый уровень" : gameTitle,
                    body: Self.levelTitle(level)
                )
            }

            if notifyNewHint, level.levelID == previous.levelID {
                let previousSet = Set(previous.visibleHintIDs)
                for help in Self.visibleHints(in: level) where !previousSet.contains(help.helpID) {
                    let text = help.helpText?.strippingHTML() ?? ""
                    await post(
                        identifier: "hint-\(gameID)-\(level.levelID)-\(help.helpID)",
                        title: "Подсказка \(help.number) · \(Self.levelTitle(level))",
                        body: String(text.prefix(220))
                    )
                }
            }
        }

        saveSnapshot(
            gameID: gameID,
            Snapshot(
                levelID: level.levelID,
                levelNumber: level.number,
                visibleHintIDs: currentHintIDs
            )
        )
    }

    func clearSnapshot(gameID: Int64) {
        var snapshots = loadAllSnapshots()
        snapshots.removeValue(forKey: String(gameID))
        persistSnapshots(snapshots)
    }

    private func post(identifier: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func visibleHints(in level: Level) -> [Help] {
        (level.helps + level.penaltyHelps).filter { help in
            guard let text = help.helpText?.strippingHTML(), !text.isEmpty else { return false }
            return true
        }
    }

    private static func visibleHintIDs(in level: Level) -> [Int] {
        visibleHints(in: level).map(\.helpID)
    }

    private static func levelTitle(_ level: Level) -> String {
        if level.name.isEmpty {
            return "Уровень \(level.number)"
        }
        return "Уровень \(level.number): \(level.name)"
    }

    private func loadSnapshot(gameID: Int64) -> Snapshot? {
        loadAllSnapshots()[String(gameID)]
    }

    private func saveSnapshot(gameID: Int64, _ snapshot: Snapshot) {
        var snapshots = loadAllSnapshots()
        snapshots[String(gameID)] = snapshot
        persistSnapshots(snapshots)
    }

    private func loadAllSnapshots() -> [String: Snapshot] {
        guard let data = UserDefaults.standard.data(forKey: snapshotsKey),
              let decoded = try? JSONDecoder().decode([String: Snapshot].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func persistSnapshots(_ snapshots: [String: Snapshot]) {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        UserDefaults.standard.set(data, forKey: snapshotsKey)
    }
}
