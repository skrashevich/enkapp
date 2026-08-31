import Foundation
import HuggingFace
import MLX
import OSLog
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Open models the app can download and run locally.
///
/// The list is deliberately short and small: a phone has to hold the weights in
/// RAM, and anything past a few billion parameters gets the app killed on most
/// devices. Qwen3 is used because it is the smallest family that emits tool
/// calls in a format worth parsing.
enum DownloadableModel: String, CaseIterable, Identifiable, Codable {
    case qwen3_0_6b
    case qwen3_1_7b
    case qwen3_4b

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qwen3_0_6b: return "Qwen3 0.6B"
        case .qwen3_1_7b: return "Qwen3 1.7B"
        case .qwen3_4b: return "Qwen3 4B"
        }
    }

    /// Rough download size, so the player can judge before starting.
    var approximateSize: String {
        switch self {
        case .qwen3_0_6b: return "~0,4 ГБ"
        case .qwen3_1_7b: return "~1,0 ГБ"
        case .qwen3_4b: return "~2,3 ГБ"
        }
    }

    var note: String {
        switch self {
        case .qwen3_0_6b: return "Самая маленькая. Быстрая, но часто ошибается в многошаговых задачах."
        case .qwen3_1_7b: return "Разумный компромисс для большинства устройств."
        case .qwen3_4b: return "Заметно умнее, но требует много памяти — не на всех iPhone."
        }
    }

    var configuration: ModelConfiguration {
        switch self {
        case .qwen3_0_6b: return LLMRegistry.qwen3_0_6b_4bit
        case .qwen3_1_7b: return LLMRegistry.qwen3_1_7b_4bit
        case .qwen3_4b: return LLMRegistry.qwen3_4b_4bit
        }
    }
}

/// Runs a downloaded open model on-device through MLX.
///
/// MLX does not execute tools: it renders them into the prompt through the
/// model's chat template and returns whatever the model emits. So this drives
/// the loop itself — generate, look for a tool call, run it through Go, feed the
/// result back — until the model answers in plain text.
///
/// The loop rests on Qwen3's reasoning mode. The model decides to call a tool
/// while it reasons, so the reasoning pass is not overhead to be trimmed: with
/// it suppressed, or with the token budget cut short before it finishes, the
/// model answers from memory and the toolset goes untouched. That costs seconds
/// per step on a phone, which is the price of tool use on a local model.
@MainActor
final class DownloadedModelBackend: LocalAgentModel {
    /// Bounds the loop. A small model can loop on a tool it keeps misusing, and
    /// every step costs seconds of on-device generation.
    private static let maxSteps = 12

    /// Token budget for one generation step.
    ///
    /// Qwen3 reasons before it acts, and it only emits tool calls from inside
    /// that reasoning pass — with thinking suppressed it answers from memory and
    /// never touches the toolset. Measured against this prompt, the model spends
    /// 80–600 tokens thinking before the call, so a budget below roughly a
    /// thousand truncates the step before the call is ever written.
    private static let maxTokensPerStep = 2048

    /// Diagnostics for the local loop. The prompt is built by a chat template
    /// inside MLX, so when the model ignores the toolset the only way to tell a
    /// template problem from a model problem is to look at what it was actually
    /// fed.
    nonisolated static let logger = Logger(subsystem: "com.svk-team.encx-cli", category: "local-model")

    private let model: DownloadableModel
    private var container: ModelContainer?
    private var transcript: [Chat.Message] = []

    init(model: DownloadableModel) {
        self.model = model
    }

    func reset() {
        transcript.removeAll()
    }

    func reply(
        to text: String,
        instructions: String,
        catalogJSON: String,
        reportActivity: @escaping @MainActor @Sendable (LocalAgentActivity?) -> Void,
        invoke: @escaping @Sendable (String, String) async throws -> String
    ) async throws -> String {
        let container = try await loadedContainer(reportActivity: reportActivity)
        let tools = try DownloadedModelBackend.toolSpecs(catalogJSON: catalogJSON)

        if transcript.isEmpty {
            Self.logger.debug("instructions from engine: \(instructions, privacy: .public)")
            transcript.append(.system(instructions + "\n" + Self.toolProtocolInstructions))
        }
        transcript.append(.user(text))

        for _ in 0 ..< Self.maxSteps {
            let output = try await generate(container: container, tools: tools)
            Self.logger.debug("model output: \(output, privacy: .public)")
            transcript.append(.assistant(output))

            guard let call = ToolCallParser.firstCall(in: output) else {
                let answer = ToolCallParser.stripThinking(output)
                // Stripping leaves nothing when the step produced only reasoning
                // and ran out of tokens. Reporting that is honest; an empty
                // bubble reads as a finished answer.
                guard !answer.isEmpty else { throw DownloadedModelError.emptyAnswer }
                return answer
            }

            let observation: String
            do {
                observation = try await invoke(call.name, call.argumentsJSON)
            } catch {
                // The model has to see the refusal, otherwise it reports success
                // for a call the player declined.
                observation = "error: \(error.localizedDescription)"
            }
            transcript.append(.user("<tool_response>\(observation)</tool_response>"))
        }

        throw DownloadedModelError.stepsExhausted
    }

