import SwiftUI

struct ContentView: View {
    @Bindable var model: EncounterViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            TabView(selection: $model.selectedScreen) {
                AccountGamesView(model: model)
                    .tag(AppScreen.games)
                    .tabItem {
                        Label("Игры", systemImage: "list.bullet.rectangle")
                    }

                LevelPlayView(model: model)
                    .tag(AppScreen.game)
                    .tabItem {
                        Label("Игра", systemImage: "gamecontroller.fill")
                    }
            }
            .navigationTitle(model.selectedScreen.title)
            .toolbar(model.selectedScreen == .game ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                if model.selectedScreen != .game {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 16) {
                            Button {
                                Task { await refreshCurrentTab() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .disabled(model.isBusy)

                            NavigationLink {
                                SettingsView(model: model)
                            } label: {
                                Image(systemName: "gearshape")
                            }
                        }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if model.isBusy {
                    ProgressView()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 8)
                }
            }
            .task {
                await model.restoreSession()
                await model.flushQueueOnResume()
                model.updateScreenWakeLock()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    model.updateScreenWakeLock()
                    Task { await model.flushQueueOnResume() }
                case .background:
                    model.handleAppBackground()
                default:
                    break
                }
            }
            .onChange(of: model.selectedScreen) { _, _ in
                model.updateScreenWakeLock()
            }
            .onChange(of: model.selectedGameID) { _, _ in
                model.updateScreenWakeLock()
            }
            .onChange(of: model.queue.pending.count) { _, _ in
                model.updateScreenWakeLock()
            }
            .onChange(of: model.settings.useHTTP) {
                model.persistAuthorizationSettings()
            }
            .onChange(of: model.settings.insecureTLS) {
                model.persistAuthorizationSettings()
            }
            .onChange(of: model.settings.liveActivityEnabled) {
                Task { await model.applyLiveActivitySetting() }
            }
            .onChange(of: model.settings.liveActivityDisplay) {
                model.persistAuthorizationSettings()
                Task { await model.applyLiveActivitySetting() }
            }
            .onChange(of: model.settings.pushOnNewLevel) {
                model.persistAuthorizationSettings()
            }
            .onChange(of: model.settings.pushOnNewHint) {
                model.persistAuthorizationSettings()
            }
            .onChange(of: model.login) {
                model.persistAuthorizationSettings()
            }
            .alert(
                "Ошибка",
                isPresented: Binding(
                    get: { model.errorMessage != nil && !model.showAntiSpamVerification },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                if model.antiSpamVerificationURL != nil {
                    Button("Пройти проверку") {
                        model.showAntiSpamVerification = true
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .sheet(isPresented: $model.showAntiSpamVerification) {
                AntiSpamVerificationView(model: model)
            }
        }
        .preferredColorScheme(model.selectedScreen == .game ? .dark : nil)
    }

    private func refreshCurrentTab() async {
        switch model.selectedScreen {
        case .games:
            await model.refreshGames()
        case .game:
            await model.refreshLevel()
        }
    }
}

#Preview {
    ContentView(model: EncounterViewModel())
}
