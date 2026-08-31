import Foundation

#if canImport(Encx)
import Encx
#endif

/// One line of the assistant transcript.
nonisolated struct AgentMessage: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant
        case failure
    }

    let id = UUID()
    let role: Role
    var text: String
}

/// A short Russian label for the engine capability behind a tool name.
nonisolated func agentToolTitle(_ tool: String) -> String {
    switch tool {
    case "enc_profile": return "Профиль"
    case "enc_team": return "Команда"
    case "enc_domain_games": return "Игры домена"
    case "enc_game_list": return "Список игр"
    case "enc_game_timeout": return "Время до старта"
    case "enc_game_state": return "Состояние игры"
    case "enc_level": return "Уровень"
    case "enc_action_log": return "Лог кодов"
    case "enc_game_statistics": return "Статистика"
    case "enc_send_code": return "Отправка кода"
    case "enc_send_bonus_code": return "Отправка бонуса"
    case "enc_take_penalty_hint": return "Штрафная подсказка"
    case "enc_enter_game": return "Заявка на игру"
    default: return tool
    }
}

/// An engine tool call shown under the assistant while it works.
///
/// `id` is the call identifier minted by the Go session, so parallel calls to
/// the same tool stay distinct.
nonisolated struct AgentToolActivity: Identifiable, Equatable {
    let id: String
    let tool: String
    var arguments: String
    var isFinished = false
    var isError = false

    var title: String { agentToolTitle(tool) }
}

/// A mutating call waiting for the player's decision.
nonisolated struct AgentConfirmation: Identifiable, Equatable {
    let id: String
    let tool: String
    let arguments: String

    var title: String { agentToolTitle(tool) }
}

/// Drives the embedded PicoClaw agent and republishes its progress on the main actor.
///
/// The Go session calls back from its own goroutines, so every delegate callback
/// hops onto the main actor before touching published state.
@MainActor
@Observable
final class AgentChatSession {
    private(set) var messages: [AgentMessage] = []
    private(set) var activity: [AgentToolActivity] = []
    private(set) var localModelActivity: LocalAgentActivity?
    private(set) var isRunning = false
    private(set) var toolCount = 0

    /// Mutating calls awaiting a decision.
    ///
    /// PicoClaw executes the tool calls of one iteration in parallel, so a turn
    /// can raise several confirmations at once. A single slot would silently drop
    /// all but the last and park the turn forever, so they queue here and are
    /// presented one at a time.
    private(set) var pendingConfirmations: [AgentConfirmation] = []

    var currentConfirmation: AgentConfirmation? { pendingConfirmations.first }

    /// Turn number of the most recent progress event, and of the newest turn known
    /// to have ended. Together they let a late confirmation be recognised as stale.
    private var currentTurn: Int64 = 0
    private var lastFinishedTurn: Int64 = 0

    let policy: AgentAccessPolicy

    #if canImport(Encx)
    private let session: EncxmobileAgentSession
    private var delegate: AgentDelegateBridge?
    #endif
    /// Non-nil when the model runs inside the app instead of behind a provider.
    private let onDevice: (any LocalAgentModel)?

    /// - Parameters:
    ///   - client: the authenticated Encounter client the agent plays through.
    ///   - settings: provider, model and access policy.
    init(client: EncounterClient, settings: AgentSettings) throws {
        policy = settings.policy

        switch settings.provider {
        case .onDevice:
            if case .unsupported(let reason) = OnDeviceAgentBackend.availability {
                throw OnDeviceAgentError.unsupported(reason)
            }
            onDevice = OnDeviceAgentBackend()
        case .downloaded:
            // The factory is installed by the app target only, so the widget and
            // App Clip never link the inference runtime.
            guard let backend = LocalAgentModelFactory.makeDownloadedModel?() else {
                throw OnDeviceAgentError.unsupported("Локальная модель недоступна в этой сборке.")
            }
            onDevice = backend
        default:
            onDevice = nil
        }

        #if canImport(Encx)
        session = try client.makeAgentSession(configJSON: try settings.agentConfigJSON())
        toolCount = Int(session.toolCount())
        let bridge = AgentDelegateBridge(owner: self)
        delegate = bridge
        session.setDelegate(bridge)
        #else
        throw AgentSessionError.bindingsUnavailable
        #endif
    }

