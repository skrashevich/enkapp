import Foundation

/// Work performed by a local model before it can start answering.
nonisolated enum LocalAgentActivity: Equatable {
    case downloadingModel(fractionCompleted: Double)
}

/// A language model that answers inside the app instead of behind a provider.
///
/// The engine toolset stays in Go, so an implementation only decides which tool
/// to call — the access policy, confirmations, pacing and caching are unchanged.
@MainActor
protocol LocalAgentModel: AnyObject {
    /// Answers one question, calling engine tools as needed.
    ///
    /// - Parameters:
    ///   - text: the player's message.
    ///   - instructions: system prompt describing the engine and the policy.
    ///   - catalogJSON: the tool list published by the Go session.
    ///   - reportActivity: publishes model preparation such as a first-run download.
    ///   - invoke: runs one tool by name; it enforces the policy gate.
    func reply(
        to text: String,
        instructions: String,
        catalogJSON: String,
        reportActivity: @escaping @MainActor @Sendable (LocalAgentActivity?) -> Void,
        invoke: @escaping @Sendable (String, String) async throws -> String
    ) async throws -> String

    /// Forgets the conversation.
    func reset()
}

/// How a downloaded open model is created.
///
/// The implementation lives in the app target only. `SharedCore` also compiles
/// into the widget and the App Clip, and neither should link a multi-megabyte
/// inference runtime, so the app installs its factory here at launch and the
/// other targets simply leave it nil.
@MainActor
enum LocalAgentModelFactory {
    /// Builds the downloaded-model backend, or nil when the app never installed one.
    static var makeDownloadedModel: (() -> LocalAgentModel)?

    /// Describes the download state of the selected open model, for settings UI.
    static var downloadedModelStatus: (() -> String)?
}
