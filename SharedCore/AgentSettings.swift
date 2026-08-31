import Foundation
import Security

/// What the in-app assistant is allowed to do with the Encounter engine.
nonisolated enum AgentAccessPolicy: String, Codable, CaseIterable, Identifiable {
    /// The assistant reads game state but cannot change anything.
    case readonly
    /// Every code, hint or application is confirmed by the player first.
    case approve
    /// The assistant acts on the engine without asking.
    case full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readonly: return "Чтение"
        case .approve: return "С подтверждением"
        case .full: return "Без подтверждения"
        }
    }

    var explanation: String {
        switch self {
        case .readonly:
            return "Ассистент видит игру, уровни, подсказки и статистику, но ничего не отправляет."
        case .approve:
            return "Ассистент может отправить код или взять штрафную подсказку — но только после вашего подтверждения."
        case .full:
            return "Ассистент отправляет коды и берёт штрафные подсказки сам, ничего не спрашивая. "
                + "Ошибочный код тратит время и может включить блокировку ответов, а штрафная подсказка "
                + "необратимо добавляет штрафное время команде."
        }
    }

    /// True when acting on the engine needs no confirmation from the player.
    var actsWithoutAsking: Bool { self == .full }
}

/// LLM backends the assistant can talk to.
///
/// The raw values match PicoClaw provider names, except `codex`, which selects a
/// ChatGPT subscription over OAuth instead of an API key.
nonisolated enum AgentProvider: String, Codable, CaseIterable, Identifiable {
    case openai
    case anthropic
    case openrouter
    case codex
    /// Apple's on-device model. No key, no network.
    case onDevice
    /// An open model downloaded into the app and run locally.
    case downloaded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .openrouter: return "OpenRouter"
        case .codex: return "ChatGPT"
        case .onDevice: return "Apple"
        case .downloaded: return "Своя модель"
        }
    }

    /// True when the provider authenticates with a ChatGPT login rather than a key.
    var usesSubscriptionLogin: Bool { self == .codex }

    /// True when the model runs inside the app and needs no credentials at all.
    var runsOnDevice: Bool { self == .onDevice || self == .downloaded }

    /// True when the model has to be downloaded before it can answer.
    var needsModelDownload: Bool { self == .downloaded }

    /// True when the provider needs no stored secret.
    var needsNoCredential: Bool { runsOnDevice }

    var defaultModel: String {
        switch self {
        case .openai: return "gpt-5.4"
        case .anthropic: return "claude-sonnet-4-6"
        case .openrouter: return "openai/gpt-5.4"
        case .codex: return "gpt-5.6-sol"
        case .onDevice, .downloaded: return ""
        }
    }

    /// Empty means "let the provider use its own default endpoint".
    var defaultAPIBase: String {
        switch self {
        case .openai, .anthropic, .codex, .onDevice, .downloaded: return ""
        case .openrouter: return "https://openrouter.ai/api/v1"
        }
    }

    /// Providers reached over a plain OpenAI-compatible endpoint expect the base
    /// URL to serve `/chat/completions`.
    var acceptsCustomEndpoint: Bool {
        switch self {
        case .openai, .anthropic, .openrouter: return true
        case .codex, .onDevice, .downloaded: return false
        }
    }
}

