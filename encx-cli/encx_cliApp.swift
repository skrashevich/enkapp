//
//  encx_cliApp.swift
//  encx-cli
//

import SwiftUI

@main
struct encx_cliApp: App {
    @State private var model = EncounterViewModel()

    init() {
        BackgroundQueueService.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onAppear {
                    Task {
                        await model.requestNotificationAuthorizationIfNeeded()
                    }
                }
                .onOpenURL { url in
                    Task { await model.handleWidgetURL(url) }
                }
        }
    }
}