    deinit {
        // The Go turn runs on its own goroutines and keeps this session alive
        // through the detached task. Without cancelling here, dismissing the chat
        // mid-turn would leave a tool call blocked on a confirmation nobody can
        // answer any more.
        #if canImport(Encx)
        session.setDelegate(nil)
        session.cancel()
        #endif
    }

    /// Sends a message and waits for the assistant's reply.
    func send(_ text: String, gameID: Int64?, levelID: Int?) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRunning else { return }

        let modelInput = Self.messageWithGameContext(
            trimmed,
            gameID: gameID,
            levelID: levelID
        )

        messages.append(AgentMessage(role: .user, text: trimmed))
        activity.removeAll()
        isRunning = true
        defer {
            isRunning = false
            localModelActivity = nil
            lastFinishedTurn = currentTurn
            pendingConfirmations.removeAll()
            // A token refreshed mid-turn must be stored even when the turn failed:
            // OpenAI rotates refresh tokens, so the one still in the Keychain has
            // already been revoked.
            persistRefreshedCredential()
        }

        #if canImport(Encx)
        let session = self.session
        do {
            let reply: String
            if let onDevice {
                reply = try await replyOnDevice(modelInput, backend: onDevice)
            } else {
                // The gomobile call blocks for the whole turn; keep it off the main actor.
                reply = try await Task.detached(priority: .userInitiated) {
                    var error: NSError?
                    let reply = session.sendMessage(modelInput, error: &error)
                    if let error { throw error }
                    return reply
                }.value
            }
            messages.append(AgentMessage(role: .assistant, text: reply))
        } catch {
            messages.append(AgentMessage(role: .failure, text: error.localizedDescription))
        }
        #else
        messages.append(AgentMessage(role: .failure, text: AgentSessionError.bindingsUnavailable.localizedDescription))
        #endif
    }

    /// Adds identifiers already known by the app before the model decides which
    /// tools to call. Keeping this separate from the visible transcript avoids
    /// making the player repeat IDs and lets the model address the current game
    /// or level directly instead of discovering them through list/state calls.
    static func messageWithGameContext(_ text: String, gameID: Int64?, levelID: Int?) -> String {
        var identifiers: [String] = []
        if let gameID {
            identifiers.append("game_id: \(gameID)")
        }
        if let levelID {
            identifiers.append("level_id: \(levelID)")
        }
        guard !identifiers.isEmpty else { return text }

        return """
        Current Encounter context supplied by the app:
        \(identifiers.joined(separator: "\n"))
        Use these IDs directly. Do not call tools only to discover the current game_id or level_id.

        Player message:
        \(text)
        """
    }

    /// Aborts the running turn.
    func cancel() {
        #if canImport(Encx)
        session.cancel()
        #endif
    }

    /// Answers a pending confirmation. Calling it twice for the same call is a
    /// no-op, so the UI can resolve from a button and from dismissal without
    /// depending on which runs first.
    func resolve(_ confirmation: AgentConfirmation, approved: Bool) {
        guard let index = pendingConfirmations.firstIndex(where: { $0.id == confirmation.id }) else {
            return
        }
        pendingConfirmations.remove(at: index)

        #if canImport(Encx)
        do {
            try session.resolveConfirmation(confirmation.id, approved: approved)
        } catch {
            messages.append(AgentMessage(role: .failure, text: error.localizedDescription))
        }
        #endif
    }

    /// Clears the transcript on both sides.
    func reset() {
        guard !isRunning else { return }
        messages.removeAll()
        activity.removeAll()
        onDevice?.reset()
        #if canImport(Encx)
        session.resetHistory()
        #endif
    }

    #if canImport(Encx)
    /// Runs one turn on Apple's on-device model.
    ///
    /// Go still owns the toolset, so the access policy, confirmations, pacing and
    /// caching are the same as for the hosted backends. Only the decision of
    /// which tool to call moves into the app.
    private func replyOnDevice(_ text: String, backend: any LocalAgentModel) async throws -> String {
        let session = self.session

        // gomobile returns a nonnull string plus NSError**, so the error stays an
        // explicit parameter rather than becoming a throwing call.
        var error: NSError?
        let catalogJSON = session.toolCatalogJSON(&error)
        if let error { throw error }
        let instructions = session.systemPrompt()

        var turn: Int64 = 0
        try session.beginHostTurn(&turn)

        var turnError: Error?
        defer {
            session.endHostTurn(turnError == nil ? "…" : "", reason: turnError?.localizedDescription ?? "")
        }

        do {
            let reply = try await backend.reply(
                to: text,
                instructions: instructions,
                catalogJSON: catalogJSON,
                reportActivity: { [weak self] activity in
                    self?.localModelActivity = activity
                },
                invoke: { name, argsJSON in
                    // The Go call blocks while a tool talks to the engine, and can
                    // block much longer while the player answers a confirmation.
                    try await Task.detached(priority: .userInitiated) {
                        var error: NSError?
                        let result = session.invokeTool(name, argsJSON: argsJSON, error: &error)
                        if let error { throw error }
                        return result
                    }.value
                }
            )
            session.recordHostExchange(text, assistantMessage: reply)
            return reply
        } catch {
            turnError = error
            throw error
        }
    }
    #endif

    /// Stores a ChatGPT token that the Go session refreshed mid-turn.
    private func persistRefreshedCredential() {
        #if canImport(Encx)
        var error: NSError?
        let credentialJSON = session.codexCredentialJSON(&error)
        guard error == nil, !credentialJSON.isEmpty else { return }
        try? AgentCredentialsStore.save(codexCredential: credentialJSON)
        #endif
    }

    // MARK: - Callbacks from Go

    fileprivate func handle(eventJSON: String) {
        guard let data = eventJSON.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else {
            return
        }

        if let turn = (event["turn"] as? NSNumber)?.int64Value {
            currentTurn = turn
        }

        switch type {
        case "tool_started":
            guard let tool = event["tool"] as? String,
                  let callID = event["call_id"] as? String else { return }
            activity.append(AgentToolActivity(
                id: callID,
                tool: tool,
                arguments: Self.describe(event["args"])
            ))
        case "tool_finished":
            guard let callID = event["call_id"] as? String,
                  let index = activity.firstIndex(where: { $0.id == callID }) else {
                return
            }
            activity[index].isFinished = true
            activity[index].isError = event["is_error"] as? Bool ?? false
        default:
            // turn_failed is already surfaced by the error SendMessage returns.
            break
        }
    }

    fileprivate func handleConfirmation(callID: String, turn: Int64, tool: String, argsJSON: String) {
        // The notification crosses actors, so it can land after its turn ended —
        // for instance when the player hits Stop as the call is raised. Showing it
        // then would ask about a call that has already been refused, and would sit
        // in front of a genuine request from the next turn. Comparing against the
        // last finished turn rather than the current one fails open: an unknown
        // turn is shown rather than dropped, because a dropped confirmation would
        // park the agent forever.
        guard turn > lastFinishedTurn else { return }
        guard !pendingConfirmations.contains(where: { $0.id == callID }) else { return }
        pendingConfirmations.append(AgentConfirmation(
            id: callID,
            tool: tool,
            arguments: Self.describe(argsJSON: argsJSON)
        ))
    }

    /// Renders tool arguments as `ключ: значение` lines for the UI.
    static func describe(argsJSON: String) -> String {
        guard let data = argsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return argsJSON
        }
        return describe(object)
    }

    static func describe(_ value: Any?) -> String {
        guard let dictionary = value as? [String: Any], !dictionary.isEmpty else { return "" }
        return dictionary
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: ", ")
    }
}

#if canImport(Encx)
/// Adapts the gomobile delegate protocol to the main-actor session.
///
/// gomobile emits both a class and a protocol named `EncxmobileAgentDelegate`,
/// so Swift imports the protocol under the `Protocol` suffix.
private final class AgentDelegateBridge: NSObject, EncxmobileAgentDelegateProtocol {
    private weak var owner: AgentChatSession?

    init(owner: AgentChatSession) {
        self.owner = owner
    }

    func onEvent(_ eventJSON: String?) {
        guard let eventJSON else { return }
        Task { @MainActor [weak owner] in
            owner?.handle(eventJSON: eventJSON)
        }
    }

    func onConfirmationRequest(_ callID: String?, turn: Int64, toolName: String?, argsJSON: String?) {
        guard let callID, let toolName else { return }
        Task { @MainActor [weak owner] in
            owner?.handleConfirmation(
                callID: callID,
                turn: turn,
                tool: toolName,
                argsJSON: argsJSON ?? "{}"
            )
        }
    }
}
#endif
