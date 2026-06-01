import Foundation
import Network
import Observation

struct CodeSubmission: Codable, Identifiable, Hashable {
    let id: UUID
    let gameID: Int64
    let levelID: Int64
    let levelNumber: Int64
    let code: String
    let createdAt: Date

    init(gameID: Int64, levelID: Int64, levelNumber: Int64, code: String) {
        self.id = UUID()
        self.gameID = gameID
        self.levelID = levelID
        self.levelNumber = levelNumber
        self.code = code
        self.createdAt = Date()
    }
}

@Observable
@MainActor
final class CodeQueueStore {
    private let storageKey = "encx.pendingCodes"
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "encx.network")

    var pending: [CodeSubmission] = []
    var isOnline = true
    var onBackOnline: (() -> Void)?
    var onPendingAdded: (() -> Void)?

    init() {
        load()
        monitor.pathUpdateHandler = { @Sendable [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isOnline = path.status == .satisfied
                if self.isOnline && !self.pending.isEmpty {
                    self.onBackOnline?()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    func enqueue(_ submission: CodeSubmission) {
        pending.append(submission)
        save()
        onPendingAdded?()
    }

    func clear() {
        pending.removeAll()
        save()
    }

    func flush(send: (CodeSubmission) async throws -> GameModel) async throws -> GameModel? {
        guard isOnline, !pending.isEmpty else { return nil }

        var latestModel: GameModel?
        var unsent: [CodeSubmission] = []
        var stoppedEarly = false

        for submission in pending {
            if stoppedEarly {
                unsent.append(submission)
                continue
            }

            do {
                latestModel = try await send(submission)
            } catch {
                unsent.append(submission)
                stoppedEarly = true
            }
        }

        pending = unsent
        save()
        return latestModel
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([CodeSubmission].self, from: data) else {
            pending = []
            return
        }
        pending = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
