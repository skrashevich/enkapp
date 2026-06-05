import AppIntents

struct SubmitCodeIntent: AppIntent {
    static var title: LocalizedStringResource = "Отправить код"
    static var description = IntentDescription("Отправляет код на текущий уровень активной игры Encounter.")
    static var openAppWhenRun = false

    @Parameter(title: "Код")
    var code: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let message = try await EncounterShortcutService.shared.submitCode(code)
        return .result(value: message, dialog: IntentDialog(stringLiteral: message))
    }
}

struct GetGameStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Статус игры"
    static var description = IntentDescription("Показывает уровень, команду и очередь кодов активной игры.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let status = try await EncounterShortcutService.shared.gameStatusSummary()
        return .result(value: status.summary, dialog: IntentDialog(stringLiteral: status.summary))
    }
}

struct FlushQueueIntent: AppIntent {
    static var title: LocalizedStringResource = "Отправить очередь"
    static var description = IntentDescription("Отправляет накопленные коды из очереди на сервер Encounter.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let message = try await EncounterShortcutService.shared.flushQueue()
        return .result(value: message, dialog: IntentDialog(stringLiteral: message))
    }
}

struct EnkappShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SubmitCodeIntent(),
            phrases: [
                "Отправить код в \(.applicationName)",
                "Отправить код Encounter в \(.applicationName)",
            ],
            shortTitle: "Отправить код",
            systemImageName: "number"
        )
        AppShortcut(
            intent: GetGameStatusIntent(),
            phrases: [
                "Статус игры в \(.applicationName)",
                "Уровень Encounter в \(.applicationName)",
            ],
            shortTitle: "Статус игры",
            systemImageName: "gamecontroller"
        )
        AppShortcut(
            intent: FlushQueueIntent(),
            phrases: [
                "Отправить очередь в \(.applicationName)",
                "Сбросить очередь кодов в \(.applicationName)",
            ],
            shortTitle: "Отправить очередь",
            systemImageName: "arrow.up.circle"
        )
    }
}
