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
    /// The free-form domain row swaps its placeholder for the real text field once tapped.
    @State private var isEnteringCustomDomain = false
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

    private enum Metrics {
        static let rowHeight: CGFloat = 60
        static let rowRadius: CGFloat = 16
        static let rowSpacing: CGFloat = 10
        static let blockSpacing: CGFloat = 26
        static let sideInset: CGFloat = 20
    }

    var body: some View {
        VStack(spacing: 0) {
            progressIndicator

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch step {
                    case .welcome: welcomeStep
                    case .domain: domainStep
                    case .account: accountStep
                    case .notifications: notificationsStep
                    case .ready: readyStep
                    }
                }
                .padding(.horizontal, Metrics.sideInset)
                .padding(.top, 34)
                .padding(.bottom, 28)
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

    private var progressIndicator: some View {
        HStack(spacing: 5) {
            ForEach(OnboardingStep.allCases) { candidate in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(candidate.rawValue <= step.rawValue ? GameTheme.accent : GameTheme.trackEmpty)
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, Metrics.sideInset)
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    private var footer: some View {
        VStack(spacing: 14) {
            Button {
                advance()
            } label: {
                HStack(spacing: 10) {
                    Text(primaryButtonTitle)
                        .font(.system(size: 18, weight: .bold))
                    Image(systemName: primaryButtonIcon)
                        .font(.system(size: 22, weight: .semibold))
                }
                .foregroundStyle(GameTheme.text)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
                        .fill(GameTheme.accent)
                )
                .opacity(isPrimaryButtonDisabled ? 0.45 : 1)
            }
            .buttonStyle(.plain)
            .disabled(isPrimaryButtonDisabled)

            HStack {
                if step != .welcome {
                    Button("Назад") { retreat() }
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.5))
                        .disabled(model.isBusy)
                }
                Spacer()
                if let secondaryTitle = secondaryButtonTitle {
                    Button(secondaryTitle) { skipStep() }
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.5))
                        .disabled(model.isBusy)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Metrics.sideInset)
        .padding(.top, 12)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: Metrics.blockSpacing) {
            Image(systemName: "flag.checkered.2.crossed")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(GameTheme.accent)

            stepIntro(
                question: AppMetadata.displayName,
                explainer: "Клиент для игр Encounter: уровни, коды, подсказки и статус команды на одном экране."
            )

            VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                groupLabel("Что внутри")
                detailRow(
                    title: "Быстрая отправка кодов",
                    subtitle: "Очередь работает даже без связи и досылает коды сама.",
                    systemImage: "paperplane.fill",
                    tint: GameTheme.accent
                )
                detailRow(
                    title: "Игра на экране блокировки",
                    subtitle: "Live Activity с уровнем, секторами и таймерами.",
                    systemImage: "rectangle.on.rectangle",
                    tint: GameTheme.bonusTitle
                )
                detailRow(
                    title: "Оповещения по ходу игры",
                    subtitle: "Смена уровня и новые подсказки приходят уведомлением.",
                    systemImage: "bell.badge.fill",
                    tint: GameTheme.sectionHeader
                )
                detailRow(
                    title: "Инструменты игрока",
                    subtitle: "Шифры, анаграммизатор и журнал кодов под рукой.",
                    systemImage: "wrench.and.screwdriver.fill",
                    tint: .orange
                )
            }

            footnote("Настройка займёт меньше минуты. Всё, что здесь выбрано, потом меняется в настройках.")
        }
    }

    private var domainStep: some View {
        VStack(alignment: .leading, spacing: Metrics.blockSpacing) {
            stepIntro(
                question: "На каком домене вы играете?",
                explainer: "Домен Encounter, на котором вы играете. Позже его можно сменить в списке игр или настройках."
            )

            VStack(spacing: Metrics.rowSpacing) {
                ForEach(model.knownDomains, id: \.self) { domain in
                    Button {
                        focusedField = nil
                        isEnteringCustomDomain = false
                        model.applyDomainSelection(domain)
                        customDomain = domain
                    } label: {
                        optionRow(
                            title: domain,
                            systemImage: "globe",
                            isSelected: domain == model.settings.domain
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isBusy)
                }

                customDomainRow
            }

            footnote("Текущий домен: \(model.settings.domain)")
        }
    }

    private var accountStep: some View {
        VStack(alignment: .leading, spacing: Metrics.blockSpacing) {
            stepIntro(
                question: "Вход в аккаунт",
                explainer: "Учётная запись Encounter для домена \(model.settings.domain). Без входа доступен только общий список игр домена."
            )

            VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                entryRow(systemImage: "person.crop.circle") {
                    TextField("Логин", text: $model.login)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .focused($focusedField, equals: .login)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(GameTheme.text)
                }

                entryRow(systemImage: "lock.fill") {
                    SecureField("Пароль", text: $model.password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await performLogin() } }
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(GameTheme.text)
                }

                if model.hasStoredSession {
                    statusLine(
                        text: "Вход выполнен",
                        systemImage: "checkmark.seal.fill",
                        tint: GameTheme.accent
                    )
                }

                if let loginError {
                    statusLine(
                        text: loginError,
                        systemImage: "exclamationmark.triangle",
                        tint: .orange
                    )
                }
            }

            footnote("Пароль сохраняется в Keychain устройства и используется только для входа на выбранный домен.")
        }
    }

    private var notificationsStep: some View {
        VStack(alignment: .leading, spacing: Metrics.blockSpacing) {
            stepIntro(
                question: "Оповещения",
                explainer: "Уведомления и Live Activity помогают не пропустить смену уровня, пока приложение свёрнуто."
            )

            VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                groupLabel("Что включить")
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

            VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                groupLabel("Разрешение системы")

                rowChrome(fill: GameTheme.panel, stroke: Color(white: 0.15)) {
                    if isRequestingNotifications {
                        ProgressView().controlSize(.small)
                        Text("Запрашиваем разрешение…")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.55))
                    } else {
                        switch notificationsGranted {
                        case true?:
                            permissionLabel("Уведомления разрешены", systemImage: "checkmark.circle.fill", tint: .green)
                        case false?:
                            permissionLabel("Нет доступа к уведомлениям", systemImage: "xmark.circle.fill", tint: .orange)
                        case nil:
                            permissionLabel("Разрешение ещё не запрошено", systemImage: "questionmark.circle", tint: .white.opacity(0.55))
                        }
                    }
                }

                if notificationsGranted != true && anyNotificationOptionEnabled {
                    Button {
                        Task { await requestNotifications() }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "bell.badge")
                                .font(.system(size: 24))
                                .foregroundStyle(GameTheme.accent)
                                .frame(width: 26)
                            Text("Разрешить уведомления")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(GameTheme.text)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: Metrics.rowHeight)
                        .background(
                            RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
                                .fill(GameTheme.accent.opacity(0.14))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
                                .strokeBorder(GameTheme.accent.opacity(0.6), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isRequestingNotifications)
                }
            }

            footnote(notificationsFooterText)
        }
    }

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: Metrics.blockSpacing) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(GameTheme.accent)

            stepIntro(
                question: "Всё готово",
                explainer: model.hasStoredSession
                    ? "Осталось выбрать игру в списке и начать."
                    : "Список игр домена доступен без входа. Войти в аккаунт можно в любой момент из настроек."
            )

            VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                groupLabel("Итог настройки")
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

            footnote("Эти параметры и остальные опции доступны в разделе «Настройки».")
        }
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func stepIntro(question: String, explainer: String) -> some View {
        Text("Шаг \(step.rawValue + 1) из \(OnboardingStep.allCases.count)")
            .font(.system(size: 12, weight: .bold))
            .textCase(.uppercase)
            .foregroundStyle(GameTheme.sectionHeader)

        Text(question)
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(GameTheme.text)
            .lineSpacing(3)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .fixedSize(horizontal: false, vertical: true)

        Text(explainer)
            .font(.system(size: 16))
            .foregroundStyle(.white.opacity(0.55))
            .lineSpacing(7)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .textCase(.uppercase)
            .foregroundStyle(GameTheme.sectionHeader)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.4))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Shared geometry for every 60pt row on the flow.
    private func rowChrome<Content: View>(
        fill: Color,
        stroke: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            content()
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: Metrics.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
                .strokeBorder(stroke, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous))
    }

    private func optionRow(title: String, systemImage: String, isSelected: Bool) -> some View {
        rowChrome(
            fill: isSelected ? GameTheme.accent.opacity(0.14) : GameTheme.panel,
            stroke: isSelected ? GameTheme.accent.opacity(0.6) : Color(white: 0.15)
        ) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : systemImage)
                .font(.system(size: 24))
                .foregroundStyle(isSelected ? GameTheme.accent : GameTheme.bonusTitle)
                .frame(width: 26)
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(GameTheme.text)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    /// Free-form domain entry: a dashed row that turns into the real text field on tap.
    @ViewBuilder
    private var customDomainRow: some View {
        if isEnteringCustomDomain {
            customDomainChrome {
                TextField("например, moscow.en.cx", text: $customDomain)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .domain)
                    .submitLabel(.done)
                    .onSubmit { applyCustomDomain() }
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(GameTheme.text)

                Button("Применить") { applyCustomDomain() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GameTheme.accent)
                    .buttonStyle(.plain)
                    .disabled(!canApplyCustomDomain)
                    .opacity(canApplyCustomDomain ? 1 : 0.35)
            }
        } else {
            Button {
                isEnteringCustomDomain = true
                focusedField = .domain
            } label: {
                customDomainChrome {
                    Text("Другой домен…")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)
        }
    }

    private func customDomainChrome<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "pencil")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 26)
            content()
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: Metrics.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
                .fill(Color(white: 0.059))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
                .strokeBorder(
                    Color(white: 0.23),
                    style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous))
    }

    private func entryRow<Content: View>(
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        rowChrome(fill: GameTheme.panel, stroke: Color(white: 0.15)) {
            Image(systemName: systemImage)
                .font(.system(size: 24))
                .foregroundStyle(GameTheme.bonusTitle)
                .frame(width: 26)
            content()
        }
    }

    private func detailRow(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        rowChrome(fill: GameTheme.panel, stroke: Color(white: 0.15)) {
            Image(systemName: systemImage)
                .font(.system(size: 24))
                .foregroundStyle(tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(GameTheme.text)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func toggleRow(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color = GameTheme.accent,
        isOn: Binding<Bool>
    ) -> some View {
        rowChrome(fill: GameTheme.panel, stroke: Color(white: 0.15)) {
            Image(systemName: systemImage)
                .font(.system(size: 24))
                .foregroundStyle(tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(GameTheme.text)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
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
        rowChrome(fill: GameTheme.panel, stroke: Color(white: 0.15)) {
            Image(systemName: systemImage)
                .font(.system(size: 24))
                .foregroundStyle(tint)
                .frame(width: 26)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GameTheme.text)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }

    private func statusLine(text: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
    }

    @ViewBuilder
    private func permissionLabel(_ text: String, systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 24))
            .foregroundStyle(tint)
            .frame(width: 26)
        Text(text)
            .font(.system(size: 16))
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
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
