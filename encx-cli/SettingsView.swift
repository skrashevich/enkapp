import SwiftUI
import UIKit

private enum PermissionCheckStatus: Equatable {
    case pending
    case granted
    case denied
}

private func openAppSettings(_ openURL: OpenURLAction) {
    if let url = URL(string: UIApplication.openSettingsURLString) {
        openURL(url)
    }
}

// MARK: - Shared building blocks

/// Hairline between rows of a settings group, inset past the leading icon so it
/// starts under the row title.
private struct SettingsRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(white: 0.13))
            .frame(height: 1)
            .padding(.leading, 48)
    }
}

/// One line of a settings group: icon, title, optional subline, optional trailing
/// value and chevron.
private struct SettingsRowLabel: View {
    let systemImage: String
    var tint: Color = GameTheme.accent
    let title: String
    var value: String? = nil
    var subtitle: String? = nil
    var showsChevron = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(GameTheme.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            if let value {
                Text(value)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(width: 20, height: 20)
            }
        }
        .padding(14)
        .contentShape(Rectangle())
    }
}

/// Row that both toggles a setting inline and pushes the screen with the rest of
/// that feature's options.
private struct SettingsToggleNavRow<Destination: View>: View {
    let systemImage: String
    let tint: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let destination: Destination

    init(
        systemImage: String,
        tint: Color,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        destination: Destination
    ) {
        self.systemImage = systemImage
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
        self.destination = destination
    }

    var body: some View {
        HStack(spacing: 4) {
            NavigationLink {
                destination
            } label: {
                SettingsRowLabel(
                    systemImage: systemImage,
                    tint: tint,
                    title: title,
                    subtitle: subtitle
                )
            }
            .buttonStyle(.plain)

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .tint(GameTheme.accent)
                .padding(.trailing, 14)
        }
    }
}

/// Toggle row used inside the pushed sub-screens; identical to the row the long
/// settings scroll used before the split.
private struct SettingToggleRow: View {
    let title: String
    var subtitle: String? = nil
    let systemImage: String
    var tint: Color = GameTheme.accent
    @Binding var isOn: Bool

    var body: some View {
        DashboardSettingsRow(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            tint: tint
        ) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .tint(GameTheme.accent)
        }
    }
}

