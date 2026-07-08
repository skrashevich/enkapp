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
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if ProcessInfo.processInfo.arguments.contains("--screenshot-settings") {
                    NavigationStack {
                        SettingsView(model: model)
                    }
                    .preferredColorScheme(.dark)
                } else if ProcessInfo.processInfo.arguments.contains("--screenshot-anagramizer") {
                    NavigationStack {
                        AnagramizerView(model: .screenshotModel())
                    }
                    .preferredColorScheme(.dark)
                } else {
                    ContentView(model: model)
                        .onAppear {
                            Task {
                                guard !ProcessInfo.processInfo.arguments.contains("--screenshots") else { return }
                                await model.requestNotificationAuthorizationIfNeeded()
                            }
                        }
                        .onOpenURL { url in
                            Task { await model.handleWidgetURL(url) }
                        }
                    }
            }
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
