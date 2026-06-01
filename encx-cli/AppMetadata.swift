import Foundation

enum AppMetadata {
    /// Имя под иконкой на домашнем экране и в системных списках (дублирует CFBundleDisplayName).
    static let displayName = "enkapp"

    static let repositoryURL = URL(string: "https://github.com/skrashevich/enkapp")!
    static let apiClientRepositoryURL = URL(string: "https://github.com/skrashevich/encx-cli")!
}
