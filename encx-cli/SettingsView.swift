import SwiftUI

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
    @State private var harShareURL: URL?
    @State private var harExportError: String?
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
                connectionSection
                notificationsSection
                liveActivitySection
                analyticsSection
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
                    value: model.settings.harRecordingEnabled ? "\(model.harEntryCount)" : "Выкл",
                    systemImage: "doc.text.magnifyingglass",
                    tint: .orange
                )
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

            if model.settings.harRecordingEnabled {
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

    @ViewBuilder
    private var analyticsSection: some View {
        if TelemetryService.isCompiledIn {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Аналитика")
                settingToggleRow(
                    title: "Аналитика и ошибки",
                    subtitle: "Обезличенные события использования и технические сбои.",
                    systemImage: "chart.line.uptrend.xyaxis",
                    tint: GameTheme.bonusTitle,
                    isOn: $model.settings.analyticsEnabled
                )
            }
            .sectionPanel()
        }
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
