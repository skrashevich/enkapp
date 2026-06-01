import SwiftUI
import Observation

struct AccountGamesView: View {
    @Bindable var model: EncounterViewModel
    @State private var customDomain = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                domainSection

                if !model.hasStoredSession && model.games.isEmpty && model.domainGames.isEmpty {
                    ContentUnavailableView {
                        Label("Войдите в аккаунт", systemImage: "person.crop.circle")
                    } description: {
                        Text("Откройте настройки и выполните вход, чтобы увидеть список игр.")
                    }
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
        .background(Color(.systemGroupedBackground))
        .refreshable {
            await model.refreshGames()
        }
        .onChange(of: model.settings.domain) { _, newDomain in
            customDomain = newDomain
        }
        .onAppear {
            customDomain = model.settings.domain
        }
    }

    private var domainSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Домен")

            Menu {
                ForEach(model.knownDomains, id: \.self) { domain in
                    Button {
                        Task { await model.selectDomain(domain) }
                    } label: {
                        if domain == model.settings.domain {
                            Label(domain, systemImage: "checkmark")
                        } else {
                            Text(domain)
                        }
                    }
                }
            } label: {
                HStack {
                    Label(model.settings.domain, systemImage: "globe")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(model.isBusy)

            HStack(spacing: 8) {
                TextField("Другой домен", text: $customDomain)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .onSubmit { applyCustomDomain() }

                Button("Применить") {
                    applyCustomDomain()
                }
                .buttonStyle(.bordered)
                .disabled(customDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
            }
        }
        .sectionPanel()
    }

    private var gamesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.games.isEmpty && model.domainGames.isEmpty {
                ContentUnavailableView("Нет списка игр", systemImage: "list.bullet.rectangle")
            }

            ForEach(model.activeGames) { game in
                GameActionRow(game: game, badge: "Активна", model: model)
            }

            ForEach(model.upcomingGames) { game in
                GameActionRow(game: game, badge: "Скоро", model: model)
            }

            if !filteredDomainGames.isEmpty {
                SectionTitle("Все игры домена")
                    .padding(.top, 6)

                ForEach(filteredDomainGames) { game in
                    DomainGameActionRow(game: game, model: model)
                }
            }
        }
        .sectionPanel()
    }

    private var filteredDomainGames: [DomainGame] {
        let ids = Set(model.games.map(\.id))
        return model.domainGames.filter { !ids.contains($0.id) }
    }

    private var loginHintSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Вы не вошли в аккаунт")
                        .font(.headline)
                    Text("Ниже показан общий список игр домена. Чтобы видеть свои активные игры и входить в них — выполните вход в настройках.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            NavigationLink {
                SettingsView(model: model)
            } label: {
                Label("Открыть настройки для входа", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(model.isBusy)
        }
        .sectionPanel()
    }

    private func applyCustomDomain() {
        Task { await model.selectDomain(customDomain) }
    }
}
