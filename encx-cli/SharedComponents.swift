import SwiftUI

struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(GameTheme.sectionHeader)
    }
}

extension View {
    func sectionPanel() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .dashboardPanelBackground()
    }

    func dashboardPanelBackground(cornerRadius: CGFloat = 12) -> some View {
        background(GameTheme.panel, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(GameTheme.border, lineWidth: 1)
            }
    }
}

struct GameActionRow: View {
    let game: GameInfo
    let badge: String
    let model: EncounterViewModel

    private var gameID: Int64 { Int64(game.id) }

    private var isActive: Bool {
        model.isGameActive(game)
    }

    private var isCurrentJoinedGame: Bool {
        guard model.selectedGameID == gameID,
              let current = model.currentModel,
              current.gameID == game.id else {
            return false
        }
        return !model.needsGameEntry(current)
    }

    var body: some View {
        Button {
            Task { await model.openGame(gameID) }
        } label: {
            HStack(spacing: 12) {
                GameRow(
                    game: game,
                    badge: badge,
                    isCurrentJoinedGame: isCurrentJoinedGame
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isActive && isCurrentJoinedGame ? "play.fill" : "arrow.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(isActive && isCurrentJoinedGame ? .green : GameTheme.accent, in: Circle())
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
        .accessibilityLabel(isActive && isCurrentJoinedGame ? "Открыть игру" : "Перейти к игре")
    }
}

struct DomainGameActionRow: View {
    let game: DomainGame
    let model: EncounterViewModel

    private var gameID: Int64 { Int64(game.id) }

    var body: some View {
        Button {
            Task { await model.openGame(gameID) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(game.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(GameTheme.text)
                    Text(verbatim: "#\(String(game.id))")
                        .font(.caption)
                        .foregroundStyle(GameTheme.muted)
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GameTheme.text)
                    .frame(width: 34, height: 34)
                    .background(GameTheme.inputBackground, in: Circle())
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
        .accessibilityLabel("Перейти к игре")
        .task(id: gameID) {
            await model.ensureGameModerationLoadedForUI(gameID: gameID)
        }
    }
}

struct GameRow: View {
    let game: GameInfo
    let badge: String
    var isCurrentJoinedGame = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(game.title)
                    .font(.headline)
                    .foregroundStyle(GameTheme.text)
                    .lineLimit(2)
                Spacer()
                GameBadge(
                    text: isCurrentJoinedGame ? "Открыта" : badge,
                    systemImage: isCurrentJoinedGame ? "play.fill" : nil,
                    tint: badge == "Активна" ? GameTheme.accent : .orange
                )
            }
            Text(verbatim: "#\(game.displayNumberText) / \(game.description.strippingHTML())")
                .font(.caption)
                .foregroundStyle(GameTheme.muted)
                .lineLimit(2)

            if let levelNumber = game.levelNumber {
                Label(levelCountLabel(levelNumber), systemImage: "flag.checkered")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(GameTheme.sectionHeader)
            }
        }
    }

    private func levelCountLabel(_ count: Int) -> String {
        "\(count) \(levelWord(count)) в игре"
    }

    private func levelWord(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod10 == 1 && mod100 != 11 {
            return "уровень"
        }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) {
            return "уровня"
        }
        return "уровней"
    }
}

struct GameBadge: View {
    let text: String
    var systemImage: String?
    var tint: Color = GameTheme.accent

    var body: some View {
        Label {
            Text(text)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
            }
        }
        .font(.caption.weight(.semibold))
        .labelStyle(.titleAndIcon)
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tint.opacity(0.16), in: Capsule())
    }
}

struct DashboardMetric: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = GameTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.headline)
                .foregroundStyle(GameTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(GameTheme.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct DashboardSettingsRow<Accessory: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color
    @ViewBuilder let accessory: Accessory

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color = GameTheme.accent,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GameTheme.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(GameTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)
            accessory
        }
        .padding(12)
        .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 10))
    }
}

extension DashboardSettingsRow where Accessory == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color = GameTheme.accent
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            tint: tint
        ) {
            EmptyView()
        }
    }
}

struct DomainChooserView: View {
    @Bindable var model: EncounterViewModel
    @Binding var isPresented: Bool
    @State private var customDomain = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle("Текущий домен")
                        DashboardSettingsRow(
                            title: model.settings.domain,
                            subtitle: "Список игр загружается для этого домена.",
                            systemImage: "globe",
                            tint: GameTheme.bonusTitle
                        )
                    }
                    .sectionPanel()

                    knownDomainsSection
                    customDomainSection
                }
                .padding()
            }
            .background(GameTheme.background)
            .navigationTitle("Домен")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GameTheme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        isPresented = false
                    }
                    .tint(GameTheme.text)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            customDomain = model.settings.domain
        }
        .onChange(of: model.settings.domain) { _, newDomain in
            customDomain = newDomain
        }
    }

    private var knownDomainsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Быстрый выбор")
            if model.knownDomains.isEmpty {
                Text("Сохранённых доменов пока нет.")
                    .font(.caption)
                    .foregroundStyle(GameTheme.muted)
            } else {
                ForEach(model.knownDomains, id: \.self) { domain in
                    Button {
                        Task {
                            await model.selectDomain(domain)
                            isPresented = false
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: domain == model.settings.domain ? "checkmark.circle.fill" : "globe")
                                .foregroundStyle(domain == model.settings.domain ? GameTheme.accent : GameTheme.bonusTitle)
                                .frame(width: 28, height: 28)
                            Text(domain)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(GameTheme.text)
                            Spacer()
                        }
                        .padding(12)
                        .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isBusy)
                }
            }
        }
        .sectionPanel()
    }

    private var customDomainSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Другой домен")
            HStack(spacing: 8) {
                TextField("Другой домен", text: $customDomain)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .onSubmit { applyCustomDomain() }
                    .foregroundStyle(GameTheme.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 10))

                Button("Применить") {
                    applyCustomDomain()
                }
                .buttonStyle(.borderedProminent)
                .tint(GameTheme.accent)
                .disabled(customDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
            }
        }
        .sectionPanel()
    }

    private func applyCustomDomain() {
        Task {
            await model.selectDomain(customDomain)
            isPresented = false
        }
    }
}

struct DetailBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text.isEmpty ? "Нет данных" : text)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}

struct StatusRow: View {
    let title: String
    let value: String
    let isDone: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isDone ? .green : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(isDone ? .green : .secondary)
            }
        }
    }
}
