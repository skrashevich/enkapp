import Foundation
import HuggingFace
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
@MainActor
final class DownloadedModelBackend: LocalAgentModel {
    /// Bounds the loop. A small model can loop on a tool it keeps misusing, and
    /// every step costs seconds of on-device generation.
    private static let maxSteps = 12

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
        invoke: @escaping @Sendable (String, String) async throws -> String
    ) async throws -> String {
        let container = try await loadedContainer()
        let tools = try DownloadedModelBackend.toolSpecs(catalogJSON: catalogJSON)

        if transcript.isEmpty {
            transcript.append(.system(instructions + "\n" + Self.toolProtocolInstructions))
        }
        transcript.append(.user(text))

        for _ in 0 ..< Self.maxSteps {
            let output = try await generate(container: container, tools: tools)
            transcript.append(.assistant(output))

            guard let call = ToolCallParser.firstCall(in: output) else {
                return ToolCallParser.stripThinking(output)
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
        return try await container.perform { context in
            let lmInput = try await context.processor.prepare(input: input)
            var text = ""
            _ = try MLXLMCommon.generate(
                input: lmInput,
                parameters: GenerateParameters(maxTokens: 512, temperature: 0.3),
                context: context
            ) { tokens in
                text = context.tokenizer.decode(tokenIds: tokens)
                return .more
            }
            return text
        }
    }

    private func loadedContainer() async throws -> ModelContainer {
        if let container {
            return container
        }
        let loaded = try await #huggingFaceLoadModelContainer(configuration: model.configuration)
        container = loaded
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

    var errorDescription: String? {
        switch self {
        case .badCatalog:
            return "Не удалось прочитать список инструментов движка."
        case .stepsExhausted:
            return "Локальная модель не смогла закончить ответ за отведённое число шагов."
        }
    }
}
