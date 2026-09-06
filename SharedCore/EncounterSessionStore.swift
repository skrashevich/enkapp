import Foundation

enum EncounterSessionStore {
    static let settingsKey = "encx.domainSettings"
    static let loginKey = "encx.login"
    static let sessionCookiesKey = "encx.session.cookies"
    static let selectedGameIDKey = "encx.selectedGameID"
    static let agentSettingsKey = "encx.agentSettings"

    private static let migrationKeys = [
        settingsKey,
        loginKey,
        sessionCookiesKey,
        selectedGameIDKey,
        agentSettingsKey,
    ]

    private static let didMigrateLegacyStorage: Void = {
        EncounterSharedStorage.migrateFromStandard(keys: migrationKeys)
    }()

    static func migrateLegacyStorageIfNeeded() {
        _ = didMigrateLegacyStorage
    }

    static func loadSettings() -> DomainSettings {
        migrateLegacyStorageIfNeeded()
        guard let data = EncounterSharedStorage.data(forKey: settingsKey),
              var decoded = try? JSONDecoder().decode(DomainSettings.self, from: data) else {
            return DomainSettings()
        }
        // Existing installations retain the retired endpoint even after the default changes.
        let endpoint = decoded.harUploadEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if URL(string: endpoint)?.host?.lowercased() == "enkapp-telemetry.exe.xyz" {
            decoded.harUploadEndpoint = DomainSettings.defaultHARUploadEndpoint
            saveSettings(decoded)
        }
        return decoded
    }

    static func saveSettings(_ settings: DomainSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        EncounterSharedStorage.set(data, forKey: settingsKey)
    }

    static func loadAgentSettings() -> AgentSettings {
        migrateLegacyStorageIfNeeded()
        guard let data = EncounterSharedStorage.data(forKey: agentSettingsKey),
              let decoded = try? JSONDecoder().decode(AgentSettings.self, from: data) else {
            return AgentSettings()
        }
        return decoded
    }

    static func saveAgentSettings(_ settings: AgentSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        EncounterSharedStorage.set(data, forKey: agentSettingsKey)
    }

    static func loadLogin() -> String {
        migrateLegacyStorageIfNeeded()
        return EncounterSharedStorage.string(forKey: loginKey) ?? ""
    }

    static func saveLogin(_ login: String) {
        EncounterSharedStorage.set(login, forKey: loginKey)
    }

    static func loadSelectedGameID() -> Int64? {
        migrateLegacyStorageIfNeeded()
        let stored = EncounterSharedStorage.object(forKey: selectedGameIDKey)
        let value = stored as? Int64
            ?? stored.flatMap { $0 as? Int }.map(Int64.init)
        return value
    }

    static func saveSelectedGameID(_ gameID: Int64?) {
        if let gameID {
            EncounterSharedStorage.set(gameID, forKey: selectedGameIDKey)
        } else {
            EncounterSharedStorage.removeObject(forKey: selectedGameIDKey)
        }
    }

    static func loadSessionCookies() -> Data? {
        migrateLegacyStorageIfNeeded()
        if let data = EncounterSharedStorage.data(forKey: sessionCookiesKey) {
            return data
        }
        let domain = loadSettings().domain
        let legacyKey = "encx.cookies.\(domain.lowercased())"
        if let legacy = EncounterSharedStorage.data(forKey: legacyKey) {
            EncounterSharedStorage.set(legacy, forKey: sessionCookiesKey)
            return legacy
        }
        return nil
    }

    static func saveSessionCookies(_ data: Data) {
        EncounterSharedStorage.set(data, forKey: sessionCookiesKey)
    }

    static func clearSessionCookies() {
        EncounterSharedStorage.removeObject(forKey: sessionCookiesKey)
        // `loadSessionCookies()` falls back to the legacy per-domain key and re-saves what it finds,
        // so leaving it in place would resurrect the session right after a logout.
        let domain = loadSettings().domain
        EncounterSharedStorage.removeObject(forKey: "encx.cookies.\(domain.lowercased())")
    }

    static func hasStoredCredentials(settings: DomainSettings, login: String) -> Bool {
        let trimmedLogin = login.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLogin.isEmpty else { return false }
        return KeychainCredentialsStore.loadPassword(domain: settings.domain, login: trimmedLogin) != nil
    }

    static func hasStoredSession(settings: DomainSettings, login: String) -> Bool {
        loadSessionCookies() != nil || hasStoredCredentials(settings: settings, login: login)
    }
}
