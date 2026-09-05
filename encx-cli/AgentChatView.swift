import SwiftUI

/// Chat with the in-app assistant. The assistant reads the live game through the
/// engine toolset; anything that changes the game is confirmed here first.
struct AgentChatView: View {
    @Bindable var model: EncounterViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var session: AgentChatSession?
    @State private var startupError: String?
    @State private var draft = ""
    @State private var dictation = VoiceDictationModel()
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if let session {
                    chat(session)
                } else {
                    unavailable
                }
            }
            .background(GameTheme.background)
            .navigationTitle("Ассистент")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Очистить") { session?.reset() }
                        .tint(GameTheme.muted)
                        .disabled(session == nil || session?.isRunning == true || session?.messages.isEmpty == true)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                        .tint(GameTheme.text)
                }
            }
            .toolbarBackground(GameTheme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task { start() }
        .onDisappear { dictation.stop() }
        .confirmationSheet(session: session)
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

    private func transcript(_ session: AgentChatSession) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if session.messages.isEmpty {
                        emptyState(session)
                    }
                    ForEach(session.messages) { message in
                        AgentMessageBubble(message: message)
                            .id(message.id)
                    }
                    if session.isRunning {
                        AgentActivityPanel(activity: session.activity)
                            .id(Self.activityAnchor)
                    }
                }
                .padding(14)
            }
            .scrollContentBackground(.hidden)
            .onChange(of: session.messages.count) { _, _ in
                scrollToBottom(session, proxy: proxy)
            }
            .onChange(of: session.activity.count) { _, _ in
                scrollToBottom(session, proxy: proxy)
            }
        }
    }

    private static let activityAnchor = "agent-activity"

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
            if session.isRunning {
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

    private func composer(_ session: AgentChatSession) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(GameTheme.border)
                .frame(height: 1)

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Спросите об игре…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(GameTheme.text)
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

                if !session.isRunning && dictation.isSupported {
                    Button {
                        dictation.toggle { text in draft = text }
                    } label: {
                        Image(systemName: dictation.isListening ? "mic.fill" : "mic")
                            .font(.title2)
                    }
                    .tint(dictation.isListening ? GameTheme.accent : GameTheme.muted)
                    .accessibilityLabel(dictation.isListening ? "Остановить диктовку" : "Продиктовать")
                }

                if session.isRunning {
                    Button {
                        session.cancel()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                    }
                    .tint(GameTheme.muted)
                    .accessibilityLabel("Остановить")
                } else {
                    Button {
                        submit(session)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .tint(GameTheme.accent)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        .background(GameTheme.panel)
    }
}

private struct AgentMessageBubble: View {
    let message: AgentMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            messageContent
                .font(.subheadline)
                .foregroundStyle(foreground)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(background, in: RoundedRectangle(cornerRadius: 10))

            if message.role != .user { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        if message.role == .assistant {
            AgentMarkdownText(source: message.text)
        } else {
            Text(message.text)
        }
    }

    private var foreground: Color {
        message.role == .failure ? .red : GameTheme.text
    }

    private var background: Color {
        switch message.role {
        case .user: return GameTheme.accent.opacity(0.22)
        case .assistant: return GameTheme.panel
        case .failure: return Color.red.opacity(0.14)
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
            case nil: return .subheadline
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
                text.font = .system(.subheadline, design: .monospaced)
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
        .tint(GameTheme.accent)
    }
}

private struct AgentActivityPanel: View {
    let activity: [AgentToolActivity]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if activity.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Думает…")
                        .font(.caption)
                        .foregroundStyle(GameTheme.muted)
                }
            }
            ForEach(activity) { item in
                HStack(spacing: 8) {
                    icon(for: item)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(item.isError ? .red : GameTheme.text)
                        if !item.arguments.isEmpty {
                            Text(item.arguments)
                                .font(.caption2)
                                .foregroundStyle(GameTheme.muted)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(GameTheme.panel.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func icon(for item: AgentToolActivity) -> some View {
        if !item.isFinished {
            ProgressView().controlSize(.small)
        } else if item.isError {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(GameTheme.accent)
        }
    }
}

private extension View {
    /// Presents the approval sheet for a mutating engine call.
    func confirmationSheet(session: AgentChatSession?) -> some View {
        modifier(AgentConfirmationPresenter(session: session))
    }
}

private struct AgentConfirmationPresenter: ViewModifier {
    let session: AgentChatSession?

    func body(content: Content) -> some View {
        content.alert(
            "Подтвердите действие",
            isPresented: isPresented,
            presenting: session?.currentConfirmation
        ) { confirmation in
            Button("Отклонить", role: .cancel) {
                session?.resolve(confirmation, approved: false)
            }
            Button("Разрешить") {
                session?.resolve(confirmation, approved: true)
            }
        } message: { confirmation in
            if confirmation.arguments.isEmpty {
                Text("Ассистент хочет выполнить: \(confirmation.title).")
            } else {
                Text("Ассистент хочет выполнить: \(confirmation.title).\n\(confirmation.arguments)")
            }
        }
    }

    /// An alert can only be dismissed through one of its buttons, and both
    /// buttons resolve the call explicitly. The setter therefore does nothing:
    /// deciding here as well would race the button action, and whichever ran
    /// first would win — silently denying an approval on some SwiftUI versions.
    /// Presentation is driven purely by the queue, which `resolve` pops.
    private var isPresented: Binding<Bool> {
        Binding(
            get: { session?.currentConfirmation != nil },
            set: { _ in }
        )
    }
}
