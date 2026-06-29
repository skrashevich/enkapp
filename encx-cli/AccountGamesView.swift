import SwiftUI
import Observation

struct AccountGamesView: View {
    @Bindable var model: EncounterViewModel
    @State private var showDomainChooser = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                headerSection

                if model.isMonitoringGame {
                    GameMonitoringBanner(model: model)
                }

                if !model.hasStoredSession && model.games.isEmpty && model.domainGames.isEmpty {
                    ContentUnavailableView {
                        Label("Войдите в аккаунт", systemImage: "person.crop.circle")
                    } description: {
                        Text("Откройте настройки и выполните вход, чтобы увидеть список игр.")
                    }
                    .foregroundStyle(GameTheme.text, GameTheme.muted)
                    .padding(.top, 20)
                } else {
                    if !model.hasStoredSession {
                        loginHintSection
                    }
                    gamesSection
                }
            }
            .padding()
        }
        .background(GameTheme.background)
        .sheet(isPresented: $showDomainChooser) {
            DomainChooserView(model: model, isPresented: $showDomainChooser)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .refreshable {
            await model.refreshGames()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.settings.domain)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(GameTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Text(model.hasStoredSession ? "Выберите игру или проверьте домен перед стартом." : "Можно смотреть игры домена, для участия нужен вход.")
                        .font(.subheadline)
                        .foregroundStyle(GameTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    showDomainChooser = true
                } label: {
                    Image(systemName: "scope")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(GameTheme.sectionHeader)
                        .frame(width: 44, height: 44)
                        .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(model.isBusy)
                .accessibilityLabel("Сменить домен")
            }

            HStack(spacing: 10) {
                DashboardMetric(
                    title: "Активные",
                    value: "\(model.activeGames.count)",
                    systemImage: "bolt.fill",
                    tint: GameTheme.accent
                )
                DashboardMetric(
                    title: "Скоро",
                    value: "\(model.upcomingGames.count)",
                    systemImage: "clock.fill",
                    tint: .orange
                )
                if !filteredDomainGames.isEmpty {
                    DashboardMetric(
                        title: "Прочие",
                        value: "\(filteredDomainGames.count)",
                        systemImage: "globe",
                        tint: GameTheme.bonusTitle
                    )
                }
            }
        }
        .sectionPanel()
    }

    private var gamesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.games.isEmpty && model.domainGames.isEmpty {
                ContentUnavailableView("Нет списка игр", systemImage: "list.bullet.rectangle")
                    .foregroundStyle(GameTheme.text, GameTheme.muted)
            }

            if let currentGame = currentActiveGame {
                SectionTitle("Текущая игра")
                GameActionRow(game: currentGame, badge: "Активна", model: model)
                    .padding(12)
                    .background(GameTheme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(GameTheme.accent.opacity(0.65), lineWidth: 1)
                    }
            }

            if !visibleActiveGames.isEmpty {
                SectionTitle("Активные")
                    .padding(.top, currentActiveGame == nil ? 0 : 6)
                ForEach(visibleActiveGames) { game in
                    GameActionRow(game: game, badge: "Активна", model: model)
                        .padding(12)
                        .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 12))
                }
            }

            if !model.upcomingGames.isEmpty {
                SectionTitle("Скоро")
                    .padding(.top, model.activeGames.isEmpty ? 0 : 6)
                ForEach(model.upcomingGames) { game in
                    GameActionRow(game: game, badge: "Скоро", model: model)
                        .padding(12)
                        .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 12))
                }
            }

            if !filteredDomainGames.isEmpty {
                SectionTitle("Все игры домена")
                    .padding(.top, 6)

                ForEach(filteredDomainGames) { game in
                    DomainGameActionRow(game: game, model: model)
                        .padding(12)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .sectionPanel()
    }

    private var filteredDomainGames: [DomainGame] {
        let ids = Set(model.games.map(\.id))
        return model.domainGames.filter { !ids.contains($0.id) }
    }

    private var currentActiveGame: GameInfo? {
        guard let selectedGameID = model.selectedGameID else { return nil }
        return model.activeGames.first { $0.id == Int(selectedGameID) }
    }

    private var visibleActiveGames: [GameInfo] {
        guard let currentActiveGame else { return model.activeGames }
        return model.activeGames.filter { $0.id != currentActiveGame.id }
    }

    private var loginHintSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Вы не вошли в аккаунт")
                        .font(.headline)
                        .foregroundStyle(GameTheme.text)
                    Text("Ниже показан общий список игр домена. Чтобы видеть свои активные игры и входить в них — выполните вход в настройках.")
                        .font(.caption)
                        .foregroundStyle(GameTheme.muted)
                }
                Spacer()
            }

            NavigationLink {
                SettingsView(model: model)
            } label: {
                Label("Открыть настройки для входа", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .tint(GameTheme.accent)
            .disabled(model.isBusy)
        }
        .sectionPanel()
    }
}
