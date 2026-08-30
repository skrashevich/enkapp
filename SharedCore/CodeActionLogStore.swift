import Foundation

enum CodeActionLogStore {
    private static let storageKeyPrefix = "encx.codeLog"

    static func load(domain: String, gameID: Int64) -> [CodeAction] {
        guard let data = EncounterSharedStorage.data(forKey: storageKey(domain: domain, gameID: gameID)),
              let actions = try? JSONDecoder().decode([CodeAction].self, from: data) else {
            return []
        }
        return sortedAndDeduplicated(actions)
    }

    static func save(_ actions: [CodeAction], domain: String, gameID: Int64) {
        guard let data = try? JSONEncoder().encode(sortedAndDeduplicated(actions)) else { return }
        EncounterSharedStorage.set(data, forKey: storageKey(domain: domain, gameID: gameID))
    }

    private static func storageKey(domain: String, gameID: Int64) -> String {
        let normalizedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(storageKeyPrefix).\(normalizedDomain).\(gameID)"
    }

    private static func sortedAndDeduplicated(_ actions: [CodeAction]) -> [CodeAction] {
        var actionsByID: [Int: CodeAction] = [:]
        for action in actions {
            actionsByID[action.actionID] = action
        }
        return actionsByID.values.sorted {
            if $0.levelNumber != $1.levelNumber {
                return $0.levelNumber > $1.levelNumber
            }
            return $0.actionID > $1.actionID
        }
    }
}
