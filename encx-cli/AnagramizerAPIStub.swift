import Foundation

// MARK: - Мок движка (Track C)
//
// Track B (encx-cli/Anagramizer/) уже определил AnagramEngine, AnagramQuery, AnagramMode,
// AnagramSort, AnagramResultPage, AnagramEngineError и AnagramDictionaryLoader —
// эти типы отсюда НЕ дублируются.
//
// Здесь только MockAnagramEngine — для SwiftUI Preview, не завязанной на реальный словарь.

/// Лёгкий мок движка — для Preview и для работы UI, пока реальный движок не подключён.
/// Возвращает пару фиктивных слов, отфильтрованных грубо по длине/первой букве.
final class MockAnagramEngine: AnagramEngine {
    private let sampleWords = [
        "кот", "ток", "отк", "стол", "лото", "толк", "полк", "волк",
        "автор", "товар", "отвар", "актёр", "терка", "карет", "ветка",
        "берег", "грёбе", "обрез", "резьба", "разбег"
    ]

    var isReady: Bool { true }

    func search(_ query: AnagramQuery, limit: Int, offset: Int) throws -> AnagramResultPage {
        let normalizedPattern = query.foldYo ? query.pattern.replacingOccurrences(of: "ё", with: "е") : query.pattern
        let normalizedLetters = query.foldYo ? query.letters.replacingOccurrences(of: "ё", with: "е") : query.letters

        if normalizedPattern.isEmpty && normalizedLetters.isEmpty {
            throw AnagramEngineError.invalidQuery("Пустой ввод")
        }

        var matches = sampleWords.filter { word in
            if let minLength = query.minLength, word.count < minLength { return false }
            if let maxLength = query.maxLength, word.count > maxLength { return false }
            return true
        }

        switch query.sort {
        case .byLengthDesc:
            matches.sort { $0.count > $1.count }
        case .byLengthAsc:
            matches.sort { $0.count < $1.count }
        case .alphabetical:
            matches.sort()
        }

        let total = matches.count
        let start = min(offset, total)
        let end = min(offset + limit, total)
        let page = start < end ? Array(matches[start..<end]) : []
        return AnagramResultPage(words: page, totalCount: total, hasMore: end < total)
    }
}
