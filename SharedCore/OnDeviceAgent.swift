import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Runs the assistant on Apple's on-device language model.
///
/// Nothing leaves the phone: no API key, no provider, no network. The engine
/// toolset still comes from Go, so the access policy, confirmations, pacing and
/// caching are exactly the ones the online backends use — the only thing that
/// changes is who decides which tool to call.
///
/// The trade-off is real: the system model is small and its context is short, so
/// it is far weaker at multi-step reasoning than a hosted model, and it cannot
/// look at pictures.
@MainActor
final class OnDeviceAgentBackend: LocalAgentModel {
    enum Availability: Equatable {
        case available
        case unsupported(String)
    }

    /// Whether this device can run the assistant locally, and why not if it cannot.
    static var availability: Availability {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            return .unsupported("Локальная модель требует iOS 26 или новее.")
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unsupported("Это устройство не поддерживает локальную модель Apple.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unsupported("Включите Apple Intelligence в настройках iOS.")
        case .unavailable(.modelNotReady):
            return .unsupported("Локальная модель ещё загружается. Повторите позже.")
        @unknown default:
            return .unsupported("Локальная модель сейчас недоступна.")
        }
        #else
        return .unsupported("Сборка выполнена без FoundationModels.")
        #endif
    }

    static var isAvailable: Bool { availability == .available }

    /// Holds the `LanguageModelSession` untyped: the app deploys back to iOS 18,
    /// where that type does not exist, and a stored property cannot carry an
    /// availability annotation.
    private var sessionStorage: Any?

    /// Answers one question, letting the model call engine tools as it goes.
    ///
    /// - Parameters:
    ///   - text: the player's message.
    ///   - instructions: the system prompt describing the engine and the policy.
    ///   - catalogJSON: the tool list published by the Go session.
    ///   - invoke: runs one tool by name; it enforces the policy gate.
    func reply(
        to text: String,
        instructions: String,
        catalogJSON: String,
        invoke: @escaping @Sendable (String, String) async throws -> String
    ) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            throw OnDeviceAgentError.unsupported(Self.availability.reason)
        }
        let session = try activeSession(instructions: instructions, catalogJSON: catalogJSON, invoke: invoke)
        return try await session.respond(to: text).content
        #else
        throw OnDeviceAgentError.unsupported(Self.availability.reason)
        #endif
    }

    /// Forgets the conversation so the next question starts clean.
    func reset() {
        sessionStorage = nil
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func activeSession(
        instructions: String,
        catalogJSON: String,
        invoke: @escaping @Sendable (String, String) async throws -> String
    ) throws -> LanguageModelSession {
        if let existing = sessionStorage as? LanguageModelSession {
            return existing
        }
        // The session keeps the transcript, so it is built once per chat rather
        // than per message.
        let tools = try Self.buildTools(catalogJSON: catalogJSON, invoke: invoke)
        let built = LanguageModelSession(tools: tools, instructions: instructions)
        sessionStorage = built
        return built
    }

    @available(iOS 26.0, *)
    private static func buildTools(
        catalogJSON: String,
        invoke: @escaping @Sendable (String, String) async throws -> String
    ) throws -> [any FoundationModels.Tool] {
        guard let data = catalogJSON.data(using: .utf8),
              let described = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw OnDeviceAgentError.badCatalog
        }

        return try described.compactMap { entry in
            guard let name = entry["name"] as? String,
                  let description = entry["description"] as? String else {
                return nil
            }
            let parameters = entry["parameters"] as? [String: Any] ?? [:]
            let schema = try EngineToolSchemaBuilder.schema(
                toolName: name,
                description: description,
                parameters: parameters
            )
            return EngineBridgeTool(
                name: name,
                description: description,
                parameters: schema,
                invoke: { argsJSON in try await invoke(name, argsJSON) }
            )
        }
    }
    #endif
}

nonisolated enum OnDeviceAgentError: LocalizedError {
    case unsupported(String)
    case badCatalog

    var errorDescription: String? {
        switch self {
        case .unsupported(let reason): return reason
        case .badCatalog: return "Не удалось прочитать список инструментов движка."
        }
    }
}

extension OnDeviceAgentBackend.Availability {
    var reason: String {
        switch self {
        case .available: return ""
        case .unsupported(let text): return text
        }
    }
}

#if canImport(FoundationModels)

/// One engine tool exposed to Apple's model.
///
/// The schema is built at runtime from the JSON schema Go publishes, so the two
/// backends always offer the same toolset without a second hand-written list.
@available(iOS 26.0, *)
private struct EngineBridgeTool: FoundationModels.Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let name: String
    let description: String
    let parameters: GenerationSchema
    let invoke: @Sendable (String) async throws -> String

    func call(arguments: GeneratedContent) async throws -> String {
        try await invoke(arguments.jsonString)
    }
}

@available(iOS 26.0, *)
enum EngineToolSchemaBuilder {
    /// Converts one JSON-schema object into a schema the model can be guided by.
    ///
    /// Only the shapes this toolset actually uses are translated — objects of
    /// string, integer, number and boolean properties. An unknown property type
    /// is dropped rather than guessed at, because a wrong schema makes the model
    /// emit arguments the tool then rejects.
    static func schema(
        toolName: String,
        description: String,
        parameters: [String: Any]
    ) throws -> GenerationSchema {
        let properties = parameters["properties"] as? [String: Any] ?? [:]
        let required = Set(parameters["required"] as? [String] ?? [])

        var fields: [DynamicGenerationSchema.Property] = []
        for (key, raw) in properties.sorted(by: { $0.key < $1.key }) {
            guard let spec = raw as? [String: Any],
                  let type = spec["type"] as? String,
                  let valueSchema = scalarSchema(for: type) else {
                continue
            }
            fields.append(DynamicGenerationSchema.Property(
                name: key,
                description: spec["description"] as? String,
                schema: valueSchema,
                isOptional: !required.contains(key)
            ))
        }

        let root = DynamicGenerationSchema(name: toolName, description: description, properties: fields)
        return try GenerationSchema(root: root, dependencies: [])
    }

    private static func scalarSchema(for type: String) -> DynamicGenerationSchema? {
        switch type {
        case "string": return DynamicGenerationSchema(type: String.self)
        case "integer": return DynamicGenerationSchema(type: Int.self)
        case "number": return DynamicGenerationSchema(type: Double.self)
        case "boolean": return DynamicGenerationSchema(type: Bool.self)
        default: return nil
        }
    }
}

#endif
