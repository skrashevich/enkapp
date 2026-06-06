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

struct GetTeamStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Статус команды"
    static var description = IntentDescription("Показывает текущую команду, входящие и отправленные приглашения.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let status = try await EncounterShortcutService.shared.teamStatusSummary()
        return .result(value: status.summary, dialog: IntentDialog(stringLiteral: status.summary))
    }
}

struct RequestTeamMembershipIntent: AppIntent {
    static var title: LocalizedStringResource = "Подать заявку в команду"
    static var description = IntentDescription("Отправляет заявку на вступление в команду по её названию.")
    static var openAppWhenRun = false

    @Parameter(title: "Название команды")
    var teamName: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let message = try await EncounterShortcutService.shared.requestTeamMembership(teamName)
        return .result(value: message, dialog: IntentDialog(stringLiteral: message))
    }
}

struct AcceptTeamInvitationIntent: AppIntent {
    static var title: LocalizedStringResource = "Принять приглашение в команду"
    static var description = IntentDescription("Принимает входящее приглашение в команду по ID команды.")
    static var openAppWhenRun = false

    @Parameter(title: "ID команды")
    var teamID: Int

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let message = try await EncounterShortcutService.shared.acceptTeamInvitation(teamID: Int64(teamID))
        return .result(value: message, dialog: IntentDialog(stringLiteral: message))
    }
}

struct RejectTeamInvitationIntent: AppIntent {
    static var title: LocalizedStringResource = "Отклонить приглашение в команду"
    static var description = IntentDescription("Отклоняет входящее приглашение в команду по ID команды.")
    static var openAppWhenRun = false

    @Parameter(title: "ID команды")
    var teamID: Int

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let message = try await EncounterShortcutService.shared.rejectTeamInvitation(teamID: Int64(teamID))
        return .result(value: message, dialog: IntentDialog(stringLiteral: message))
    }
}

struct InviteTeamMemberIntent: AppIntent {
    static var title: LocalizedStringResource = "Пригласить игрока"
    static var description = IntentDescription("Отправляет приглашение игроку в текущую команду по логину.")
    static var openAppWhenRun = false

    @Parameter(title: "Логин игрока")
    var login: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let message = try await EncounterShortcutService.shared.inviteTeamMember(login: login)
        return .result(value: message, dialog: IntentDialog(stringLiteral: message))
    }
}

struct RemoveTeamInvitationIntent: AppIntent {
    static var title: LocalizedStringResource = "Отозвать приглашение игроку"
    static var description = IntentDescription("Отзывает отправленное приглашение игроку по ID игрока.")
    static var openAppWhenRun = false

    @Parameter(title: "ID игрока")
    var userID: Int

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let message = try await EncounterShortcutService.shared.removeTeamInvitation(userID: Int64(userID))
        return .result(value: message, dialog: IntentDialog(stringLiteral: message))
    }
}

struct LeaveTeamIntent: AppIntent {
    static var title: LocalizedStringResource = "Выйти из команды"
    static var description = IntentDescription("Выходит из текущей команды, если Encounter разрешает это действие.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let message = try await EncounterShortcutService.shared.leaveCurrentTeam()
        return .result(value: message, dialog: IntentDialog(stringLiteral: message))
    }
}

struct RenameTeamIntent: AppIntent {
    static var title: LocalizedStringResource = "Переименовать команду"
    static var description = IntentDescription("Меняет название текущей команды.")
    static var openAppWhenRun = false

    @Parameter(title: "Новое название")
    var name: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let message = try await EncounterShortcutService.shared.renameCurrentTeam(name)
        return .result(value: message, dialog: IntentDialog(stringLiteral: message))
    }
}

struct UpdateTeamSiteIntent: AppIntent {
    static var title: LocalizedStringResource = "Обновить сайт команды"
    static var description = IntentDescription("Меняет сайт текущей команды. Пустое значение очищает сайт.")
    static var openAppWhenRun = false

    @Parameter(title: "Сайт")
    var site: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let message = try await EncounterShortcutService.shared.updateCurrentTeamSite(site)
        return .result(value: message, dialog: IntentDialog(stringLiteral: message))
    }
}

struct UpdateTeamForumIntent: AppIntent {
    static var title: LocalizedStringResource = "Обновить форум команды"
    static var description = IntentDescription("Меняет форум текущей команды. Пустое значение очищает форум.")
    static var openAppWhenRun = false

    @Parameter(title: "Форум")
    var forum: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let message = try await EncounterShortcutService.shared.updateCurrentTeamForum(forum)
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
        AppShortcut(
            intent: GetTeamStatusIntent(),
            phrases: [
                "Статус команды в \(.applicationName)",
                "Показать команду в \(.applicationName)",
            ],
            shortTitle: "Статус команды",
            systemImageName: "person.2"
        )
        AppShortcut(
            intent: RequestTeamMembershipIntent(),
            phrases: [
                "Подать заявку в команду в \(.applicationName)",
                "Вступить в команду в \(.applicationName)",
            ],
            shortTitle: "Заявка",
            systemImageName: "person.badge.plus"
        )
        AppShortcut(
            intent: AcceptTeamInvitationIntent(),
            phrases: [
                "Принять приглашение в команду в \(.applicationName)",
                "Войти в приглашённую команду в \(.applicationName)",
            ],
            shortTitle: "Принять",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: RejectTeamInvitationIntent(),
            phrases: [
                "Отклонить приглашение в команду в \(.applicationName)",
                "Отказаться от команды в \(.applicationName)",
            ],
            shortTitle: "Отклонить",
            systemImageName: "xmark.circle"
        )
        AppShortcut(
            intent: InviteTeamMemberIntent(),
            phrases: [
                "Пригласить игрока в \(.applicationName)",
                "Добавить игрока в команду в \(.applicationName)",
            ],
            shortTitle: "Пригласить",
            systemImageName: "person.crop.circle.badge.plus"
        )
        AppShortcut(
            intent: RemoveTeamInvitationIntent(),
            phrases: [
                "Отозвать приглашение игроку в \(.applicationName)",
                "Убрать приглашение игроку в \(.applicationName)",
            ],
            shortTitle: "Отозвать",
            systemImageName: "person.crop.circle.badge.xmark"
        )
        AppShortcut(
            intent: RenameTeamIntent(),
            phrases: [
                "Переименовать команду в \(.applicationName)",
                "Сменить название команды в \(.applicationName)",
            ],
            shortTitle: "Название",
            systemImageName: "textformat"
        )
    }
}
