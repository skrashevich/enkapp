//
//  encx_cliApp.swift
//  encx-cli
//

import SwiftUI

@main
struct encx_cliApp: App {
    @State private var model = EncounterViewModel.screenshotModelIfRequested() ?? EncounterViewModel()

    init() {
        BackgroundQueueService.shared.register()
        TelemetryService.configure(settings: EncounterSessionStore.loadSettings())
        TelemetryService.track("app_launch")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if ProcessInfo.processInfo.arguments.contains("--screenshot-settings") {
                    NavigationStack {
                        SettingsView(model: model)
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
