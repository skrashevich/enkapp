import Foundation

enum EncounterSessionStore {
    static let settingsKey = "encx.domainSettings"
    static let loginKey = "encx.login"
    static let sessionCookiesKey = "encx.session.cookies"
    static let selectedGameIDKey = "encx.selectedGameID"

    static func loadSettings() -> DomainSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let decoded = try? JSONDecoder().decode(DomainSettings.self, from: data) else {
            return DomainSettings()
        }
        return decoded
    }

    static func saveSettings(_ settings: DomainSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: settingsKey)
    }

    static func loadLogin() -> String {
        UserDefaults.standard.string(forKey: loginKey) ?? ""
    }

    static func saveLogin(_ login: String) {
        UserDefaults.standard.set(login, forKey: loginKey)
    }

    static func loadSelectedGameID() -> Int64? {
        let value = UserDefaults.standard.object(forKey: selectedGameIDKey) as? Int64
            ?? UserDefaults.standard.object(forKey: selectedGameIDKey).flatMap { $0 as? Int }.map(Int64.init)
        return value
    }

    static func saveSelectedGameID(_ gameID: Int64?) {
        if let gameID {
            UserDefaults.standard.set(gameID, forKey: selectedGameIDKey)
        } else {
            UserDefaults.standard.removeObject(forKey: selectedGameIDKey)
        }
    }

    static func loadSessionCookies() -> Data? {
        if let data = UserDefaults.standard.data(forKey: sessionCookiesKey) {
            return data
        }
        let domain = loadSettings().domain
        let legacyKey = "encx.cookies.\(domain.lowercased())"
        if let legacy = UserDefaults.standard.data(forKey: legacyKey) {
            UserDefaults.standard.set(legacy, forKey: sessionCookiesKey)
            return legacy
        }
        return nil
    }

    static func saveSessionCookies(_ data: Data) {
        UserDefaults.standard.set(data, forKey: sessionCookiesKey)
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
