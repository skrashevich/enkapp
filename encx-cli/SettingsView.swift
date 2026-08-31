import SwiftUI
import UIKit

private enum PermissionCheckStatus: Equatable {
    case pending
    case granted
    case denied
}

struct SettingsView: View {
    @Bindable var model: EncounterViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var notificationDenied = false
    @State private var liveActivitySystemStatus: PermissionCheckStatus = .pending
    @State private var liveActivityPushStatus: PermissionCheckStatus = .pending
    @State private var showHARShareSheet = false
    @State private var showDomainChooser = false
    @State private var showOnboarding = false
    @State private var harShareURL: URL?
    @State private var harExportError: String?
    @State private var agentAPIKeyDraft = ""
    @State private var agentKeyStored = false
    @State private var agentKeyStatus: String?
    @State private var codexSignIn = CodexSignInModel()
    @State private var downloadedModel = DownloadedModelPreference.selected
    @Environment(\.scenePhase) private var scenePhase

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                settingsHeader
                accountSection
                setupSection
                connectionSection
                agentSection
                notificationsSection
                liveActivitySection
                debugSection
                automationSection
                aboutSection
            }
            .padding()
        }
        .background(GameTheme.background)
        .scrollContentBackground(.hidden)
        .preferredColorScheme(.dark)
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(GameTheme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
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
        .task {
            if model.settings.liveActivityEnabled {
                liveActivitySystemStatus = .pending
                liveActivityPushStatus = .pending
                await model.requestNotificationAuthorizationIfNeeded()
            }
            await refreshNotificationStatus()
            await refreshLiveActivityPermissions()
            model.refreshHAREntryCount()
        }
        .onDisappear {
            // Without this the login keeps polling OpenAI for a quarter of an hour
            // after the screen is gone, and an approval granted in that window is
            // discarded instead of stored.
            codexSignIn.cancel()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await refreshNotificationStatus()
                    await refreshLiveActivityPermissions()
                    model.refreshHAREntryCount()
                }
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

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Параметры")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(GameTheme.text)
                    Text("Аккаунт, уведомления и технические опции приложения.")
                        .font(.subheadline)
                        .foregroundStyle(GameTheme.muted)
                }
                Spacer()
                Image(systemName: "gearshape.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(GameTheme.sectionHeader)
                    .frame(width: 44, height: 44)
                    .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 10) {
                DashboardMetric(
                    title: "Домен",
                    value: model.settings.domain,
                    systemImage: "globe",
                    tint: GameTheme.bonusTitle
                )
                DashboardMetric(
                    title: "HAR",
                    value: model.settings.harCaptureEnabled ? "\(model.harEntryCount)" : "Выкл",
                    systemImage: "doc.text.magnifyingglass",
                    tint: .orange
                )
                // Only appears when the engine sent something we could not decode, so a lossy
                // decode leaves a visible trace instead of quietly hiding data.
                if model.decodeDropCount > 0 {
                    DashboardMetric(
                        title: "Пропущено",
                        value: "\(model.decodeDropCount)",
                        systemImage: "exclamationmark.triangle",
                        tint: .red
                    )
                }
            }
        }
        .sectionPanel()
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Аккаунт")

            Button {
                showDomainChooser = true
            } label: {
                DashboardSettingsRow(
                    title: "Домен",
                    subtitle: model.settings.domain,
                    systemImage: "globe",
                    tint: GameTheme.bonusTitle
                ) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GameTheme.muted)
                }
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)

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

            if !model.statusMessage.isEmpty {
                Label(model.statusMessage, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(GameTheme.muted)
            }
        }
        .sectionPanel()
    }

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Первоначальная настройка")
            Button {
                showOnboarding = true
            } label: {
                DashboardSettingsRow(
                    title: "Пройти настройку заново",
                    subtitle: "Домен, вход в аккаунт и разрешения на оповещения шаг за шагом.",
                    systemImage: "sparkles",
                    tint: GameTheme.sectionHeader
                ) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GameTheme.muted)
                }
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)
        }
        .sectionPanel()
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Подключение")
            settingToggleRow(
                title: "Использовать HTTP",
                subtitle: "Для старых или нестандартных доменов Encounter.",
                systemImage: "network",
                isOn: $model.settings.useHTTP
            )
            settingToggleRow(
                title: "Отключить проверку TLS",
                subtitle: "Только если сертификат домена сломан.",
                systemImage: "lock.trianglebadge.exclamationmark",
                tint: .orange,
                isOn: $model.settings.insecureTLS
            )
        }
        .sectionPanel()
    }

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Ассистент")
            settingToggleRow(
                title: "Ассистент в игре",
                subtitle: "Чат с ИИ, который видит движок и умеет им пользоваться.",
                systemImage: "sparkles",
                tint: GameTheme.bonusTitle,
                isOn: $model.agentSettings.enabled
            )

            if model.agentSettings.enabled {
                agentProviderRows
                if model.agentSettings.provider.needsModelDownload {
                    agentDownloadedModelRows
                } else if model.agentSettings.provider.runsOnDevice {
                    agentOnDeviceRows
                } else if model.agentSettings.provider.usesSubscriptionLogin {
                    agentChatGPTRows
                } else {
                    agentKeyRows
                }
                agentPolicyRows
            }
        }
        .sectionPanel()
        .onChange(of: model.agentSettings) { _, _ in
            model.persistAgentSettings()
        }
        .onAppear { refreshAgentCredentialState() }
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
        .onChange(of: downloadedModel) { _, newValue in
            DownloadedModelPreference.selected = newValue
            // The chosen model is captured when the session is built.
            model.invalidateAgentSession()
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

        if !model.agentSettings.provider.runsOnDevice {
            TextField("Модель", text: $model.agentSettings.model)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(GameTheme.text)
                .padding(12)
                .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 10))
        }

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

    @ViewBuilder
    private var agentDownloadedModelRows: some View {
        Picker("Модель", selection: $downloadedModel) {
            ForEach(DownloadableModel.allCases) { candidate in
                Text(candidate.title).tag(candidate)
            }
        }
        .pickerStyle(.segmented)

        Text("\(downloadedModel.approximateSize) · \(downloadedModel.note)")
            .font(.caption)
            .foregroundStyle(GameTheme.muted)

        Text("Веса скачиваются с Hugging Face при первом вопросе и остаются на устройстве. "
            + "Дальше всё работает без сети и без ключей. Такая модель заметно слабее облачной: "
            + "она хуже держит длинные рассуждения и не умеет смотреть картинки заданий. "
            + "Поиск в интернете в этом режиме выключен.")
            .font(.caption)
            .foregroundStyle(GameTheme.muted)
    }

    @ViewBuilder
    private var agentOnDeviceRows: some View {
        switch OnDeviceAgentBackend.availability {
        case .available:
            Text("Модель Apple работает прямо на устройстве: ключ не нужен, запросы никуда не уходят. "
                + "Она заметно меньше облачных, поэтому хуже справляется с длинными рассуждениями "
                + "и не умеет смотреть картинки заданий. Поиск в интернете в этом режиме выключен.")
                .font(.caption)
                .foregroundStyle(GameTheme.muted)
        case .unsupported(let reason):
            Label(reason, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
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
        Picker("Доступ к движку", selection: $model.agentSettings.policy) {
            ForEach(AgentAccessPolicy.allCases) { policy in
                Text(policy.title).tag(policy)
            }
        }
        .pickerStyle(.segmented)

        Text(model.agentSettings.policy.explanation)
            .font(.caption)
            .foregroundStyle(model.agentSettings.policy.actsWithoutAsking ? .orange : GameTheme.muted)

        settingToggleRow(
            title: "Поиск в интернете",
            subtitle: "DuckDuckGo и чтение страниц. Запросы уходят в поисковик.",
            systemImage: "globe",
            tint: GameTheme.bonusTitle,
            isOn: $model.agentSettings.webToolsEnabled
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

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Уведомления")
            settingToggleRow(
                title: "Новый уровень",
                subtitle: "Локальное уведомление при смене уровня.",
                systemImage: "flag.checkered",
                isOn: $model.settings.pushOnNewLevel
            )
            settingToggleRow(
                title: "Новая подсказка",
                subtitle: "Оповещение, когда появляется текст подсказки.",
                systemImage: "lightbulb.fill",
                tint: GameTheme.sectionHeader,
                isOn: $model.settings.pushOnNewHint
            )

            if notificationDenied {
                Button("Открыть настройки iOS") {
                    openAppSettings()
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

    private var liveActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Live Activity")
            settingToggleRow(
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
                        openAppSettings()
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

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Отладка")
            settingToggleRow(
                title: "Запись HAR",
                subtitle: "Дамп HTTP-запросов к серверу Encounter.",
                systemImage: "doc.text.magnifyingglass",
                tint: .orange,
                isOn: $model.settings.harRecordingEnabled
            )
            settingToggleRow(
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

            if let harExportError {
                Label(harExportError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .sectionPanel()
    }

    private var automationSection: some View {
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

    private var aboutSection: some View {
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

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    private func requestPushPermission() async {
        liveActivityPushStatus = .pending
        let granted = await GameEventNotificationService.shared.requestAuthorizationIfNeeded()
        await refreshLiveActivityPermissions()
        await refreshNotificationStatus()
        if !granted {
            let status = await GameEventNotificationService.shared.authorizationStatus()
            if status == .denied {
                openAppSettings()
            }
        }
    }

    private func requestLiveActivityPermission() async {
        liveActivitySystemStatus = .pending
        await model.applyLiveActivitySetting()
        await refreshLiveActivityPermissions()
        guard liveActivitySystemStatus == .denied else { return }
        openAppSettings()
    }

    private func liveActivityToggle(
        _ title: String,
        keyPath: WritableKeyPath<LiveActivityDisplayOptions, Bool>
    ) -> some View {
        settingToggleRow(
            title: title,
            systemImage: liveActivityIcon(for: title),
            isOn: Binding(
                get: { model.settings.liveActivityDisplay[keyPath: keyPath] },
                set: { model.settings.liveActivityDisplay[keyPath: keyPath] = $0 }
            )
        )
    }

    private func settingToggleRow(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color = GameTheme.accent,
        isOn: Binding<Bool>
    ) -> some View {
        DashboardSettingsRow(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            tint: tint
        ) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .tint(GameTheme.accent)
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

    private func refreshNotificationStatus() async {
        let status = await GameEventNotificationService.shared.authorizationStatus()
        notificationDenied = status == .denied
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
