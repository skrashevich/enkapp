import Foundation

struct AppClipInvocation: Equatable {
    private nonisolated static let fallbackDomain = "encounter.exe.xyz"
    nonisolated static let webHost = "enkapp.svk.app"

    var domain: String
    var gameID: Int64?

    nonisolated static let fallback = AppClipInvocation(
        domain: fallbackDomain,
        gameID: nil
    )

    nonisolated init(domain: String, gameID: Int64?) {
        let normalized = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.domain = normalized.isEmpty ? Self.fallbackDomain : normalized
        self.gameID = gameID
    }

    nonisolated init(url: URL) {
        var domain: String?
        var gameID: Int64?

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            for item in components.queryItems ?? [] {
                switch item.name.lowercased() {
                case "domain", "host":
                    domain = item.value
                case "game", "gameid", "id":
                    gameID = item.value.flatMap(Int64.init)
                default:
                    break
                }
            }
        }

        let pathParts = url.path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }

        if pathParts.first?.lowercased() == "g" {
            if pathParts.count >= 3 {
                domain = domain ?? pathParts[1]
                gameID = gameID ?? Int64(pathParts[2])
            } else if pathParts.count >= 2 {
                gameID = gameID ?? Int64(pathParts[1])
            }
        }

        self.init(domain: domain ?? Self.fallbackDomain, gameID: gameID)
    }

    nonisolated static func isSupportedWebURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == webHost
    }
}
