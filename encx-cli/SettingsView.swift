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
    @State private var harShareURL: URL?
    @State private var harExportError: String?
    @Environment(\.scenePhase) private var scenePhase

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            Section("Подключение") {
                Toggle("Использовать HTTP", isOn: $model.settings.useHTTP)
                Toggle("Отключить проверку TLS", isOn: $model.settings.insecureTLS)
            }

            Section {
                Toggle("Запись HAR", isOn: $model.settings.harRecordingEnabled)

                if model.settings.harRecordingEnabled {
                    LabeledContent("Записей", value: "\(model.harEntryCount)")

                    Button {
                        exportHAR()
                    } label: {
                        Label("Экспорт HAR", systemImage: "square.and.arrow.up")
                    }
                    .disabled(model.harEntryCount == 0 || model.isBusy)

                    Button("Очистить запись", role: .destructive) {
                        model.clearHARCapture()
                    }
                    .disabled(model.harEntryCount == 0 || model.isBusy)
                }
            } header: {
                Text("Отладка")
            } footer: {
                Text("HAR — дамп HTTP-запросов к серверу Encounter (HAR 1.2). Экспортируйте и отправьте для отладки или создания mock-сервера. Пароли в login-запросах скрываются; cookies и коды остаются в файле.")
            }

            if let harExportError {
                Section {
                    Label(harExportError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Live Activity", isOn: $model.settings.liveActivityEnabled)

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
                }
            } footer: {
                Text(liveActivityFooterText)
            }

            if liveActivityPermissionsNeedSettings {
                Section {
                    Button("Открыть настройки iOS") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
            }

            if model.settings.liveActivityEnabled {
                Section {
                    liveActivityToggle("Название игры", keyPath: \.showGameTitle)
                    liveActivityToggle("Уровень", keyPath: \.showLevel)
                    liveActivityToggle("Команда", keyPath: \.showTeam)
                    liveActivityToggle("Секторы и бонусы", keyPath: \.showProgress)
                    liveActivityToggle("Очередь кодов", keyPath: \.showQueue)
                    liveActivityToggle("Пробитые коды", keyPath: \.showCodes)
                    liveActivityToggle("Подсказки", keyPath: \.showHints)
                    liveActivityToggle("Статус", keyPath: \.showStatus)
                } header: {
                    Text("На экране блокировки")
                } footer: {
                    Text("Выберите, какие блоки отображать в Live Activity.")
                }
            }

            Section {
                Toggle("Новый уровень", isOn: $model.settings.pushOnNewLevel)
                Toggle("Новая подсказка", isOn: $model.settings.pushOnNewHint)
            } header: {
                Text("Уведомления")
            } footer: {
                if notificationDenied {
                    Text("Разрешите уведомления в настройках iOS, чтобы получать оповещения вне приложения.")
                } else {
                    Text("Локальные уведомления при смене уровня или появлении текста подсказки. Работают в фоне, пока открыта игра.")
                }
            }

            if notificationDenied {
                Section {
                    Button("Открыть настройки iOS") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
            }

            Section("Аккаунт") {
                LabeledContent("Домен", value: model.settings.domain)

                TextField("Логин", text: $model.login)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("Пароль", text: $model.password)

                Button {
                    Task {
                        if await model.loginAction() {
                            dismiss()
                        }
                    }
                } label: {
                    Label("Войти", systemImage: "person.crop.circle.badge.checkmark")
                }
                .disabled(model.login.isEmpty || model.password.isEmpty || model.isBusy)
            }

            if !model.statusMessage.isEmpty {
                Section {
                    Label(model.statusMessage, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("О приложении") {
                LabeledContent("Приложение", value: AppMetadata.displayName)
                LabeledContent("Автор", value: "Sergei \"svk\" Krashevich")
                LabeledContent("Версия", value: appVersion)
                Link(destination: AppMetadata.repositoryURL) {
                    Label("Исходный код на GitHub", systemImage: "link")
                }
                Link(destination: AppMetadata.apiClientRepositoryURL) {
                    Label("Клиент API (encx-cli)", systemImage: "link")
                }
            }
        }
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
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
        Toggle(title, isOn: Binding(
            get: { model.settings.liveActivityDisplay[keyPath: keyPath] },
            set: { model.settings.liveActivityDisplay[keyPath: keyPath] = $0 }
        ))
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
