import Foundation
import Network
import Observation

enum CodeSubmissionKind: String, Codable, Hashable {
    case level
    case bonus
}

enum CodeSubmissionDeferredError: LocalizedError {
    case levelAnswerBlocked(seconds: Int)

    var errorDescription: String? {
        switch self {
        case .levelAnswerBlocked(let seconds):
            if seconds > 0 {
                return "Ответы на уровень заблокированы ещё на \(seconds) сек."
            }
            return "Ответ на уровень сейчас нельзя отправить."
        }
    }
}

struct CodeSubmission: Codable, Identifiable, Hashable {
    let id: UUID
    let gameID: Int64
    let levelID: Int64
    let levelNumber: Int64
    let code: String
    let kind: CodeSubmissionKind
    let createdAt: Date

    init(
        gameID: Int64,
        levelID: Int64,
        levelNumber: Int64,
        code: String,
        kind: CodeSubmissionKind = .level
    ) {
        self.id = UUID()
        self.gameID = gameID
        self.levelID = levelID
        self.levelNumber = levelNumber
        self.code = code
        self.kind = kind
        self.createdAt = Date()
    }

    enum CodingKeys: String, CodingKey {
        case id
        case gameID
        case levelID
        case levelNumber
        case code
        case kind
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        gameID = try container.decode(Int64.self, forKey: .gameID)
        levelID = try container.decode(Int64.self, forKey: .levelID)
        levelNumber = try container.decode(Int64.self, forKey: .levelNumber)
        code = try container.decode(String.self, forKey: .code)
        kind = try container.decodeIfPresent(CodeSubmissionKind.self, forKey: .kind) ?? .level
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

@Observable
@MainActor
final class CodeQueueStore {
    static let shared = CodeQueueStore()

    private let storageKey = "encx.pendingCodes"
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "encx.network")

    var pending: [CodeSubmission] = []
    var isOnline = true
    private(set) var isFlushing = false
    var onBackOnline: (() -> Void)?
    var onPendingAdded: (() -> Void)?

    private init() {
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
        postQueueDidChange()
    }

    func clear() {
        pending.removeAll()
        save()
        postQueueDidChange()
    }

    /// Drops a single submission that must not be retried, e.g. one the engine already accepted.
    func discard(_ id: UUID) {
        pending.removeAll { $0.id == id }
        save()
        postQueueDidChange()
    }

    func reloadFromDisk() {
        load()
    }

    private func postQueueDidChange() {
        NotificationCenter.default.post(name: .encxQueueDidChange, object: nil)
    }

    /// Result of one flush pass. The failure is reported back so the caller can decide whether the
    /// submission is worth retrying — swallowing it made every failure look like a dead engine.
    struct FlushOutcome {
        var latestModel: GameModel?
        var failedSubmission: CodeSubmission?
        var failure: Error?
    }

    func flush(send: (CodeSubmission) async throws -> GameModel) async -> FlushOutcome {
        guard isOnline, !pending.isEmpty, !isFlushing else { return FlushOutcome() }

        isFlushing = true
        defer { isFlushing = false }

        var outcome = FlushOutcome()
        var sentIDs = Set<UUID>()

        // pending может измениться (enqueue/clear) во время await, поэтому
        // работаем со снимком, а в конце убираем только реально отправленное.
        let snapshot = pending
        for submission in snapshot {
            do {
                outcome.latestModel = try await send(submission)
                sentIDs.insert(submission.id)
            } catch {
                outcome.failedSubmission = submission
                outcome.failure = error
                break
            }
        }

        pending.removeAll { sentIDs.contains($0.id) }
        save()
        postQueueDidChange()
        return outcome
    }

    private func load() {
        guard let data = EncounterSharedStorage.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([CodeSubmission].self, from: data) else {
            pending = []
            return
        }
        pending = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        EncounterSharedStorage.set(data, forKey: storageKey)
    }
}