/// Assistant configuration. Credentials live in the Keychain, never here.
nonisolated struct AgentSettings: Codable, Equatable {
    /// Steps the assistant may take in one answer. Zero means no limit — some
    /// requests are legitimately long, like trying a whole range of codes.
    static let defaultMaxSteps = 100

    var enabled = false
    var provider: AgentProvider = .openai
    var model = AgentProvider.openai.defaultModel
    var apiBase = ""
    var policy: AgentAccessPolicy = .approve
    var maxSteps = AgentSettings.defaultMaxSteps
    /// Lets the assistant search the web (DuckDuckGo) and read pages.
    var webToolsEnabled = true

    init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled
        case provider
        case model
        case apiBase
        case policy
        case maxSteps
        case webToolsEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        provider = try container.decodeIfPresent(AgentProvider.self, forKey: .provider) ?? .openai
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? provider.defaultModel
        apiBase = try container.decodeIfPresent(String.self, forKey: .apiBase) ?? provider.defaultAPIBase
        policy = try container.decodeIfPresent(AgentAccessPolicy.self, forKey: .policy) ?? .approve
        maxSteps = try container.decodeIfPresent(Int.self, forKey: .maxSteps) ?? Self.defaultMaxSteps
        webToolsEnabled = try container.decodeIfPresent(Bool.self, forKey: .webToolsEnabled) ?? true
    }

    /// Switches provider and resets the model and endpoint to that provider's defaults.
    mutating func applyProvider(_ newProvider: AgentProvider) {
        guard provider != newProvider else { return }
        provider = newProvider
        model = newProvider.defaultModel
        apiBase = newProvider.defaultAPIBase
    }

    /// Whether the assistant has everything it needs to start a session.
    var hasCredentials: Bool {
        if provider.needsNoCredential {
            return true
        }
        if provider.usesSubscriptionLogin {
            return AgentCredentialsStore.codexCredential() != nil
        }
        return AgentCredentialsStore.apiKey() != nil
    }

    /// Builds the JSON contract consumed by `EncClient.NewAgentSession`.
    func agentConfigJSON() throws -> String {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty || provider.runsOnDevice else {
            throw AgentSessionError.notConfigured
        }

        var payload: [String: Any] = [
            "model": trimmedModel,
            "policy": policy.rawValue,
            // The Go side reads a negative budget as "no cap".
            "max_iterations": maxSteps > 0 ? maxSteps : -1,
            "web_tools": webToolsEnabled,
        ]

        if provider.runsOnDevice {
            // There is no provider to build: the model lives in the app, and the
            // host drives the conversation while Go keeps the toolset.
            payload["auth_method"] = "on-device"
        } else if provider.usesSubscriptionLogin {
            guard let credential = AgentCredentialsStore.codexCredential() else {
                throw AgentSessionError.chatGPTSignInRequired
            }
            payload["auth_method"] = "codex"
            payload["codex_credential"] = credential
        } else {
            guard let apiKey = AgentCredentialsStore.apiKey() else {
                throw AgentSessionError.notConfigured
            }
            payload["provider"] = provider.rawValue
            payload["api_key"] = apiKey
            let trimmedBase = apiBase.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedBase.isEmpty {
                payload["api_base"] = trimmedBase
            }
        }

        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw AgentSessionError.configEncodingFailed
        }
        return json
    }
}

/// Keychain slots for the assistant's credentials. They are secrets, so they
/// never go into UserDefaults next to the rest of the settings.
nonisolated enum AgentCredentialsStore {
    private static let service = "dev.encx-cli.agent"
    private static let apiKeyAccount = "llm-api-key"
    private static let codexAccount = "chatgpt-credential"

    enum Error: Swift.Error {
        case encodingFailed
        case unhandled(OSStatus)
    }

    static func save(apiKey: String) throws {
        try store(apiKey, account: apiKeyAccount)
    }

    static func apiKey() -> String? {
        load(account: apiKeyAccount)
    }

    static func delete() {
        delete(account: apiKeyAccount)
    }

    /// Stores the JSON credential returned by the ChatGPT device login.
    static func save(codexCredential: String) throws {
        try store(codexCredential, account: codexAccount)
    }

    static func codexCredential() -> String? {
        load(account: codexAccount)
    }

    static func deleteCodexCredential() {
        delete(account: codexAccount)
    }

    // MARK: - Keychain plumbing

    private static func store(_ value: String, account: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            delete(account: account)
            return
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw Error.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw Error.unhandled(updateStatus)
            }
        } else if status != errSecSuccess {
            throw Error.unhandled(status)
        }
    }

    private static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

nonisolated enum AgentSessionError: LocalizedError {
    case notConfigured
    case chatGPTSignInRequired
    case configEncodingFailed
    case bindingsUnavailable

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Ассистент не настроен: укажите модель и ключ API в настройках."
        case .chatGPTSignInRequired:
            return "Войдите в ChatGPT в настройках ассистента."
        case .configEncodingFailed:
            return "Не удалось собрать конфигурацию ассистента."
        case .bindingsUnavailable:
            return "Encx.xcframework не подключен к target."
        }
    }
}
