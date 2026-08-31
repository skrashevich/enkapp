import SwiftUI

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case domain
    case account
    case notifications
    case ready

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return "Добро пожаловать"
        case .domain: return "Домен"
        case .account: return "Аккаунт"
        case .notifications: return "Уведомления"
        case .ready: return "Готово"
        }
    }
}

/// First-launch setup: picks a domain, signs the player in and asks for the
/// notification permissions the game screens rely on.
struct OnboardingView: View {
    @Bindable var model: EncounterViewModel
    var onFinish: () -> Void

    @State private var step: OnboardingStep = .welcome
    @State private var customDomain = ""
    @State private var loginError: String?
    @State private var notificationsGranted: Bool?
    @State private var isRequestingNotifications = false
    @State private var didApplyFirstRunDefaults = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case domain
        case login
        case password
    }

    var body: some View {
        VStack(spacing: 0) {
            progressHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch step {
                    case .welcome: welcomeStep
                    case .domain: domainStep
                    case .account: accountStep
                    case .notifications: notificationsStep
                    case .ready: readyStep
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)

            footer
        }
        .background(GameTheme.background)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.2), value: step)
        // Login can trip the engine's anti-spam check; without this the player would be
        // stuck on an error they have no way to clear from inside onboarding.
        .sheet(isPresented: $model.showAntiSpamVerification) {
            AntiSpamVerificationView(model: model)
        }
        .onAppear {
            customDomain = model.settings.domain
            applyFirstRunDefaults()
        }
        // ContentView owns the observers that persist these settings, and it is not
        // mounted yet during onboarding — without this the choices are lost on relaunch.
        .onChange(of: model.settings.pushOnNewLevel) {
            model.persistAuthorizationSettings()
        }
        .onChange(of: model.settings.pushOnNewHint) {
            model.persistAuthorizationSettings()
        }
        .onChange(of: model.settings.liveActivityEnabled) {
            Task { await model.applyLiveActivitySetting() }
        }
        .task(id: step) {
            guard step == .notifications else { return }
            await refreshNotificationStatus()
        }
    }

    // MARK: - Chrome

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Шаг \(step.rawValue + 1) из \(OnboardingStep.allCases.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GameTheme.muted)
                Spacer()
                Text(step.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GameTheme.sectionHeader)
            }

            HStack(spacing: 4) {
                ForEach(OnboardingStep.allCases) { candidate in
                    Capsule()
                        .fill(candidate.rawValue <= step.rawValue ? GameTheme.accent : GameTheme.border)
                        .frame(height: 4)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: step)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(GameTheme.panel)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(GameTheme.border)
                .frame(height: 1)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                advance()
            } label: {
                Label(primaryButtonTitle, systemImage: primaryButtonIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(GameTheme.accent)
            .disabled(isPrimaryButtonDisabled)

            HStack {
                if step != .welcome {
                    Button("Назад") { retreat() }
                        .font(.subheadline)
                        .tint(GameTheme.muted)
                        .disabled(model.isBusy)
                }
                Spacer()
                if let secondaryTitle = secondaryButtonTitle {
                    Button(secondaryTitle) { skipStep() }
                        .font(.subheadline)
                        .tint(GameTheme.muted)
                        .disabled(model.isBusy)
                }
            }
        }
        .padding(16)
        .background(GameTheme.panel)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(GameTheme.border)
                .frame(height: 1)
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "flag.checkered.2.crossed")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(GameTheme.accent)
                Text(AppMetadata.displayName)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(GameTheme.text)
                Text("Клиент для игр Encounter: уровни, коды, подсказки и статус команды на одном экране.")
                    .font(.subheadline)
                    .foregroundStyle(GameTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .sectionPanel()

            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Что внутри")
                featureRow(
                    title: "Быстрая отправка кодов",
                    subtitle: "Очередь работает даже без связи и досылает коды сама.",
                    systemImage: "paperplane.fill",
                    tint: GameTheme.accent
                )
                featureRow(
                    title: "Игра на экране блокировки",
                    subtitle: "Live Activity с уровнем, секторами и таймерами.",
                    systemImage: "rectangle.on.rectangle",
                    tint: GameTheme.bonusTitle
                )
                featureRow(
                    title: "Оповещения по ходу игры",
                    subtitle: "Смена уровня и новые подсказки приходят уведомлением.",
                    systemImage: "bell.badge.fill",
                    tint: GameTheme.sectionHeader
                )
                featureRow(
                    title: "Инструменты игрока",
                    subtitle: "Шифры, анаграммизатор и журнал кодов под рукой.",
                    systemImage: "wrench.and.screwdriver.fill",
                    tint: .orange
                )
            }
            .sectionPanel()

            Text("Настройка займёт меньше минуты. Всё, что здесь выбрано, потом меняется в настройках.")
                .font(.caption)
                .foregroundStyle(GameTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var domainStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                title: "Выберите домен",
                subtitle: "Домен Encounter, на котором вы играете. Позже его можно сменить в списке игр или настройках.",
                systemImage: "globe"
            )

            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Известные домены")
                ForEach(model.knownDomains, id: \.self) { domain in
                    Button {
                        focusedField = nil
                        model.applyDomainSelection(domain)
                        customDomain = domain
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
            .sectionPanel()

            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Другой домен")
                HStack(spacing: 8) {
                    TextField("например, moscow.en.cx", text: $customDomain)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .domain)
                        .submitLabel(.done)
                        .onSubmit { applyCustomDomain() }
                        .foregroundStyle(GameTheme.text)
                        .padding(12)
                        .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 10))

                    Button("Применить") { applyCustomDomain() }
                        .buttonStyle(.bordered)
                        .tint(GameTheme.accent)
                        .disabled(!canApplyCustomDomain)
                }
                Text("Текущий домен: \(model.settings.domain)")
                    .font(.caption)
                    .foregroundStyle(GameTheme.muted)
            }
            .sectionPanel()
        }
    }

    private var accountStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                title: "Вход в аккаунт",
                subtitle: "Учётная запись Encounter для домена \(model.settings.domain). Без входа доступен только общий список игр домена.",
                systemImage: "person.crop.circle"
            )

            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Учётные данные")

                TextField("Логин", text: $model.login)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .focused($focusedField, equals: .login)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .foregroundStyle(GameTheme.text)
                    .padding(12)
                    .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 10))

                SecureField("Пароль", text: $model.password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { Task { await performLogin() } }
                    .foregroundStyle(GameTheme.text)
                    .padding(12)
                    .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 10))

                if model.hasStoredSession {
                    Label("Вход выполнен", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(GameTheme.accent)
                }

                if let loginError {
                    Label(loginError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Пароль сохраняется в Keychain устройства и используется только для входа на выбранный домен.")
                    .font(.caption)
                    .foregroundStyle(GameTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .sectionPanel()
        }
    }

    private var notificationsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                title: "Оповещения",
                subtitle: "Уведомления и Live Activity помогают не пропустить смену уровня, пока приложение свёрнуто.",
                systemImage: "bell.badge"
            )

            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Что включить")
                toggleRow(
                    title: "Новый уровень",
                    subtitle: "Уведомление, когда команда переходит на следующий уровень.",
                    systemImage: "flag.checkered",
                    isOn: $model.settings.pushOnNewLevel
                )
                toggleRow(
                    title: "Новая подсказка",
                    subtitle: "Оповещение при открытии текста подсказки.",
                    systemImage: "lightbulb.fill",
                    tint: GameTheme.sectionHeader,
                    isOn: $model.settings.pushOnNewHint
                )
                toggleRow(
                    title: "Live Activity",
                    subtitle: "Игра на экране блокировки и в Dynamic Island.",
                    systemImage: "rectangle.on.rectangle",
                    tint: GameTheme.bonusTitle,
                    isOn: $model.settings.liveActivityEnabled
                )
            }
            .sectionPanel()

            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Разрешение системы")

                HStack(spacing: 10) {
                    if isRequestingNotifications {
                        ProgressView().controlSize(.small)
                        Text("Запрашиваем разрешение…")
                            .font(.subheadline)
                            .foregroundStyle(GameTheme.muted)
                    } else {
                        switch notificationsGranted {
                        case true?:
                            Label("Уведомления разрешены", systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                        case false?:
                            Label("Нет доступа к уведомлениям", systemImage: "xmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                        case nil:
                            Label("Разрешение ещё не запрошено", systemImage: "questionmark.circle")
                                .font(.subheadline)
                                .foregroundStyle(GameTheme.muted)
                        }
                    }
                    Spacer()
                }
                .padding(12)
                .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 10))

                if notificationsGranted != true && anyNotificationOptionEnabled {
                    Button {
                        Task { await requestNotifications() }
                    } label: {
                        Label("Разрешить уведомления", systemImage: "bell.badge")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(GameTheme.accent)
                    .disabled(isRequestingNotifications)
                }

                Text(notificationsFooterText)
                    .font(.caption)
                    .foregroundStyle(GameTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .sectionPanel()
        }
    }

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(GameTheme.accent)
                Text("Всё готово")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(GameTheme.text)
                Text(model.hasStoredSession
                     ? "Осталось выбрать игру в списке и начать."
                     : "Список игр домена доступен без входа. Войти в аккаунт можно в любой момент из настроек.")
                    .font(.subheadline)
                    .foregroundStyle(GameTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .sectionPanel()

            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Итог настройки")
                summaryRow(
                    title: "Домен",
                    value: model.settings.domain,
                    systemImage: "globe",
                    tint: GameTheme.bonusTitle
                )
                summaryRow(
                    title: "Аккаунт",
                    value: model.hasStoredSession ? (model.login.isEmpty ? "Вход выполнен" : model.login) : "Без входа",
                    systemImage: "person.crop.circle",
                    tint: model.hasStoredSession ? GameTheme.accent : GameTheme.muted
                )
                summaryRow(
                    title: "Уведомления",
                    value: notificationsSummary,
                    systemImage: "bell",
                    tint: GameTheme.sectionHeader
                )
                summaryRow(
                    title: "Live Activity",
                    value: model.settings.liveActivityEnabled ? "Включена" : "Выключена",
                    systemImage: "rectangle.on.rectangle",
                    tint: GameTheme.bonusTitle
                )
            }
            .sectionPanel()

            Text("Эти параметры и остальные опции доступны в разделе «Настройки».")
                .font(.caption)
                .foregroundStyle(GameTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Building blocks

    private func stepHeader(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(GameTheme.text)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(GameTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(GameTheme.sectionHeader)
                .frame(width: 44, height: 44)
                .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 12))
        }
        .sectionPanel()
    }

    private func featureRow(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        DashboardSettingsRow(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            tint: tint
        )
    }

    private func toggleRow(
        title: String,
        subtitle: String,
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

    private func summaryRow(
        title: String,
        value: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        DashboardSettingsRow(
            title: title,
            systemImage: systemImage,
            tint: tint
        ) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GameTheme.text)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }

    // MARK: - Navigation

    private var primaryButtonTitle: String {
        switch step {
        case .welcome: return "Начать настройку"
        case .domain: return "Продолжить"
        case .account: return model.hasStoredSession ? "Продолжить" : "Войти"
        case .notifications: return "Продолжить"
        case .ready: return "Перейти к играм"
        }
    }

    private var primaryButtonIcon: String {
        switch step {
        case .welcome: return "arrow.right.circle.fill"
        case .account: return model.hasStoredSession ? "arrow.right" : "person.crop.circle.badge.checkmark"
        case .ready: return "gamecontroller.fill"
        default: return "arrow.right"
        }
    }

    private var isPrimaryButtonDisabled: Bool {
        if model.isBusy { return true }
        if step == .account && !model.hasStoredSession {
            return model.login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || model.password.isEmpty
        }
        return false
    }

    private var secondaryButtonTitle: String? {
        switch step {
        case .welcome, .ready:
            return nil
        case .account:
            return model.hasStoredSession ? nil : "Пропустить вход"
        default:
            return "Пропустить"
        }
    }

    private func advance() {
        focusedField = nil
        if step == .account && !model.hasStoredSession {
            Task { await performLogin() }
            return
        }
        if step == .ready {
            finish()
            return
        }
        goToNextStep()
    }

    private func skipStep() {
        focusedField = nil
        loginError = nil
        goToNextStep()
    }

    private func goToNextStep() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else {
            finish()
            return
        }
        step = next
    }

    private func retreat() {
        focusedField = nil
        loginError = nil
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// Onboarding proposes the recommended setup, so Live Activity starts enabled.
    /// Only on a genuine first run — re-running the flow from Settings must not
    /// silently flip a choice the player made deliberately.
    private func applyFirstRunDefaults() {
        guard !OnboardingStore.hasCompleted, !didApplyFirstRunDefaults else { return }
        didApplyFirstRunDefaults = true
        model.settings.liveActivityEnabled = true
    }

    private func finish() {
        OnboardingStore.markCompleted()
        // Land on the games list, not on an empty state that sends the player to Settings.
        model.selectedScreen = .games
        onFinish()
        // Skipping login leaves both lists empty and restoreSession() bails out early,
        // so the domain catalogue is fetched here. A successful login already loaded it.
        if model.games.isEmpty, model.domainGames.isEmpty {
            Task { await model.refreshGames() }
        }
    }

    // MARK: - Actions

    private var canApplyCustomDomain: Bool {
        let normalized = customDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !normalized.isEmpty && normalized != model.settings.domain && !model.isBusy
    }

    private func applyCustomDomain() {
        focusedField = nil
        guard model.applyDomainSelection(customDomain) else { return }
        customDomain = model.settings.domain
    }

    private func performLogin() async {
        loginError = nil
        let succeeded = await model.loginAction()
        if succeeded {
            goToNextStep()
            return
        }
        // loginAction() routes failures into the alert channel that ContentView owns.
        // Onboarding has no such alert, so the message is drained and shown inline.
        // A suppressed error lands in statusMessage instead, so both are checked.
        let reported = model.errorMessage ?? model.statusMessage
        loginError = reported.isEmpty
            ? "Не удалось войти. Проверьте домен, логин и пароль."
            : reported
        model.errorMessage = nil
    }

    private var anyNotificationOptionEnabled: Bool {
        model.settings.pushOnNewLevel || model.settings.pushOnNewHint || model.settings.liveActivityEnabled
    }

    private var notificationsSummary: String {
        switch (model.settings.pushOnNewLevel, model.settings.pushOnNewHint) {
        case (true, true): return "Уровень и подсказки"
        case (true, false): return "Только уровень"
        case (false, true): return "Только подсказки"
        case (false, false): return "Выключены"
        }
    }

    private var notificationsFooterText: String {
        if notificationsGranted == false && anyNotificationOptionEnabled {
            return "Без разрешения оповещения не придут, когда приложение свёрнуто. Выдать доступ можно позже в настройках iOS."
        }
        if !anyNotificationOptionEnabled {
            return "Все оповещения выключены — разрешение системы не потребуется."
        }
        return "Разрешение нужно только для оповещений и Live Activity, приложение не отправляет push с сервера."
    }

    private func refreshNotificationStatus() async {
        let status = await GameEventNotificationService.shared.authorizationStatus()
        switch status {
        case .notDetermined:
            notificationsGranted = nil
        default:
            notificationsGranted = GameEventNotificationService.isAuthorized(status)
        }
    }

    private func requestNotifications() async {
        isRequestingNotifications = true
        defer { isRequestingNotifications = false }
        _ = await GameEventNotificationService.shared.requestAuthorizationIfNeeded()
        await refreshNotificationStatus()
    }
}

#Preview {
    OnboardingView(model: EncounterViewModel()) {}
}
