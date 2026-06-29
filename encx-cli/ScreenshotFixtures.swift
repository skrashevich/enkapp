import Foundation

enum ScreenshotFixtureError: Error {
    case invalidFixture(String)
}

extension EncounterViewModel {
    static func screenshotModelIfRequested() -> EncounterViewModel? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--screenshots") else { return nil }
        let screen: AppScreen
        if arguments.contains("--screenshot-team") {
            screen = .team
        } else if arguments.contains("--screenshot-game") {
            screen = .game
        } else {
            screen = .games
        }
        return screenshotModel(selectedScreen: screen)
    }

    static func screenshotModel(selectedScreen: AppScreen) -> EncounterViewModel {
        let model = EncounterViewModel()
        model.applyScreenshotFixture(selectedScreen: selectedScreen)
        return model
    }

    func applyScreenshotFixture(selectedScreen: AppScreen = .games) {
        settings = DomainSettings()
        settings.domain = "moscow.en.cx"
        settings.liveActivityEnabled = false
        settings.pushOnNewLevel = false
        settings.pushOnNewHint = false
        login = "svk"
        games = Self.decodeFixture([GameInfo].self, from: Self.gamesJSON)
        domainGames = Self.decodeFixture([DomainGame].self, from: Self.domainGamesJSON)
        selectedGameID = 82034
        currentModel = Self.decodeFixture(GameModel.self, from: Self.gameJSON)
        myTeams = Self.decodeFixture([TeamInfo].self, from: Self.myTeamsJSON)
        selectedTeamID = 404
        teamManagementInfo = Self.decodeFixture(TeamManagementInfo.self, from: Self.teamManagementJSON)
        teamInvitations = Self.decodeFixture([TeamInvitation].self, from: Self.teamInvitationsJSON)
        gameStartCountdown = nil
        self.selectedScreen = selectedScreen
        statusMessage = "Демо-режим для скриншотов"
        serverRoundTripMs = 87
    }

    private static func decodeFixture<T: Decodable>(_ type: T.Type, from json: String) -> T {
        do {
            return try JSONDecoder().decode(type, from: Data(json.utf8))
        } catch {
            preconditionFailure("Invalid screenshot fixture for \(type): \(error)")
        }
    }

    private static let gamesJSON = """
    [
      {
        "GameID": 82034,
        "GameNum": 82034,
        "Title": "Межрег в екенях",
        "Descr": "В допах загранпаспорт",
        "Started": true,
        "Finished": false,
        "InProgress": true,
        "IsModerated": false,
        "LevelNumber": 4
      },
      {
        "GameID": 82052,
        "GameNum": 82052,
        "Title": "Фотоохота: старые вывески",
        "Descr": "Не хабарить!",
        "Started": false,
        "Finished": false,
        "InProgress": false,
        "IsModerated": true,
        "LevelNumber": null
      },
      {
        "GameID": 82061,
        "GameNum": 82061,
        "Title": "Квест по метро",
        "Descr": "Найди себя на Выхино",
        "Started": false,
        "Finished": false,
        "InProgress": false,
        "IsModerated": false,
        "LevelNumber": null
      }
    ]
    """

    private static let domainGamesJSON = """
    [
      { "gameId": 82071, "title": "Архивный EN-спринт" },
      { "gameId": 82072, "title": "Тренировка кодов" }
    ]
    """

    private static let myTeamsJSON = """
    [
      { "teamId": 404, "name": "Команда 404" },
      { "teamId": 512, "name": "Байты и кофе" },
      { "teamId": 777, "name": "Ночные координаты" }
    ]
    """

    private static let teamInvitationsJSON = """
    [
      { "team_id": 901, "name": "Секретный отдел", "action": "accept" },
      { "team_id": 902, "name": "Полевой штаб", "action": "accept" }
    ]
    """

    private static let teamManagementJSON = """
    {
      "team_id": 404,
      "team_name": "Команда 404",
      "pending_invitations": [
        { "user_id": 101, "login": "alice" },
        { "user_id": 102, "login": "bob" },
        { "user_id": 103, "login": "charlie" }
      ],
      "actions": {
        "invite": "/team/invite",
        "leave": "/team/leave"
      }
    }
    """

    private static let gameJSON = """
    {
      "Event": 0,
      "GameId": 82034,
      "GameTitle": "Межрег в екенях",
      "Login": "svk",
      "TeamName": "Команда 404",
      "FinishPlace": 3,
      "Levels": [
        { "LevelId": 1, "LevelNumber": 1, "LevelName": "Разминка", "Dismissed": false, "IsPassed": true },
        { "LevelId": 2, "LevelNumber": 2, "LevelName": "Двор-колодец", "Dismissed": false, "IsPassed": true },
        { "LevelId": 3, "LevelNumber": 3, "LevelName": "Переход", "Dismissed": false, "IsPassed": true },
        { "LevelId": 4, "LevelNumber": 4, "LevelName": "Башня", "Dismissed": false, "IsPassed": false },
        { "LevelId": 5, "LevelNumber": 5, "LevelName": "Финал", "Dismissed": false, "IsPassed": false }
      ],
      "Level": {
        "LevelId": 4,
        "Number": 4,
        "Name": "Башня",
        "TimeoutSecondsRemain": 3160,
        "IsPassed": false,
        "Dismissed": false,
        "HasAnswerBlockRule": true,
        "BlockDuration": 60,
        "AttemtsNumber": 3,
        "AttemtsPeriod": 60,
        "RequiredSectorsCount": 5,
        "PassedSectorsCount": 2,
        "PassedBonusesCount": 1,
        "SectorsLeftToClose": 3,
        "Tasks": [
          {
            "TaskText": "Найдите башню с часами. И забейте на неё, потому что код спрятан на крыше будки охраны.",
            "TaskTextFormatted": ""
          }
        ],
        "Task": null,
        "Messages": [
          {
            "MessageId": 101,
            "OwnerLogin": "org",
            "MessageText": "Проверяйте формат: EN123",
            "WrappedText": ""
          }
        ],
        "Sectors": [
          { "SectorId": 41, "Order": 1, "Name": "Сектор 1", "IsAnswered": true, "Answer": "EN841" },
          { "SectorId": 42, "Order": 2, "Name": "Сектор 2", "IsAnswered": true, "Answer": "CLOCK" },
          { "SectorId": 43, "Order": 3, "Name": "Сектор 3", "IsAnswered": false, "Answer": "" },
          { "SectorId": 44, "Order": 4, "Name": "Сектор 4", "IsAnswered": false, "Answer": "" },
          { "SectorId": 45, "Order": 5, "Name": "Сектор 5", "IsAnswered": false, "Answer": "" }
        ],
        "Helps": [
          {
            "HelpId": 1,
            "Number": 1,
            "HelpText": "Смотрите на северную сторону здания.",
            "IsPenalty": false,
            "Penalty": 0,
            "RequestConfirm": false,
            "PenaltyHelpState": 0,
            "RemainSeconds": 0,
            "PenaltyMessage": null
          },
          {
            "HelpId": 2,
            "Number": 2,
            "HelpText": "Север -- там где мох",
            "IsPenalty": false,
            "Penalty": 0,
            "RequestConfirm": false,
            "PenaltyHelpState": 0,
            "RemainSeconds": 0,
            "PenaltyMessage": null
          }
        ],
        "Bonuses": [
          {
            "BonusId": 1,
            "Name": "Кофейня",
            "Number": 1,
            "Task": "Найдите вывеску с латте-артом.",
            "Help": "латте-арт -- это когда на кофе рисуют узор из молока",
            "IsAnswered": true,
            "Answer": "LATTE",
            "Expired": false,
            "SecondsToStart": 0,
            "SecondsLeft": 900,
            "AwardTime": 300,
            "Negative": false
          }
        ],
        "PenaltyHelps": [],
        "MixedActions": [
          { "ActionId": 1, "LevelNumber": 4, "Kind": 1, "Login": "svk", "Answer": "EN841", "IsCorrect": true, "LocDateTime": "22:17" },
          { "ActionId": 2, "LevelNumber": 4, "Kind": 1, "Login": "svk", "Answer": "CLOCK", "IsCorrect": true, "LocDateTime": "22:24" },
          { "ActionId": 3, "LevelNumber": 4, "Kind": 1, "Login": "svk", "Answer": "TOWER", "IsCorrect": false, "LocDateTime": "22:31" }
        ]
      },
      "EngineAction": null
    }
    """
}