    private func generate(container: ModelContainer, tools: [ToolSpec]) async throws -> String {
        let input = UserInput(chat: transcript, tools: tools)
        // Qwen3's own recommendation for its reasoning mode. The reply loop
        // depends on that mode, so the sampling has to match it: the earlier
        // 0.3 with no top-p made the model likelier to restate the question
        // instead of committing to a call.
        let parameters = GenerateParameters(
            maxTokens: Self.maxTokensPerStep,
            temperature: 0.6,
            topP: 0.95
        )
        let logger = Self.logger
        return try await container.perform { context in
            let lmInput = try await context.processor.prepare(input: input)

            // Decoding the prompt back is the only way to see whether the chat
            // template ran: when it is missing MLX silently falls back to joining
            // message contents, which drops the toolset entirely.
            let renderedPrompt = context.tokenizer.decode(
                tokenIds: lmInput.text.tokens.asArray(Int.self),
                skipSpecialTokens: false
            )
            logger.debug("""
                prompt: tools=\(tools.count, privacy: .public) \
                chars=\(renderedPrompt.count, privacy: .public) \
                templated=\(renderedPrompt.contains("<|im_start|>"), privacy: .public) \
                toolsRendered=\(renderedPrompt.contains("<tools>"), privacy: .public)
                """)

            var text = ""
            _ = try MLXLMCommon.generate(
                input: lmInput,
                parameters: parameters,
                context: context
            ) { tokens in
                // Special tokens are skipped so `<|im_end|>` never reaches the
                // player; `<tool_call>` is a plain added token, so it survives.
                text = context.tokenizer.decode(tokenIds: tokens, skipSpecialTokens: true)
                return .more
            }
            return text
        }
    }

    private func loadedContainer(
        reportActivity: @escaping @MainActor @Sendable (LocalAgentActivity?) -> Void
    ) async throws -> ModelContainer {
        if let container {
            return container
        }
        let loaded = try await #huggingFaceLoadModelContainer(
            configuration: model.configuration,
            progressHandler: { progress in
                let fraction = min(max(progress.fractionCompleted, 0), 1)
                // A cached snapshot reports a single completed unit. Ignore it
                // so subsequent launches do not flash a fake download status.
                guard fraction < 1 else { return }
                Task { @MainActor in
                    reportActivity(.downloadingModel(fractionCompleted: fraction))
                }
            }
        )
        container = loaded
        reportActivity(nil)
        return loaded
    }

    /// Renders the Go tool catalog into the OpenAI-style specs the chat template
    /// expects.
    private static func toolSpecs(catalogJSON: String) throws -> [ToolSpec] {
        guard let data = catalogJSON.data(using: .utf8),
              let described = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw DownloadedModelError.badCatalog
        }
        return described.compactMap { entry in
            guard let name = entry["name"] as? String else { return nil }
            return [
                "type": "function",
                "function": [
                    "name": name,
                    "description": entry["description"] as? String ?? "",
                    "parameters": entry["parameters"] as? [String: Any] ?? [:],
                ],
            ] as ToolSpec
        }
    }

    private static let toolProtocolInstructions = """
        Call a tool by emitting exactly one <tool_call>{"name": "...", "arguments": {...}}</tool_call> \
        block and nothing else. The result comes back inside <tool_response>. When you can answer, \
        reply in plain text without any tool_call block.
        """
}

/// Extracts a tool call from raw model output.
///
/// Qwen3 wraps calls in `<tool_call>` and reasoning in `<think>`; neither should
/// reach the player.
enum ToolCallParser {
    struct Call {
        let name: String
        let argumentsJSON: String
    }

    static func firstCall(in output: String) -> Call? {
        guard let body = between(output, open: "<tool_call>", close: "</tool_call>"),
              let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object["name"] as? String else {
            return nil
        }
        let arguments = object["arguments"] ?? [String: Any]()
        let argumentsJSON: String
        if let encoded = try? JSONSerialization.data(withJSONObject: arguments),
           let text = String(data: encoded, encoding: .utf8) {
            argumentsJSON = text
        } else {
            argumentsJSON = "{}"
        }
        return Call(name: name, argumentsJSON: argumentsJSON)
    }

    static func stripThinking(_ output: String) -> String {
        var text = output
        while let range = rangeOfBlock(text, open: "<think>", close: "</think>") {
            text.removeSubrange(range)
        }
        // A step that runs out of tokens mid-thought leaves an unclosed block.
        // Without this the player is shown the raw reasoning instead of an answer.
        if let start = text.range(of: "<think>") {
            text.removeSubrange(start.lowerBound ..< text.endIndex)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func between(_ text: String, open: String, close: String) -> String? {
        guard let start = text.range(of: open), let end = text.range(of: close, range: start.upperBound ..< text.endIndex) else {
            return nil
        }
        return String(text[start.upperBound ..< end.lowerBound])
    }

    private static func rangeOfBlock(_ text: String, open: String, close: String) -> Range<String.Index>? {
        guard let start = text.range(of: open), let end = text.range(of: close, range: start.upperBound ..< text.endIndex) else {
            return nil
        }
        return start.lowerBound ..< end.upperBound
    }
}

nonisolated enum DownloadedModelError: LocalizedError {
    case badCatalog
    case stepsExhausted
    case emptyAnswer

    var errorDescription: String? {
        switch self {
        case .badCatalog:
            return "Не удалось прочитать список инструментов движка."
        case .stepsExhausted:
            return "Локальная модель не смогла закончить ответ за отведённое число шагов."
        case .emptyAnswer:
            return "Локальная модель не выдала ответ — попробуйте переформулировать вопрос короче."
        }
    }
}
