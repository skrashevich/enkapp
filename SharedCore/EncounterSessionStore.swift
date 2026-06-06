import Foundation

enum EncounterSessionStore {
    static let settingsKey = "encx.domainSettings"
    static let loginKey = "encx.login"
    static let sessionCookiesKey = "encx.session.cookies"
    static let selectedGameIDKey = "encx.selectedGameID"

    private static let migrationKeys = [
        settingsKey,
        loginKey,
        sessionCookiesKey,
        selectedGameIDKey,
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
              let decoded = try? JSONDecoder().decode(DomainSettings.self, from: data) else {
            return DomainSettings()
        }
        return decoded
    }

    static func saveSettings(_ settings: DomainSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        EncounterSharedStorage.set(data, forKey: settingsKey)
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

    static func hasStoredCredentials(settings: DomainSettings, login: String) -> Bool {
        let trimmedLogin = login.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLogin.isEmpty else { return false }
        return KeychainCredentialsStore.loadPassword(domain: settings.domain, login: trimmedLogin) != nil
    }

    static func hasStoredSession(settings: DomainSettings, login: String) -> Bool {
        loadSessionCookies() != nil || hasStoredCredentials(settings: settings, login: login)
    }
}
