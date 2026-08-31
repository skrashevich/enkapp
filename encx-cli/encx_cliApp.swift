//
//  encx_cliApp.swift
//  encx-cli
//

import SwiftUI
import UIKit

@main
struct encx_cliApp: App {
    @UIApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    @State private var model = EncounterViewModel.screenshotModelIfRequested() ?? EncounterViewModel()

    init() {
        BackgroundQueueService.shared.register()
        // SharedCore also builds into the widget and the App Clip, so the
        // inference runtime is injected here rather than referenced there.
        DownloadedModelInstaller.install()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if ProcessInfo.processInfo.arguments.contains("--screenshot-settings") {
                    NavigationStack {
                        SettingsView(model: model)
                    }
                    .preferredColorScheme(.dark)
                } else if ProcessInfo.processInfo.arguments.contains("--screenshot-tools") {
                    ToolsHubView()
                } else if ProcessInfo.processInfo.arguments.contains("--screenshot-anagramizer") {
                    NavigationStack {
                        AnagramizerView(model: .screenshotModel())
                    }
                    .preferredColorScheme(.dark)
                } else if ProcessInfo.processInfo.arguments.contains("--screenshot-onboarding") {
                    OnboardingView(model: model) {}
                } else {
                    RootView(model: model)
                }
            }
        }
    }
}

/// Chooses between the first-launch setup flow and the main app, and keeps the
/// choice alive for the whole session so finishing onboarding does not need a relaunch.
private struct RootView: View {
    let model: EncounterViewModel
    @State private var showOnboarding: Bool

    init(model: EncounterViewModel) {
        self.model = model
        _showOnboarding = State(
            initialValue: Self.shouldShowOnboarding(for: model)
        )
    }

    private static func shouldShowOnboarding(for model: EncounterViewModel) -> Bool {
        guard !ProcessInfo.processInfo.arguments.contains("--screenshots") else { return false }
        return OnboardingStore.needsOnboarding(settings: model.settings, login: model.login)
    }

    var body: some View {
        Group {
            if showOnboarding {
                OnboardingView(model: model) {
                    showOnboarding = false
                }
            } else {
                ContentView(model: model)
                    .onAppear {
                        Task {
                            guard !ProcessInfo.processInfo.arguments.contains("--screenshots") else { return }
                            await model.requestNotificationAuthorizationIfNeeded()
                        }
                    }
            }
        }
        // Kept outside the branch so a widget or game deep link is not dropped while onboarding shows.
        .onOpenURL { url in
            Task { await model.handleIncomingURL(url) }
        }
    }
}

private final class AppLifecycleDelegate: NSObject, UIApplicationDelegate {
    func applicationWillTerminate(_ application: UIApplication) {
        Task { @MainActor in
            await QueueLiveActivityManager.endAll()
        }
    }
}
