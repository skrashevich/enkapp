import SwiftUI

struct SettingsView: View {
    @Bindable var model: EncounterViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var notificationDenied = false

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
                Toggle("Live Activity", isOn: $model.settings.liveActivityEnabled)
            } footer: {
                Text("Показывает игру на экране блокировки и в Dynamic Island.")
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
        .task {
            await refreshNotificationStatus()
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
}
