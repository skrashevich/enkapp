import SwiftUI

/// Chat with the in-app assistant. The assistant reads the live game through the
/// engine toolset; anything that changes the game is confirmed here first — in the
/// transcript itself, so the pending call stays visible next to its context.
struct AgentChatView: View {
    @Bindable var model: EncounterViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var session: AgentChatSession?
    @State private var startupError: String?
    @State private var draft = ""
    @State private var dictation = VoiceDictationModel()
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if let session {
                serviceLine(session)
                chat(session)
            } else {
                unavailable
            }
        }
        .background(GameTheme.background)
        .preferredColorScheme(.dark)
        .task { start() }
        .onDisappear { dictation.stop() }
    }

    private func start() {
        guard session == nil else { return }
        do {
            // The view model owns the session so a running turn survives dismissal.
            session = try model.agentChatSession()
        } catch {
            startupError = error.localizedDescription
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18))
                    .foregroundStyle(GameTheme.bonusTitle)
                Text("Ассистент")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(GameTheme.text)
            }

            HStack {
                Button {
                    session?.reset()
                } label: {
                    Text("Очистить")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(canClear ? 0.45 : 0.2))
                }
                .buttonStyle(.plain)
                .disabled(!canClear)

                Spacer(minLength: 12)

                Button {
                    dismiss()
                } label: {
                    Text("Готово")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(GameTheme.text)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var canClear: Bool {
        guard let session else { return false }
        return !session.isRunning && !session.messages.isEmpty
    }

    /// Level on the left, access policy and toolset size on the right.
    private func serviceLine(_ session: AgentChatSession) -> some View {
        HStack(spacing: 5) {
            if let levelCaption {
                Text(levelCaption)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 10)

            Text(session.policy.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GameTheme.bonusTitle)
            Text("·")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
            Text("\(session.toolCount) инструментов")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private var levelCaption: String? {
        guard let level = model.currentModel?.level else { return nil }
        let name = level.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Ур. \(level.number)" : "Ур. \(level.number) · \(name)"
    }

    @ViewBuilder
    private var unavailable: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 34))
                .foregroundStyle(GameTheme.muted)
            Text(startupError ?? "Ассистент недоступен.")
                .font(.subheadline)
                .foregroundStyle(GameTheme.muted)
                .multilineTextAlignment(.center)
            Text("Настройте провайдера, модель и ключ API в настройках приложения.")
                .font(.footnote)
                .foregroundStyle(GameTheme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chat(_ session: AgentChatSession) -> some View {
        VStack(spacing: 0) {
            transcript(session)
            composer(session)
        }
    }

    // MARK: - Transcript

    private func transcript(_ session: AgentChatSession) -> some View {
        // Bubbles are sized as a share of the transcript width, so the width has
        // to be measured rather than guessed.
        GeometryReader { geometry in
            let contentWidth = max(0, geometry.size.width - 28)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if session.messages.isEmpty {
                            emptyState(session)
                        }
                        ForEach(session.messages) { message in
                            AgentMessageRow(message: message, availableWidth: contentWidth)
                                .id(message.id)
                        }
                        if session.isRunning {
                            AgentActivityPanel(
                                activity: session.activity,
                                startedAt: session.runStartedAt,
                                awaitingConfirmation: session.currentConfirmation != nil
                            )
                                .id(Self.activityAnchor)
                        }
                        if let confirmation = session.currentConfirmation {
                            AgentConfirmationCard(confirmation: confirmation) { approved in
                                session.resolve(confirmation, approved: approved)
                            }
                            .id(Self.confirmationAnchor)
                        }
                    }
                    .padding(14)
                }
                .scrollContentBackground(.hidden)
                .onAppear {
                    scrollToBottom(session, proxy: proxy)
                }
                .onChange(of: session.isRunning) { _, _ in
                    scrollToBottom(session, proxy: proxy)
                }
                .onChange(of: session.messages.count) { _, _ in
                    scrollToBottom(session, proxy: proxy)
                }
                .onChange(of: session.activity.count) { _, _ in
                    scrollToBottom(session, proxy: proxy)
                }
                .onChange(of: session.currentConfirmation?.id) { _, _ in
                    scrollToBottom(session, proxy: proxy)
                }
            }
        }
    }

    private static let activityAnchor = "agent-activity"
    private static let confirmationAnchor = "agent-confirmation"

    private func submit(_ session: AgentChatSession) {
        dictation.stop()
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !session.isRunning else { return }
        draft = ""
        let currentModel = model.currentModel
        let gameID = model.selectedGameID ?? currentModel.map { Int64($0.gameID) }
        let levelID = currentModel?.gameID == gameID.map(Int.init)
            ? currentModel?.level?.levelID
            : nil
        Task { await session.send(text, gameID: gameID, levelID: levelID) }
    }

    private func scrollToBottom(_ session: AgentChatSession, proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if session.currentConfirmation != nil {
                proxy.scrollTo(Self.confirmationAnchor, anchor: .bottom)
            } else if session.isRunning {
                proxy.scrollTo(Self.activityAnchor, anchor: .bottom)
            } else if let last = session.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func emptyState(_ session: AgentChatSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ассистент видит текущую игру: уровень, секторы, бонусы, подсказки, лог кодов и статистику.")
                .font(.footnote)
                .foregroundStyle(GameTheme.muted)
            Text(session.policy.explanation)
                .font(.footnote)
                .foregroundStyle(GameTheme.muted)
            Text("Доступно инструментов движка: \(session.toolCount)")
                .font(.caption)
                .foregroundStyle(GameTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(GameTheme.panel, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Composer

    private func composer(_ session: AgentChatSession) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(GameTheme.hairline)
                .frame(height: 1)

            HStack(alignment: .bottom, spacing: 10) {
                inputField(session)

                if !session.isRunning && dictation.isSupported {
                    Button {
                        dictation.toggle { text in draft = text }
                    } label: {
                        composerButtonLabel {
                            Image(systemName: dictation.isListening ? "mic.fill" : "mic")
                                .font(.system(size: 20))
                                .foregroundStyle(dictation.isListening
                                                 ? GameTheme.accent
                                                 : .white.opacity(0.55))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(dictation.isListening ? "Остановить диктовку" : "Продиктовать")
                }

                if session.isRunning {
                    Button {
                        session.cancel()
                    } label: {
                        composerButtonLabel {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Остановить")
                } else {
                    let canSend = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    Button {
                        submit(session)
                    } label: {
                        composerButtonLabel {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(GameTheme.accent)
                                .opacity(canSend ? 1 : 0.35)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .accessibilityLabel("Отправить")
                }
            }
            .padding(12)

            if case .unavailable(let reason) = dictation.state {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .background(GameTheme.background)
    }

    /// The placeholder colour cannot be set on a `TextField` prompt, so it is
    /// drawn behind an untitled field instead.
    private func inputField(_ session: AgentChatSession) -> some View {
        ZStack(alignment: .topLeading) {
            if draft.isEmpty {
                Text("Спросите об игре…")
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 17)
                    .allowsHitTesting(false)
            }

            TextField("", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .foregroundStyle(GameTheme.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 17)
                .focused($inputFocused)
                .disabled(session.isRunning)
                // With a hardware keyboard Return sends and Shift+Return breaks
                // the line. A vertical-axis TextField never calls onSubmit, so
                // the key has to be intercepted directly.
                .onKeyPress(.return, phases: .down) { keyPress in
                    guard !keyPress.modifiers.contains(.shift) else { return .ignored }
                    submit(session)
                    return .handled
                }
        }
        .frame(minHeight: 56)
        .background(GameTheme.fieldFill, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(GameTheme.fieldStroke, lineWidth: 1)
        }
    }

    private func composerButtonLabel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: 56, height: 56)
            .background(GameTheme.fieldFill, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(GameTheme.fieldStroke, lineWidth: 1)
            }
    }
}

/// The player's turns are bubbles; the assistant answers straight onto the
/// background, so long replies read as a document rather than as chat.
private struct AgentMessageRow: View {
    let message: AgentMessage
    let availableWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            if message.role == .user {
                Spacer(minLength: 0)
                Text(message.text)
                    .font(.system(size: 16))
                    .lineSpacing(16 * 0.4)
                    .foregroundStyle(GameTheme.text)
                    .textSelection(.enabled)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 13)
                    .background(GameTheme.accent.opacity(0.22), in: Self.userBubble)
                    .frame(maxWidth: availableWidth * 0.78, alignment: .trailing)
            } else {
                assistantContent
                    .foregroundStyle(message.role == .failure ? Color.red : GameTheme.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: availableWidth * 0.88, alignment: .leading)
                Spacer(minLength: 0)
            }
        }
    }

    private static let userBubble = UnevenRoundedRectangle(
        topLeadingRadius: 14,
        bottomLeadingRadius: 14,
        bottomTrailingRadius: 4,
        topTrailingRadius: 14,
        style: .continuous
    )

    @ViewBuilder
    private var assistantContent: some View {
        if message.role == .assistant {
            AgentMarkdownText(source: message.text)
        } else {
            Text(message.text)
                .font(.system(size: 16))
                .lineSpacing(16 * 0.45)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Foundation parses Markdown; separate views retain its block structure, which
/// SwiftUI Text alone does not render (headings, lists, quotes and code blocks).
private struct AgentMarkdownText: View {
    private let blocks: [Block]

    init(source: String) {
        blocks = Self.parse(source)
    }

    private struct Block: Identifiable {
        let id: Int
        let intent: PresentationIntent?
        var text: AttributedString

        var heading: Int? {
            intent?.components.compactMap {
                if case .header(let level) = $0.kind { return level }
                return nil
            }.first
        }

        var isCode: Bool {
            intent?.components.contains {
                if case .codeBlock = $0.kind { return true }
                return false
            } ?? false
        }

        var isQuote: Bool {
            intent?.components.contains { $0.kind == .blockQuote } ?? false
        }

        var listDepth: Int {
            intent?.components.filter {
                switch $0.kind {
                case .orderedList, .unorderedList: return true
                default: return false
                }
            }.count ?? 0
        }

        var marker: String? {
            guard let components = intent?.components,
                  let itemIndex = components.firstIndex(where: {
                      if case .listItem = $0.kind { return true }
                      return false
                  }),
                  case .listItem(let ordinal) = components[itemIndex].kind
            else { return nil }
            let parent = components.dropFirst(itemIndex + 1).first {
                switch $0.kind {
                case .orderedList, .unorderedList: return true
                default: return false
                }
            }
            return parent?.kind == .orderedList ? "\(ordinal)." : "•"
        }

        var font: Font {
            if isCode { return .system(.footnote, design: .monospaced) }
            switch heading {
            case 1: return .title2.bold()
            case 2: return .title3.bold()
            case .some: return .headline
            case nil: return .system(size: 16)
            }
        }
    }

    private static func parse(_ source: String) -> [Block] {
        guard let parsed = try? AttributedString(markdown: source) else {
            return [Block(id: 0, intent: nil, text: AttributedString(source))]
        }
        var result: [Block] = []
        for run in parsed.runs {
            var text = AttributedString(parsed[run.range])
            if run.inlinePresentationIntent?.contains(.code) == true {
                text.font = .system(size: 14, design: .monospaced)
            }
            if let last = result.last, last.intent == run.presentationIntent {
                result[result.count - 1].text.append(text)
            } else {
                result.append(Block(id: result.count, intent: run.presentationIntent, text: text))
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                HStack(alignment: .top, spacing: 8) {
                    if block.isQuote {
                        Rectangle()
                            .fill(GameTheme.muted)
                            .frame(width: 3)
                    }
                    if let marker = block.marker {
                        Text(marker)
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    if block.isCode {
                        ScrollView(.horizontal) {
                            Text(block.text)
                                .font(block.font)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(8)
                        }
                        .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 6))
                    } else {
                        Text(block.text)
                            .font(block.font)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, CGFloat(max(0, block.listDepth - 1)) * 16)
            }
        }
        .lineSpacing(16 * 0.45)
        .tint(GameTheme.accent)
    }
}

private struct AgentActivityPanel: View {
    let activity: [AgentToolActivity]
    let startedAt: Date?
    let awaitingConfirmation: Bool

    private var status: String {
        if awaitingConfirmation { return "Ждёт вашего подтверждения" }
        if activity.contains(where: { !$0.isFinished }) { return "Выполняет действия…" }
        return activity.isEmpty ? "Ассистент думает…" : "Обдумывает результаты…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(activity) { item in
                HStack(spacing: 8) {
                    icon(for: item)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(item.isError ? Color.red : GameTheme.text)
                        if !item.arguments.isEmpty {
                            Text(item.arguments)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                }
            }

            if !activity.isEmpty {
                Rectangle()
                    .fill(Color(white: 0.118))
                    .frame(height: 1)
            }

            HStack(spacing: 10) {
                if awaitingConfirmation {
                    Image(systemName: "hourglass")
                        .font(.system(size: 16))
                        .foregroundStyle(GameTheme.bonusTitle)
                        .accessibilityHidden(true)
                } else {
                    ProgressView()
                        .tint(GameTheme.bonusTitle)
                        .accessibilityHidden(true)
                }
                Text(status)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GameTheme.text)
                Spacer(minLength: 8)
                if let startedAt {
                    HStack(spacing: 4) {
                        Text("Прошло")
                        // A relative timer text ticks up on its own, without a
                        // per-second refresh of the whole panel.
                        Text(startedAt, style: .timer)
                            .monospacedDigit()
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Color(white: 0.063), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(GameTheme.bonusTitle.opacity(0.3), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func icon(for item: AgentToolActivity) -> some View {
        if !item.isFinished {
            ProgressView().controlSize(.small)
        } else if item.isError {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.red)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(GameTheme.accent)
        }
    }
}

/// Approval for a mutating engine call, asked inside the transcript.
///
/// A system alert hid the conversation and the tool arguments behind it; here the
/// request stays in place, under the activity it belongs to.
private struct AgentConfirmationCard: View {
    let confirmation: AgentConfirmation
    let resolve: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield")
                    .font(.system(size: 18))
                Text("Подтвердите действие")
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(GameTheme.sectionHeader)

            VStack(alignment: .leading, spacing: 6) {
                Text("Ассистент хочет выполнить:")
                    .font(.system(size: 16))
                    .lineSpacing(16 * 0.4)
                    .foregroundStyle(GameTheme.text)
                chip(confirmation.title)
                if !confirmation.arguments.isEmpty {
                    chip(confirmation.arguments)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button {
                    resolve(true)
                } label: {
                    Text("Разрешить")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(GameTheme.accent, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button {
                    resolve(false)
                } label: {
                    Text("Отклонить")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.horizontal, 18)
                        .frame(height: 48)
                        .background(Color(white: 0.102), in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(white: 0.2), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GameTheme.sectionHeader.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(GameTheme.sectionHeader.opacity(0.45), lineWidth: 1)
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, design: .monospaced))
            .foregroundStyle(GameTheme.text)
            .textSelection(.enabled)
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(Color(white: 0.102), in: RoundedRectangle(cornerRadius: 5))
    }
}
