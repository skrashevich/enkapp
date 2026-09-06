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
/// The raw values are passed to the engine as the provider name, except `codex`,
/// which selects a ChatGPT subscription over OAuth instead of an API key. A name
/// the engine does not know is fine as long as the provider carries an endpoint:
/// they all speak the same OpenAI-compatible chat API.
nonisolated enum AgentProvider: String, Codable, CaseIterable, Identifiable {
    case openai
    case anthropic
    case polza
    case codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .polza: return "Polza.AI"
        case .codex: return "ChatGPT"
        }
    }

    /// Shown under the provider picker. Empty when the provider needs no
    /// explaining — everyone knows what OpenAI is.
    var explanation: String {
        switch self {
        case .polza:
            return "Российский агрегатор: сотни моделей OpenAI, Anthropic, Google и других "
                + "по одному ключу, с оплатой картами РФ."
        case .openai, .anthropic, .codex:
            return ""
        }
    }

    /// Where to get an account for providers that need one before the key.
    var signupURL: URL? {
        switch self {
        case .polza: return URL(string: "https://polza.ai/?referral=6GWIX1KxUI")
        case .openai, .anthropic, .codex: return nil
        }
    }

    /// True when the provider authenticates with a ChatGPT login rather than a key.
    var usesSubscriptionLogin: Bool { self == .codex }

    var defaultModel: String {
        switch self {
        case .openai: return "gpt-5.6-sol"
        case .anthropic: return "claude-sonnet-4-6"
        // Polza is an aggregator, so its model names carry a vendor prefix.
        case .polza: return "deepseek/deepseek-v4-flash-vision-exp"
        case .codex: return "gpt-5.6-sol"
        }
    }

    /// Empty means "let the provider use its own default endpoint".
    var defaultAPIBase: String {
        switch self {
        case .openai, .anthropic, .codex: return ""
        case .polza: return "https://polza.ai/api/v1"
        }
    }

    /// Providers reached over a plain OpenAI-compatible endpoint expect the base
    /// URL to serve `/chat/completions`.
    var acceptsCustomEndpoint: Bool {
        switch self {
        case .openai, .anthropic, .polza: return true
        case .codex: return false
        }
    }
}

/// Assistant configuration. Credentials live in the Keychain, never here.
nonisolated struct AgentSettings: Codable, Equatable {
    /// Steps the assistant may take in one answer. Zero means no limit — some
    /// requests are legitimately long, like trying a whole range of codes.
    static let defaultMaxSteps = 100

    var enabled = false
    var provider: AgentProvider = .polza
    var model = AgentProvider.polza.defaultModel
    var apiBase = ""
    var policy: AgentAccessPolicy = .approve
    var fullAccessUnlocked = false
    var maxSteps = AgentSettings.defaultMaxSteps
    /// Lets the assistant search the web (DuckDuckGo) and read pages.
    var webToolsEnabled = true
    /// Lets the assistant read the device's GPS position. The iOS permission
    /// prompt still gates the actual fix, so this only offers the tool.
    var locationToolsEnabled = true

    init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled
        case provider
        case model
        case apiBase
        case policy
        case fullAccessUnlocked
        case maxSteps
        case webToolsEnabled
        case locationToolsEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        // Providers get removed over time — the local models ("onDevice",
        // "downloaded"), later OpenRouter — so a stored value can name a provider
        // that no longer exists. Falling back to the default keeps the rest of the
        // settings — the policy above all — instead of failing the whole decode and
        // resetting the assistant. The stored endpoint survives too, so a player
        // who was on OpenRouter keeps reaching it until they pick a new provider.
        provider = (try? container.decodeIfPresent(AgentProvider.self, forKey: .provider)) ?? .polza
        // A session stored for one of the removed local providers carries an empty
        // model name, which no hosted provider accepts.
        let storedModel = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        model = storedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? provider.defaultModel
            : storedModel
        apiBase = try container.decodeIfPresent(String.self, forKey: .apiBase) ?? provider.defaultAPIBase
        policy = try container.decodeIfPresent(AgentAccessPolicy.self, forKey: .policy) ?? .approve
        fullAccessUnlocked = try container.decodeIfPresent(Bool.self, forKey: .fullAccessUnlocked) ?? false
        if policy == .full && !fullAccessUnlocked {
            policy = .approve
        }
        maxSteps = try container.decodeIfPresent(Int.self, forKey: .maxSteps) ?? Self.defaultMaxSteps
        webToolsEnabled = try container.decodeIfPresent(Bool.self, forKey: .webToolsEnabled) ?? true
        locationToolsEnabled = try container.decodeIfPresent(Bool.self, forKey: .locationToolsEnabled) ?? true
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
        if provider.usesSubscriptionLogin {
            return AgentCredentialsStore.codexCredential() != nil
        }
        return AgentCredentialsStore.apiKey() != nil
    }

    /// Builds the JSON contract consumed by `EncClient.NewAgentSession`.
    func agentConfigJSON() throws -> String {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            throw AgentSessionError.notConfigured
        }

        var payload: [String: Any] = [
            "model": trimmedModel,
            "policy": policy.rawValue,
            // The Go side reads a negative budget as "no cap".
            "max_iterations": maxSteps > 0 ? maxSteps : -1,
            "web_tools": webToolsEnabled,
            "location_tools": locationToolsEnabled,
        ]

        if provider.usesSubscriptionLogin {
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
            // The engine only knows the endpoints of the providers it was built
            // with, and falls back to its own defaults for the rest — so a provider
            // it has never heard of has to carry its endpoint along. An empty field
            // in the settings means "the provider's default", not "no endpoint".
            var trimmedBase = apiBase.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedBase.isEmpty {
                trimmedBase = provider.defaultAPIBase
            }
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
