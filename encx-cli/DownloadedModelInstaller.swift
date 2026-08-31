import Foundation

/// Remembers which open model the player chose.
///
/// Only the identifier is stored; the weights live in the Hugging Face cache
/// that MLX manages, so switching models does not re-download one already there.
nonisolated enum DownloadedModelPreference {
    private static let key = "encx.agent.downloadedModel"

    static var selected: DownloadableModel {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let model = DownloadableModel(rawValue: raw) else {
                // The smallest model is the safe default: it is the only one that
                // fits comfortably on older devices.
                return .qwen3_0_6b
            }
            return model
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

/// Connects the app-only inference runtime to the shared agent session.
@MainActor
enum DownloadedModelInstaller {
    static func install() {
        LocalAgentModelFactory.makeDownloadedModel = {
            DownloadedModelBackend(model: DownloadedModelPreference.selected)
        }
        LocalAgentModelFactory.downloadedModelStatus = {
            let model = DownloadedModelPreference.selected
            return "\(model.title) · \(model.approximateSize)"
        }
    }
}
