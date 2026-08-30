import Foundation

nonisolated enum CodeLogCSVFormatter {
    static func data(for actions: [CodeAction]) -> Data {
        let header = [
            "Уровень",
            "Дата и время",
            "Игрок",
            "Код",
            "Тип",
            "Результат",
            "ID действия",
        ]
        let rows = actions.map { action in
            [
                String(action.levelNumber),
                action.locDateTime,
                action.login,
                action.answer,
                kindLabel(for: action.kind),
                action.isCorrect ? "Верно" : "Неверно",
                String(action.actionID),
            ]
        }
        let csv = ([header] + rows)
            .map { $0.map(escapedField).joined(separator: ",") }
            .joined(separator: "\r\n") + "\r\n"

        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(contentsOf: csv.utf8)
        return data
    }

    private static func escapedField(_ value: String) -> String {
        let safeValue = spreadsheetSafeField(value)
        return "\"\(safeValue.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func spreadsheetSafeField(_ value: String) -> String {
        let ignoredPrefixCharacters = CharacterSet.whitespacesAndNewlines
            .union(.controlCharacters)
        guard let firstSignificantScalar = value.unicodeScalars.first(where: {
            !ignoredPrefixCharacters.contains($0)
        }), CharacterSet(charactersIn: "=+-@").contains(firstSignificantScalar) else {
            return value
        }
        return "'\(value)"
    }

    private static func kindLabel(for kind: Int) -> String {
        switch kind {
        case 1: return "Уровень"
        case 2: return "Бонус"
        default: return "Другое (\(kind))"
        }
    }
}
