import Foundation

/// Tracks whether the first-launch setup flow has already been shown.
enum OnboardingStore {
    static let completedKey = "encx.onboarding.completed"

    static var hasCompleted: Bool {
        EncounterSharedStorage.object(forKey: completedKey) as? Bool == true
    }

    static func markCompleted() {
        EncounterSharedStorage.set(true, forKey: completedKey)
    }

    static func reset() {
        EncounterSharedStorage.removeObject(forKey: completedKey)
    }

    /// Players who upgrade from a build without onboarding already have a session, so
    /// showing them the setup flow would be a regression. They are marked as done instead.
    static func needsOnboarding(settings: DomainSettings, login: String) -> Bool {
        guard !hasCompleted else { return false }
        guard !EncounterSessionStore.hasStoredSession(settings: settings, login: login) else {
            markCompleted()
            return false
        }
        return true
    }
}
