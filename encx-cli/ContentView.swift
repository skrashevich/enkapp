import SwiftUI

struct ContentView: View {
    @Bindable var model: EncounterViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // The tab bar is a sibling of the stack, not a safe-area inset on it: an inset would let
        // the screens' own bottom insets (the level/codes input bar) lay out underneath the bar.
        // As a sibling it consumes real layout height, so those bars land right above it, and it
        // still stays visible on pushed destinations.
        VStack(spacing: 0) {
            NavigationStack(path: $model.navigationPath) {
                mainContent
                    .navigationDestination(for: AppRoute.self, destination: destination)
            }
            bottomTabBar
        }
        // Present model errors and the tools sheet from the navigation container so they are visible
        // on the currently displayed destination (not only after returning to the root screen).
        .sheet(isPresented: $model.showToolsSheet) {
            ToolsHubView()
        }
        .modifier(ErrorAlertPresenter(model: model))
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
            .modifier(NewHintPopupPresenter(model: model))
            .sheet(isPresented: $model.showAntiSpamVerification) {
                AntiSpamVerificationView(model: model)
            }
            .sheet(isPresented: $model.showAgentSheet) {
                AgentChatView(model: model)
            }
    }

    private var screenContent: some View {
        Group {
            switch model.selectedScreen {
            case .games:
                AccountGamesView(model: model)
            case .game:
                LevelPlayView(model: model)
            case .team:
                TeamManagementView(model: model)
            case .tools:
                ToolsHubContent()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GameTheme.background)
        .navigationTitle(model.selectedScreen.title)
        .toolbar(model.selectedScreen == .game ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            if model.selectedScreen != .game && model.selectedScreen != .tools {
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

                        if model.agentSettings.enabled {
                            Button {
                                model.showAgentSheet = true
                            } label: {
                                AgentIcon()
                            }
                            .tint(GameTheme.bonusTitle)
                            .disabled(model.isBusy)
                            .accessibilityLabel("Ассистент")
                        }

                        Button {
                            model.showToolsSheet = true
                        } label: {
                            Image(systemName: "wrench.and.screwdriver")
                        }
                        .tint(GameTheme.text)
                        .disabled(model.isBusy)
                        .accessibilityLabel("Инструменты")

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

    private enum BottomTab: Hashable {
        case games
        case game
        case codes
        case tools
    }

    private var bottomTabBar: some View {
        HStack(spacing: 0) {
            bottomTabButton(.games, title: "Игры", systemImage: "list.bullet.rectangle")
            bottomTabButton(.game, title: "Игра", systemImage: "gamecontroller.fill")
            bottomTabButton(.codes, title: "Коды", systemImage: "list.bullet.rectangle.portrait")
            bottomTabButton(.tools, title: "Инструменты", systemImage: "wrench.and.screwdriver")
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background {
            Color(white: 0.05)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color(white: 0.15))
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func bottomTabButton(
        _ tab: BottomTab,
        title: String,
        systemImage: String
    ) -> some View {
        Button {
            selectTab(tab)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 24))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selectedTab == tab ? GameTheme.accent : Color.white.opacity(0.45))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var selectedTab: BottomTab? {
        if model.navigationPath.contains(.codes) {
            return .codes
        }
        switch model.selectedScreen {
        case .games:
            return .games
        case .game:
            return .game
        case .tools:
            return .tools
        case .team:
            return nil
        }
    }

    private func selectTab(_ tab: BottomTab) {
        switch tab {
        case .games:
            model.navigationPath.removeAll()
            model.selectedScreen = .games
        case .game:
            model.navigationPath.removeAll()
            model.selectedScreen = .game
        case .codes:
            if !model.navigationPath.contains(.codes) {
                model.navigationPath.append(.codes)
            }
        case .tools:
            model.navigationPath.removeAll()
            model.selectedScreen = .tools
        }
    }

    private func refreshCurrentTab() async {
        switch model.selectedScreen {
        case .games:
            await model.refreshGames()
        case .game:
            await model.refreshLevel()
        case .team:
            await model.refreshTeam()
        case .tools:
            break
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
