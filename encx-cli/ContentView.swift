import SwiftUI

struct ContentView: View {
    @Bindable var model: EncounterViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $model.navigationPath) {
            mainContent
                .navigationDestination(for: AppRoute.self, destination: destination)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .codes:
            CodesView(model: model)
        case .statistics(let gameID):
            GameStatisticsView(model: model, gameID: gameID)
        }
    }

    private var mainContent: some View {
        screenContent
            .modifier(SettingsChangeObserver(model: model))
            .modifier(LifecycleObserver(model: model, scenePhase: scenePhase))
            .modifier(ErrorAlertPresenter(model: model))
            .modifier(NewHintPopupPresenter(model: model))
            .sheet(isPresented: $model.showAntiSpamVerification) {
                AntiSpamVerificationView(model: model)
            }
    }

    private var screenContent: some View {
        VStack(spacing: 0) {
            screenNavigation

            Group {
                switch model.selectedScreen {
                case .games:
                AccountGamesView(model: model)
                case .game:
                LevelPlayView(model: model)
                case .team:
                TeamManagementView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(GameTheme.background)
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
                        .tint(GameTheme.text)
                        .disabled(model.isBusy)

                        Button {
                            model.selectedScreen = .team
                        } label: {
                            Image(systemName: "person.2.fill")
                        }
                        .tint(model.selectedScreen == .team ? GameTheme.accent : GameTheme.text)
                        .disabled(model.isBusy)
                        .accessibilityLabel("Управление командой")

                        NavigationLink {
                            SettingsView(model: model)
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .tint(GameTheme.text)
                    }
                }
            }
        }
        .toolbarBackground(GameTheme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .overlay(alignment: .bottom) {
            if model.isBusy {
                ProgressView()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 8)
            }
        }
    }

    private var screenNavigation: some View {
        HStack(spacing: 8) {
            screenNavigationButton(
                screen: .games,
                title: "Игры",
                systemImage: "list.bullet.rectangle"
            )
            screenNavigationButton(
                screen: .game,
                title: "Игра",
                systemImage: "gamecontroller.fill"
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(GameTheme.panel)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(GameTheme.border)
                .frame(height: 1)
        }
    }

    private func screenNavigationButton(
        screen: AppScreen,
        title: String,
        systemImage: String
    ) -> some View {
        Button {
            model.selectedScreen = screen
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(model.selectedScreen == screen ? .white : GameTheme.muted)
                .background(
                    model.selectedScreen == screen ? GameTheme.accent : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
        .buttonStyle(.plain)
    }

    private func refreshCurrentTab() async {
        switch model.selectedScreen {
        case .games:
            await model.refreshGames()
        case .game:
            await model.refreshLevel()
        case .team:
            await model.refreshTeam()
        }
    }
}

private struct LifecycleObserver: ViewModifier {
    @Bindable var model: EncounterViewModel
    let scenePhase: ScenePhase

    func body(content: Content) -> some View {
        content
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
                if model.selectedScreen != .game {
                    model.navigationPath.removeAll()
                }
                model.updateScreenWakeLock()
            }
            .onChange(of: model.selectedGameID) { _, _ in
                model.updateScreenWakeLock()
            }
            .onChange(of: model.queue.pending.count) { _, _ in
                model.updateScreenWakeLock()
            }
    }
}

private struct SettingsChangeObserver: ViewModifier {
    @Bindable var model: EncounterViewModel

    func body(content: Content) -> some View {
        content
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
            .onChange(of: model.settings.harRecordingEnabled) {
                model.applyHARRecordingSetting()
                model.persistAuthorizationSettings()
            }
            .onChange(of: model.settings.harUploadEnabled) {
                model.applyHARRecordingSetting()
                model.persistAuthorizationSettings()
            }
            .onChange(of: model.settings.harUploadEndpoint) {
                model.persistAuthorizationSettings()
            }
            .onChange(of: model.login) {
                model.persistAuthorizationSettings()
            }
    }
}

private struct ErrorAlertPresenter: ViewModifier {
    @Bindable var model: EncounterViewModel

    func body(content: Content) -> some View {
        content.alert(
            "Ошибка",
            isPresented: isPresented
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
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil && !model.showAntiSpamVerification },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}

private struct NewHintPopupPresenter: ViewModifier {
    @Bindable var model: EncounterViewModel

    func body(content: Content) -> some View {
        content.alert(
            model.newHintPopup?.title ?? "Новая подсказка",
            isPresented: isPresented
        ) {
            Button("OK", role: .cancel) {
                model.newHintPopup = nil
            }
        } message: {
            Text(model.newHintPopup?.message ?? "")
        }
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { model.newHintPopup != nil },
            set: { if !$0 { model.newHintPopup = nil } }
        )
    }
}

#Preview {
    ContentView(model: EncounterViewModel())
}
