import SwiftUI

struct AppClipRootView: View {
    @Bindable var model: AppClipViewModel
    @Environment(\.openURL) private var openURL
    @State private var codeDraft = ""
    @State private var previousCodeDraft = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    header
                    gameSelector

                    if model.needsLogin {
                        loginPanel
                    }

                    if let game = model.currentModel {
                        gamePanel(game)
                    } else {
                        emptyPanel
                    }

                    queuePanel
                    installPanel
                }
                .padding(14)
            }
            .background(GameTheme.background)
            .navigationTitle("enkapp")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(GameTheme.background, for: .navigationBar)
            .preferredColorScheme(.dark)
            .overlay(alignment: .bottom) {
                if model.isBusy {
                    ProgressView()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 10)
                }
            }
            .alert("Ошибка", isPresented: errorPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .task {
                if model.gameID != nil {
                    await model.loadGame()
                }
            }
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.settings.domain)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(GameTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text("Быстрый доступ к уровню и очереди кодов без установки полного приложения.")
                .font(.subheadline)
                .foregroundStyle(GameTheme.muted)
        }
        .sectionPanel()
    }

    private var gameSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Игра")
            TextField("Домен", text: $model.settings.domain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.plain)
                .padding(12)
                .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(GameTheme.text)

            TextField("ID игры", text: $model.gameIDText)
                .keyboardType(.numberPad)
                .textFieldStyle(.plain)
                .padding(12)
                .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(GameTheme.text)

            Button {
                Task { await model.loadGame() }
            } label: {
                Label("Загрузить", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(GameTheme.accent)
            .disabled(model.isBusy)
        }
        .sectionPanel()
    }

    private var loginPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Вход")
            TextField("Логин", text: $model.login)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.plain)
                .padding(12)
                .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(GameTheme.text)

            SecureField("Пароль", text: $model.password)
                .textFieldStyle(.plain)
                .padding(12)
                .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(GameTheme.text)

            Button {
                Task { await model.loginAction() }
            } label: {
                Label("Войти", systemImage: "person.crop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(GameTheme.accent)
            .disabled(model.isBusy || model.login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .sectionPanel()
    }

    @ViewBuilder
    private func gamePanel(_ game: GameModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Текущий статус")
            Text(game.gameTitle.isEmpty ? "Игра #\(game.gameID)" : game.gameTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(GameTheme.text)

            if !game.teamName.isEmpty {
                Label(game.teamName, systemImage: "person.2.fill")
                    .font(.subheadline)
                    .foregroundStyle(GameTheme.muted)
            }

            if let level = game.level {
                levelView(level)
                codeInput
            } else {
                Text(EncounterClient.eventText(for: game.event))
                    .font(.subheadline)
                    .foregroundStyle(GameTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if game.event == GameEvent.playerNoApplication || game.event == GameEvent.teamNoApplication {
                    Button {
                        Task { await model.enterGame() }
                    } label: {
                        Label("Войти в игру", systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(GameTheme.accent)
                    .disabled(model.isBusy || model.needsLogin)
                }
            }

            if !model.statusMessage.isEmpty {
                Text(model.statusMessage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(GameTheme.sectionHeader)
            }
        }
        .sectionPanel()
    }

    private var emptyPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Уровень")
            Text("Откройте ссылку на игру или укажите домен и ID вручную.")
                .font(.subheadline)
                .foregroundStyle(GameTheme.muted)
        }
        .sectionPanel()
    }

    private func levelView(_ level: Level) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(level.name.isEmpty ? "Уровень \(level.number)" : "Ур. \(level.number): \(level.name)")
                    .font(.headline)
                    .foregroundStyle(GameTheme.text)
                Spacer()
                Text("\(level.passedSectorsCount)/\(level.requiredSectorsCount)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(GameTheme.accent)
            }

            if let task = level.task ?? level.tasks.first {
                Text(task.displayText)
                    .font(.body)
                    .foregroundStyle(GameTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if level.timeoutSecondsRemain > 0 {
                TickingCountdownText(
                    countdown: SyncedSecondsCountdown(remainSeconds: level.timeoutSecondsRemain, syncedAt: Date()),
                    label: GameDurationFormatter.levelDrainLabel
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GameTheme.sectionHeader)
            }

            if !level.canSubmitLevelAnswer(), level.blockDuration > 0 {
                AppClipAnswerBlockCountdown(remainSeconds: level.blockDuration) {
                    Task { await model.loadGame() }
                }
            }

            if !level.helps.isEmpty {
                ForEach(level.helps.prefix(2)) { help in
                    if let text = help.unlockedText {
                        Text("Подсказка \(help.number): \(text.strippingHTML())")
                            .font(.caption)
                            .foregroundStyle(GameTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var codeInput: some View {
        HStack(spacing: 8) {
            TextField("Код", text: $codeDraft)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textFieldStyle(.plain)
                .padding(12)
                .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(GameTheme.text)
                .onSubmit { submitDraft() }

            if !previousCodeDraft.isEmpty {
                Button {
                    codeDraft = previousCodeDraft
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Повторить предыдущий код")
                .accessibilityHint("Вернуть предыдущий код в поле ввода для правки")
            }

            Button {
                submitDraft()
            } label: {
                Image(systemName: "paperplane.fill")
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.borderedProminent)
            .tint(GameTheme.accent)
            .disabled(!model.canSubmitCode || codeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var queuePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Очередь кодов")
            HStack {
                Label("\(model.queue.pending.count) в очереди", systemImage: model.queue.isOnline ? "wifi" : "wifi.slash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(model.queue.pending.isEmpty ? GameTheme.muted : GameTheme.sectionHeader)
                Spacer()
                Button {
                    Task { await model.flushQueue() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                }
                .buttonStyle(.bordered)
                .disabled(model.queue.pending.isEmpty || model.isBusy)
            }
            Text("Блиц-очередь хранится локально в App Clip. Для надёжной фоновой отправки используйте полное приложение.")
                .font(.caption)
                .foregroundStyle(GameTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sectionPanel()
    }

    private var installPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Полное приложение")
            Text("enkapp добавляет Live Activity, уведомления, автоматизации и фоновую отправку очереди.")
                .font(.subheadline)
                .foregroundStyle(GameTheme.muted)
            Button {
                openURL(AppClipMetadata.fullAppInstallURL)
            } label: {
                Label("Установить enkapp", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(GameTheme.accent)
        }
        .sectionPanel()
    }

    private func submitDraft() {
        let value = codeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        guard model.canSubmitCode else {
            // Preserve the draft and let the view model surface the current block reason.
            Task { await model.submitCode(value) }
            return
        }
        previousCodeDraft = value
        codeDraft = ""
        Task { await model.submitCode(value) }
    }
}

private struct AppClipAnswerBlockCountdown: View {
    let remainSeconds: Int
    let onExpire: () -> Void
    @State private var syncedAt = Date()

    var body: some View {
        TickingCountdownText(
            countdown: SyncedSecondsCountdown(remainSeconds: remainSeconds, syncedAt: syncedAt),
            label: { "Ответы можно отправить через \($0) сек." }
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(GameTheme.sectionHeader)
        .onAppear { syncedAt = Date() }
        .onChange(of: remainSeconds) { _, _ in syncedAt = Date() }
        .task(id: remainSeconds) {
            try? await Task.sleep(for: .seconds(Double(remainSeconds) + 1))
            guard !Task.isCancelled else { return }
            onExpire()
        }
    }
}