/// Common chrome for every settings sub-screen.
private struct SettingsSubScreen<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding()
        }
        .background(GameTheme.background)
        .scrollContentBackground(.hidden)
        .preferredColorScheme(.dark)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(GameTheme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

// MARK: - Settings root

struct SettingsView: View {
    @Bindable var model: EncounterViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showDomainChooser = false
    @State private var showOnboarding = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                accountCard
                inGameGroup
                otherGroup
                keychainFootnote
            }
            .padding(16)
        }
        .background(GameTheme.background)
        .scrollContentBackground(.hidden)
        .preferredColorScheme(.dark)
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "arrow.backward")
                        .font(.system(size: 17, weight: .semibold))
                }
                .tint(GameTheme.text)
                .accessibilityLabel("Назад")
            }
        }
        .toolbarBackground(GameTheme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showDomainChooser) {
            DomainChooserView(model: model, isPresented: $showDomainChooser)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(model: model) {
                showOnboarding = false
            }
        }
        .onChange(of: model.agentSettings) { _, _ in
            model.persistAgentSettings()
        }
        .onChange(of: model.settings.liveActivityEnabled) { _, enabled in
            // The toggle now lives on this screen, so the permission prompt has to
            // be requested from here too — not only from the Live Activity sub-screen.
            if enabled {
                Task { await model.requestNotificationAuthorizationIfNeeded() }
            }
        }
    }

    // MARK: Account card

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.hasStoredSession {
                signedInHeader
                signedInActions
            } else {
                signedOutHeader
                loginFields
            }

            if !model.statusMessage.isEmpty {
                Label(model.statusMessage, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(GameTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(GameTheme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color(white: 0.15), lineWidth: 1)
        }
    }

    private var signedInHeader: some View {
        HStack(spacing: 14) {
            Text(loginInitials)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(GameTheme.accent)
                .frame(width: 48, height: 48)
                .background(
                    GameTheme.accent.opacity(0.18),
                    in: RoundedRectangle(cornerRadius: 14)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(displayLogin)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(GameTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(model.settings.domain) · вход выполнен")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(GameTheme.accent)
        }
    }

    private var signedOutHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(GameTheme.accent)
                .frame(width: 48, height: 48)
                .background(
                    GameTheme.accent.opacity(0.18),
                    in: RoundedRectangle(cornerRadius: 14)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Вход в аккаунт")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(GameTheme.text)
                Text("\(model.settings.domain) · вход не выполнен")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)
        }
    }

    private var signedInActions: some View {
        HStack(spacing: 10) {
            domainChangeButton

            Button {
                Task { await model.logoutAction() }
            } label: {
                Text("Выйти")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)
        }
    }

    private var domainChangeButton: some View {
        Button {
            showDomainChooser = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GameTheme.bonusTitle)
                Text("Сменить домен")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GameTheme.text)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
    }

    @ViewBuilder
    private var loginFields: some View {
        TextField("Логин", text: $model.login)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .foregroundStyle(GameTheme.text)
            .padding(12)
            .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 10))

        SecureField("Пароль", text: $model.password)
            .foregroundStyle(GameTheme.text)
            .padding(12)
            .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 10))

        Button {
            Task {
                if await model.loginAction() {
                    dismiss()
                }
            }
        } label: {
            Label("Войти", systemImage: "person.crop.circle.badge.checkmark")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(GameTheme.accent)
        .disabled(model.login.isEmpty || model.password.isEmpty || model.isBusy)

        domainChangeButton
    }

    private var displayLogin: String {
        let trimmed = model.login.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Вход выполнен" : trimmed
    }

    private var loginInitials: String {
        let trimmed = model.login.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "EN" }
        return String(trimmed.prefix(2)).uppercased()
    }

    // MARK: Groups

    private var inGameGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("В игре")

            VStack(spacing: 0) {
                NavigationLink {
                    SettingsNotificationsView(model: model)
                } label: {
                    SettingsRowLabel(
                        systemImage: "bell.badge",
                        title: "Оповещения",
                        value: notificationsSummary
                    )
                }
                .buttonStyle(.plain)

                SettingsRowDivider()

                SettingsToggleNavRow(
                    systemImage: "rectangle.on.rectangle",
                    tint: GameTheme.bonusTitle,
                    title: "Live Activity",
                    subtitle: liveActivitySummary,
                    isOn: $model.settings.liveActivityEnabled,
                    destination: SettingsLiveActivityView(model: model)
                )

                SettingsRowDivider()

                SettingsToggleNavRow(
                    systemImage: "sparkles",
                    tint: GameTheme.bonusTitle,
                    title: "Ассистент",
                    subtitle: assistantSummary,
                    isOn: $model.agentSettings.enabled,
                    destination: SettingsAssistantView(model: model)
                )
            }
            .background(GameTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var otherGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Прочее")

            VStack(spacing: 0) {
                NavigationLink {
                    SettingsConnectionView(model: model)
                } label: {
                    SettingsRowLabel(
                        systemImage: "network",
                        title: "Подключение",
                        value: connectionSummary
                    )
                }
                .buttonStyle(.plain)

                SettingsRowDivider()

                NavigationLink {
                    SettingsDebugView(model: model)
                } label: {
                    SettingsRowLabel(
                        systemImage: "ant",
                        tint: .orange,
                        title: "Отладка и HAR",
                        value: harSummary
                    )
                }
                .buttonStyle(.plain)

                SettingsRowDivider()

                Button {
                    showOnboarding = true
                } label: {
                    SettingsRowLabel(
                        systemImage: "arrow.clockwise.circle",
                        tint: GameTheme.sectionHeader,
                        title: "Пройти настройку заново"
                    )
                }
                .buttonStyle(.plain)
                .disabled(model.isBusy)

                SettingsRowDivider()

                NavigationLink {
                    SettingsAboutView(model: model, appVersion: appVersion)
                } label: {
                    SettingsRowLabel(
                        systemImage: "info.circle",
                        tint: GameTheme.bonusTitle,
                        title: "О приложении",
                        value: appVersion
                    )
                }
                .buttonStyle(.plain)
            }
            .background(GameTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var keychainFootnote: some View {
        Text("Пароль и ключи хранятся в Keychain устройства.")
            .font(.system(size: 12))
            .lineSpacing(5.4)
            .foregroundStyle(.white.opacity(0.4))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Row summaries

    private var notificationsSummary: String {
        switch (model.settings.pushOnNewLevel, model.settings.pushOnNewHint) {
        case (true, true): return "Уровень и подсказки"
        case (true, false): return "Уровень"
        case (false, true): return "Подсказки"
        case (false, false): return "Выключены"
        }
    }

    private var liveActivitySummary: String {
        guard model.settings.liveActivityEnabled else { return "Выключена" }
        let count = enabledLiveActivityFieldCount
        return "Включена · \(count) \(Self.fieldsWord(count)) на экране блокировки"
    }

    private var enabledLiveActivityFieldCount: Int {
        let display = model.settings.liveActivityDisplay
        return [
            display.showGameTitle,
            display.showLevel,
            display.showTeam,
            display.showProgress,
            display.showQueue,
            display.showCodes,
            display.showHints,
            display.showStatus,
        ].filter { $0 }.count
    }

    private static func fieldsWord(_ count: Int) -> String {
        let lastTwo = count % 100
        if lastTwo >= 11 && lastTwo <= 14 { return "полей" }
        switch count % 10 {
        case 1: return "поле"
        case 2, 3, 4: return "поля"
        default: return "полей"
        }
    }

    private var assistantSummary: String {
        guard model.agentSettings.enabled else { return "Выключен" }
        let provider = model.agentSettings.provider.title
        let agentModel = model.agentSettings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        return agentModel.isEmpty
            ? "Включён · \(provider)"
            : "Включён · \(provider) · \(agentModel)"
    }

    private var connectionSummary: String {
        let scheme = model.settings.useHTTP ? "HTTP" : "HTTPS"
        let tls = model.settings.insecureTLS ? "без проверки TLS" : "TLS"
        return "\(scheme) · \(tls)"
    }

    private var harSummary: String {
        model.settings.harCaptureEnabled ? "Вкл" : "Выкл"
    }
}

// MARK: - Оповещения

private struct SettingsNotificationsView: View {
    @Bindable var model: EncounterViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationDenied = false

    var body: some View {
        SettingsSubScreen(title: "Оповещения") {
            VStack(alignment: .leading, spacing: 12) {
                SettingToggleRow(
                    title: "Новый уровень",
                    subtitle: "Локальное уведомление при смене уровня.",
                    systemImage: "flag.checkered",
                    isOn: $model.settings.pushOnNewLevel
                )
                SettingToggleRow(
                    title: "Новая подсказка",
                    subtitle: "Оповещение, когда появляется текст подсказки.",
                    systemImage: "lightbulb.fill",
                    tint: GameTheme.sectionHeader,
                    isOn: $model.settings.pushOnNewHint
                )

                if notificationDenied {
                    Button("Открыть настройки iOS") {
                        openAppSettings(openURL)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }

                Text(notificationDenied ? "Разрешите уведомления в настройках iOS, чтобы получать оповещения вне приложения." : "Работают в фоне, пока открыта игра.")
                    .font(.caption)
                    .foregroundStyle(GameTheme.muted)
            }
            .sectionPanel()
        }
        .task {
            await refreshNotificationStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refreshNotificationStatus() }
            }
        }
        .onChange(of: model.settings.pushOnNewLevel) { _, enabled in
            if enabled {
                Task {
                    await model.requestNotificationAuthorizationIfNeeded()
                    await refreshNotificationStatus()
                }
            }
        }
        .onChange(of: model.settings.pushOnNewHint) { _, enabled in
            if enabled {
                Task {
                    await model.requestNotificationAuthorizationIfNeeded()
                    await refreshNotificationStatus()
                }
            }
        }
    }

    private func refreshNotificationStatus() async {
        let status = await GameEventNotificationService.shared.authorizationStatus()
        notificationDenied = status == .denied
    }
}

// MARK: - Live Activity

private struct SettingsLiveActivityView: View {
    @Bindable var model: EncounterViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var liveActivitySystemStatus: PermissionCheckStatus = .pending
    @State private var liveActivityPushStatus: PermissionCheckStatus = .pending

    var body: some View {
        SettingsSubScreen(title: "Live Activity") {
            VStack(alignment: .leading, spacing: 12) {
                SettingToggleRow(
                    title: "Live Activity",
                    subtitle: "Игра на экране блокировки и в Dynamic Island.",
                    systemImage: "rectangle.on.rectangle",
                    isOn: $model.settings.liveActivityEnabled
                )

                if model.settings.liveActivityEnabled {
                    liveActivityPermissionRow(
                        title: "Разрешение Live Activity",
                        status: liveActivitySystemStatus
                    ) {
                        Task { await requestLiveActivityPermission() }
                    }
                    liveActivityPermissionRow(
                        title: "Уведомления",
                        status: liveActivityPushStatus
                    ) {
                        Task { await requestPushPermission() }
                    }

                    if liveActivityPermissionsNeedSettings {
                        Button("Открыть настройки iOS") {
                            openAppSettings(openURL)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }

                    Text(liveActivityFooterText)
                        .font(.caption)
                        .foregroundStyle(GameTheme.muted)

                    SectionTitle("На экране блокировки")
                        .padding(.top, 6)
                    liveActivityToggle("Название игры", keyPath: \.showGameTitle)
                    liveActivityToggle("Уровень", keyPath: \.showLevel)
                    liveActivityToggle("Команда", keyPath: \.showTeam)
                    liveActivityToggle("Секторы и бонусы", keyPath: \.showProgress)
                    liveActivityToggle("Очередь кодов", keyPath: \.showQueue)
                    liveActivityToggle("Пробитые коды", keyPath: \.showCodes)
                    liveActivityToggle("Подсказки", keyPath: \.showHints)
                    liveActivityToggle("Статус", keyPath: \.showStatus)
                }
            }
            .sectionPanel()
        }
        .task {
            if model.settings.liveActivityEnabled {
                liveActivitySystemStatus = .pending
                liveActivityPushStatus = .pending
                await model.requestNotificationAuthorizationIfNeeded()
            }
            await refreshLiveActivityPermissions()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refreshLiveActivityPermissions() }
            }
        }
        .onChange(of: model.settings.liveActivityEnabled) { _, enabled in
            if enabled {
                liveActivitySystemStatus = .pending
                liveActivityPushStatus = .pending
                Task {
                    await model.requestNotificationAuthorizationIfNeeded()
                    await refreshLiveActivityPermissions()
                }
            } else {
                Task { await refreshLiveActivityPermissions() }
            }
        }
    }

    @ViewBuilder
    private func liveActivityPermissionRow(
        title: String,
        status: PermissionCheckStatus,
        onRequest: @escaping () -> Void
    ) -> some View {
        let label = HStack {
            Text(title)
            Spacer()
            switch status {
            case .pending:
                ProgressView()
                    .controlSize(.small)
            case .granted:
                Label("Разрешено", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .denied:
                Label("Нет доступа", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .font(.subheadline)
        .foregroundStyle(GameTheme.text)
        .padding(12)
        .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 10))

        if status == .denied {
            Button(action: onRequest) {
                label
            }
            .buttonStyle(.plain)
        } else {
            label
        }
    }

    private func liveActivityToggle(
        _ title: String,
        keyPath: WritableKeyPath<LiveActivityDisplayOptions, Bool>
    ) -> some View {
        SettingToggleRow(
            title: title,
            systemImage: liveActivityIcon(for: title),
            isOn: Binding(
                get: { model.settings.liveActivityDisplay[keyPath: keyPath] },
                set: { model.settings.liveActivityDisplay[keyPath: keyPath] = $0 }
            )
        )
    }

    private func liveActivityIcon(for title: String) -> String {
        switch title {
        case "Название игры": return "textformat"
        case "Уровень": return "flag.checkered"
        case "Команда": return "person.3.fill"
        case "Секторы и бонусы": return "checklist"
        case "Очередь кодов": return "tray.full"
        case "Пробитые коды": return "checkmark.seal"
        case "Подсказки": return "lightbulb.fill"
        case "Статус": return "waveform.path.ecg"
        default: return "rectangle.on.rectangle"
        }
    }

    private var liveActivityPermissionsNeedSettings: Bool {
        model.settings.liveActivityEnabled
            && (liveActivitySystemStatus == .denied || liveActivityPushStatus == .denied)
    }

    private var liveActivityPermissionTapHint: String {
        " Нажмите на строку с «Нет доступа», чтобы запросить разрешение."
    }

    private var liveActivityFooterText: String {
        let systemDenied = liveActivitySystemStatus == .denied
        let pushDenied = liveActivityPushStatus == .denied
        switch (systemDenied, pushDenied) {
        case (true, true):
            return "Разрешите Live Activity и уведомления в настройках iOS, чтобы видеть игру на экране блокировки и получать обновления в фоне."
                + liveActivityPermissionTapHint
        case (true, false):
            return "Разрешите отображение Live Activity в настройках iOS, чтобы видеть игру на экране блокировки и в Dynamic Island."
                + liveActivityPermissionTapHint
        case (false, true):
            return "Разрешите уведомления в настройках iOS, чтобы приложение могло обновлять Live Activity в фоне."
                + liveActivityPermissionTapHint
        default:
            return "Показывает игру на экране блокировки и в Dynamic Island."
        }
    }

    private func requestPushPermission() async {
        liveActivityPushStatus = .pending
        let granted = await GameEventNotificationService.shared.requestAuthorizationIfNeeded()
        await refreshLiveActivityPermissions()
        if !granted {
            let status = await GameEventNotificationService.shared.authorizationStatus()
            if status == .denied {
                openAppSettings(openURL)
            }
        }
    }

    private func requestLiveActivityPermission() async {
        liveActivitySystemStatus = .pending
        await model.applyLiveActivitySetting()
        await refreshLiveActivityPermissions()
        guard liveActivitySystemStatus == .denied else { return }
        openAppSettings(openURL)
    }

    private func refreshLiveActivityPermissions() async {
        guard model.settings.liveActivityEnabled else {
            liveActivitySystemStatus = .pending
            liveActivityPushStatus = .pending
            return
        }

        liveActivitySystemStatus = QueueLiveActivityManager.areActivitiesEnabled ? .granted : .denied
        let status = await GameEventNotificationService.shared.authorizationStatus()
        liveActivityPushStatus = GameEventNotificationService.isAuthorized(status) ? .granted : .denied
    }
}

// MARK: - Ассистент

private struct SettingsAssistantView: View {
    @Bindable var model: EncounterViewModel
    @Environment(\.openURL) private var openURL
    @State private var agentAPIKeyDraft = ""
    @State private var agentKeyStored = false
    @State private var agentKeyStatus: String?
    @State private var agentApprovalTapCount = 0
    @State private var codexSignIn = CodexSignInModel()

    var body: some View {
        SettingsSubScreen(title: "Ассистент") {
            VStack(alignment: .leading, spacing: 12) {
                SettingToggleRow(
                    title: "Ассистент в игре",
                    subtitle: "Чат с ИИ, который видит движок и умеет им пользоваться.",
                    systemImage: "sparkles",
                    tint: GameTheme.bonusTitle,
                    isOn: $model.agentSettings.enabled
                )

                if model.agentSettings.enabled {
                    agentProviderRows
                    if model.agentSettings.provider.usesSubscriptionLogin {
                        agentChatGPTRows
                    } else {
                        agentKeyRows
                    }
                    agentPolicyRows
                }
            }
            .sectionPanel()
        }
        .onAppear { refreshAgentCredentialState() }
        .onDisappear {
            // Without this the login keeps polling OpenAI for a quarter of an hour
            // after the screen is gone, and an approval granted in that window is
            // discarded instead of stored.
            codexSignIn.cancel()
        }
        .onChange(of: codexSignIn.phase) { _, phase in
            // A completed sign-in writes a new credential, so the cached session
            // built on the old one has to go.
            if case .signedIn = phase {
                agentCredentialsChanged()
            } else {
                refreshAgentCredentialState()
            }
            // The code is useless without the page that accepts it, so open it as
            // soon as OpenAI hands the code out, and put it on the clipboard so
            // the player does not have to retype it from memory.
            if case .awaitingApproval(let userCode, let verifyURL) = phase {
                UIPasteboard.general.string = userCode
                if let verifyURL {
                    openURL(verifyURL)
                }
            }
        }
        .onChange(of: model.agentSettings.provider) { _, _ in
            refreshAgentCredentialState()
            agentKeyStatus = nil
        }
    }

    @ViewBuilder
    private var agentProviderRows: some View {
        Picker("Провайдер", selection: providerBinding) {
            ForEach(AgentProvider.allCases) { provider in
                Text(provider.title).tag(provider)
            }
        }
        .pickerStyle(.segmented)

        agentProviderDescription

        TextField("Модель", text: $model.agentSettings.model)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .foregroundStyle(GameTheme.text)
            .padding(12)
            .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 10))

        if model.agentSettings.provider.acceptsCustomEndpoint {
            TextField("Endpoint API (необязательно)", text: $model.agentSettings.apiBase)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .foregroundStyle(GameTheme.text)
                .padding(12)
                .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 10))

            Text("Endpoint должен обслуживать /chat/completions. Шлюзы только с Responses API (например api.openmodel.ai) отвечают 404.")
                .font(.caption)
                .foregroundStyle(GameTheme.muted)
        }
    }

    /// Explains the picked provider and, when it needs an account first, links to
    /// the sign-up page.
    @ViewBuilder
    private var agentProviderDescription: some View {
        let provider = model.agentSettings.provider
        let explanation = provider.explanation
        if !explanation.isEmpty || provider.signupURL != nil {
            VStack(alignment: .leading, spacing: 4) {
                if !explanation.isEmpty {
                    Text(explanation)
                        .font(.caption)
                        .foregroundStyle(GameTheme.muted)
                }
                if let signupURL = provider.signupURL {
                    Link("Зарегистрироваться и получить ключ", destination: signupURL)
                        .font(.caption.weight(.semibold))
                        .tint(GameTheme.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var agentChatGPTRows: some View {
        switch codexSignIn.phase {
        case .awaitingApproval(let userCode, let verifyURL):
            VStack(alignment: .leading, spacing: 8) {
                Text("Код подтверждения")
                    .font(.caption)
                    .foregroundStyle(GameTheme.muted)
                Text(userCode)
                    .font(.title2.weight(.bold).monospaced())
                    .foregroundStyle(GameTheme.text)
                    .textSelection(.enabled)
                Text("Страница входа уже открыта, код скопирован в буфер обмена. Введите его и подтвердите доступ — приложение ждёт до 15 минут.")
                    .font(.caption)
                    .foregroundStyle(GameTheme.muted)
                HStack(spacing: 10) {
                    if let verifyURL {
                        Button("Открыть страницу снова") { openURL(verifyURL) }
                            .buttonStyle(.borderedProminent)
                            .tint(GameTheme.accent)
                    }
                    Button("Отмена", role: .cancel) { codexSignIn.cancel() }
                        .buttonStyle(.bordered)
                }
                ProgressView()
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default:
            HStack(spacing: 10) {
                Button(agentKeyStored ? "Войти заново" : "Войти через ChatGPT") {
                    codexSignIn.start()
                }
                .buttonStyle(.borderedProminent)
                .tint(GameTheme.accent)
                .disabled(codexSignIn.isBusy)

                if agentKeyStored {
                    Button("Выйти", role: .destructive) {
                        codexSignIn.signOut()
                        agentCredentialsChanged()
                        agentKeyStatus = "Вход в ChatGPT отменён."
                    }
                    .buttonStyle(.bordered)
                }
            }

            Text(codexStatusText)
                .font(.caption)
                .foregroundStyle(codexStatusIsError ? .red : GameTheme.muted)
        }
    }

    private var codexStatusText: String {
        switch codexSignIn.phase {
        case .failed(let message): return message
        case .signedIn: return "Вход выполнен, подписка ChatGPT подключена."
        default:
            return agentKeyStored
                ? "Подписка ChatGPT подключена."
                : "Используется подписка ChatGPT вместо ключа API. Ключ не нужен."
        }
    }

    private var codexStatusIsError: Bool {
        if case .failed = codexSignIn.phase { return true }
        return false
    }

    @ViewBuilder
    private var agentKeyRows: some View {
        SecureField(agentKeyPlaceholder, text: $agentAPIKeyDraft)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .foregroundStyle(GameTheme.text)
            .padding(12)
            .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 10))

        HStack(spacing: 10) {
            Button("Сохранить ключ") { saveAgentKey() }
                .buttonStyle(.borderedProminent)
                .tint(GameTheme.accent)
                .disabled(agentAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if agentKeyStored {
                Button("Удалить ключ", role: .destructive) { deleteAgentKey() }
                    .buttonStyle(.bordered)
            }
        }

        if let agentKeyStatus {
            Text(agentKeyStatus)
                .font(.caption)
                .foregroundStyle(GameTheme.muted)
        }
    }

    @ViewBuilder
    private var agentPolicyRows: some View {
        // Buttons also receive taps on the selected option, unlike a Picker.
        HStack(spacing: 4) {
            ForEach(AgentAccessPolicy.allCases.filter {
                $0 != .full || model.agentSettings.fullAccessUnlocked
            }) { policy in
                Button {
                    if policy == .approve && !model.agentSettings.fullAccessUnlocked {
                        agentApprovalTapCount += 1
                        if agentApprovalTapCount >= 10 {
                            model.agentSettings.fullAccessUnlocked = true
                        }
                    }
                    model.agentSettings.policy = policy
                } label: {
                    Text(policy.title)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(GameTheme.text)
                        .background(
                            model.agentSettings.policy == policy ? GameTheme.accent : .clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.agentSettings.policy == policy ? .isSelected : [])
            }
        }
        .padding(4)
        .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Доступ к движку")

        Text(model.agentSettings.policy.explanation)
            .font(.caption)
            .foregroundStyle(model.agentSettings.policy.actsWithoutAsking ? .orange : GameTheme.muted)

        SettingToggleRow(
            title: "Поиск в интернете",
            subtitle: "DuckDuckGo и чтение страниц. Запросы уходят в поисковик.",
            systemImage: "globe",
            tint: GameTheme.bonusTitle,
            isOn: $model.agentSettings.webToolsEnabled
        )

        SettingToggleRow(
            title: "Геолокация устройства",
            subtitle: "Ассистент может узнать текущие GPS-координаты — например, чтобы подсказать дорогу. "
                + "iOS спросит разрешение при первом использовании; координаты уходят выбранному провайдеру.",
            systemImage: "location.fill",
            tint: GameTheme.accent,
            isOn: $model.agentSettings.locationToolsEnabled
        )

        HStack {
            Text("Шагов на ответ")
                .font(.subheadline)
                .foregroundStyle(GameTheme.text)
            Spacer()
            TextField("100", value: $model.agentSettings.maxSteps, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .foregroundStyle(GameTheme.text)
                .padding(10)
                .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 10))
        }

        Text("Сколько обращений к движку ассистент может сделать, отвечая на один вопрос. "
            + "0 — без ограничения; длинные задачи вроде перебора кодов требуют много шагов. "
            + "Остановить можно кнопкой в чате.")
            .font(.caption)
            .foregroundStyle(GameTheme.muted)

        Text("Ключ или токен ChatGPT хранится в Keychain устройства. Запросы уходят напрямую выбранному провайдеру — данные игры покидают устройство вместе с ними.")
            .font(.caption)
            .foregroundStyle(.orange)
    }

    private var providerBinding: Binding<AgentProvider> {
        Binding(
            get: { model.agentSettings.provider },
            set: { model.agentSettings.applyProvider($0) }
        )
    }

    private var agentKeyPlaceholder: String {
        agentKeyStored ? "Ключ API сохранён — введите новый, чтобы заменить" : "Ключ API"
    }

    private func saveAgentKey() {
        do {
            try AgentCredentialsStore.save(apiKey: agentAPIKeyDraft)
            agentAPIKeyDraft = ""
            agentCredentialsChanged()
            agentKeyStatus = agentKeyStored ? "Ключ сохранён в Keychain." : "Ключ не сохранён."
        } catch {
            agentKeyStatus = "Не удалось сохранить ключ: \(error.localizedDescription)"
        }
    }

    private func deleteAgentKey() {
        AgentCredentialsStore.delete()
        agentCredentialsChanged()
        agentKeyStatus = "Ключ удалён."
    }

    /// `agentKeyStored` tracks whichever credential the selected provider needs.
    private func refreshAgentCredentialState() {
        agentKeyStored = model.agentSettings.hasCredentials
    }

    /// Call after writing or clearing a credential.
    ///
    /// The credential is read from the Keychain when the agent session is built,
    /// so replacing it has to drop the cached session — otherwise a fresh key
    /// keeps failing against the revoked one, with no way out but restarting the
    /// app. Merely opening this screen must not do that: it would kill a turn
    /// that is still running.
    private func agentCredentialsChanged() {
        refreshAgentCredentialState()
        model.invalidateAgentSession()
    }
}

// MARK: - Подключение

private struct SettingsConnectionView: View {
    @Bindable var model: EncounterViewModel

    var body: some View {
        SettingsSubScreen(title: "Подключение") {
            VStack(alignment: .leading, spacing: 12) {
                SettingToggleRow(
                    title: "Использовать HTTP",
                    subtitle: "Для старых или нестандартных доменов Encounter.",
                    systemImage: "network",
                    isOn: $model.settings.useHTTP
                )
                SettingToggleRow(
                    title: "Отключить проверку TLS",
                    subtitle: "Только если сертификат домена сломан.",
                    systemImage: "lock.trianglebadge.exclamationmark",
                    tint: .orange,
                    isOn: $model.settings.insecureTLS
                )
            }
            .sectionPanel()
        }
    }
}

// MARK: - Отладка и HAR

private struct SettingsDebugView: View {
    @Bindable var model: EncounterViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showHARShareSheet = false
    @State private var harShareURL: URL?
    @State private var harExportError: String?

    var body: some View {
        SettingsSubScreen(title: "Отладка и HAR") {
            VStack(alignment: .leading, spacing: 12) {
                SettingToggleRow(
                    title: "Запись HAR",
                    subtitle: "Дамп HTTP-запросов к серверу Encounter.",
                    systemImage: "doc.text.magnifyingglass",
                    tint: .orange,
                    isOn: $model.settings.harRecordingEnabled
                )
                SettingToggleRow(
                    title: "Отправлять HAR разработчику",
                    subtitle: "Автоматически отправляет сетевые взаимодействия на сервер диагностики.",
                    systemImage: "arrow.up.doc",
                    tint: .orange,
                    isOn: $model.settings.harUploadEnabled
                )

                if model.settings.harUploadEnabled {
                    TextField("Endpoint HAR", text: $model.settings.harUploadEndpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .foregroundStyle(GameTheme.text)
                        .padding(12)
                        .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 10))
                    Text("Внимание: включение этой опции позволит разработчику приложения видеть всю информацию во взаимодействии приложения с движком, включая чувствительные данные вроде кодов, и потенциально авторизоваться под вашей учетной записью на движке в течение непродолжительного времени. Используйте только для отладки проблем при прямом взаимодействии с автором приложения либо при запуске собственных тестовых игр, утечка данных из которых некритична. Это поможет в разработке приложения и смежных проектов вроде encx-cli.")
                        .font(.caption)
                        .foregroundStyle(.red)
                    if !model.harUploadStatusMessage.isEmpty {
                        Label(model.harUploadStatusMessage, systemImage: "arrow.up.doc")
                            .font(.caption)
                            .foregroundStyle(GameTheme.muted)
                    }
                }

                if model.settings.harCaptureEnabled {
                    DashboardSettingsRow(
                        title: "Записей",
                        subtitle: "Пароли скрываются, cookies и коды остаются в файле.",
                        systemImage: "tray.full",
                        tint: .orange
                    ) {
                        Text("\(model.harEntryCount)")
                            .font(.headline)
                            .foregroundStyle(GameTheme.text)
                    }

                    HStack(spacing: 10) {
                        Button {
                            exportHAR()
                        } label: {
                            Label("Экспорт HAR", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(GameTheme.accent)
                        .disabled(model.harEntryCount == 0 || model.isBusy)

                        Button(role: .destructive) {
                            model.clearHARCapture()
                        } label: {
                            Label("Очистить", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.harEntryCount == 0 || model.isBusy)
                    }
                }

                // Only appears when the engine sent something we could not decode, so a lossy
                // decode leaves a visible trace instead of quietly hiding data.
                if model.decodeDropCount > 0 {
                    DashboardSettingsRow(
                        title: "Пропущено",
                        subtitle: "Движок прислал данные, которые не удалось разобрать.",
                        systemImage: "exclamationmark.triangle",
                        tint: .red
                    ) {
                        Text("\(model.decodeDropCount)")
                            .font(.headline)
                            .foregroundStyle(GameTheme.text)
                    }
                }

                if let harExportError {
                    Label(harExportError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .sectionPanel()
        }
        .sheet(isPresented: $showHARShareSheet, onDismiss: {
            if let harShareURL {
                try? FileManager.default.removeItem(at: harShareURL)
            }
            harShareURL = nil
        }) {
            if let harShareURL {
                ShareSheet(items: [harShareURL])
            }
        }
        .task {
            model.refreshHAREntryCount()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refreshHAREntryCount()
            }
        }
    }

    private func exportHAR() {
        harExportError = nil
        do {
            let url = try model.exportHARFileURL()
            harShareURL = url
            showHARShareSheet = true
        } catch {
            harExportError = error.localizedDescription
        }
    }
}

// MARK: - О приложении

private struct SettingsAboutView: View {
    let model: EncounterViewModel
    let appVersion: String

    var body: some View {
        SettingsSubScreen(title: "О приложении") {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("О приложении")
                aboutRow("Приложение", value: AppMetadata.displayName, systemImage: "app")
                aboutRow("Автор", value: "Sergei \"svk\" Krashevich", systemImage: "person")
                aboutRow("Версия", value: appVersion, systemImage: "number")

                Link(destination: AppMetadata.repositoryURL) {
                    DashboardSettingsRow(
                        title: "Исходный код на GitHub",
                        systemImage: "link",
                        tint: GameTheme.accent
                    )
                }
                Link(destination: AppMetadata.apiClientRepositoryURL) {
                    DashboardSettingsRow(
                        title: "Клиент API (encx-cli)",
                        systemImage: "link",
                        tint: GameTheme.accent
                    )
                }
            }
            .sectionPanel()

            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Автоматизации")
                DashboardSettingsRow(
                    title: "Команды Shortcuts",
                    subtitle: "Отправить код, статус игры и отправка очереди доступны в приложении «Команды».",
                    systemImage: "square.stack.3d.up",
                    tint: GameTheme.bonusTitle
                )
            }
            .sectionPanel()
        }
    }

    private func aboutRow(_ title: String, value: String, systemImage: String) -> some View {
        DashboardSettingsRow(
            title: title,
            systemImage: systemImage,
            tint: GameTheme.bonusTitle
        ) {
            Text(value)
                .font(.subheadline)
                .foregroundStyle(GameTheme.muted)
                .multilineTextAlignment(.trailing)
        }
    }
}
