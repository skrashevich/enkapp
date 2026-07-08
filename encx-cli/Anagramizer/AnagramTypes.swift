import Foundation

// MARK: - Публичный контракт (см. docs/anagramizer-engine-api.md)
//
// Все типы помечены `nonisolated`: проект собирается с `-default-isolation MainActor`,
// который иначе привязал бы их инициализаторы/члены к MainActor и не дал бы вызывать
// движок из фонового скана. Value-типы иммутабельны и Sendable.

/// Режим поиска.
public nonisolated enum AnagramMode: Equatable, Sendable {
    case pattern            // шаблон: фикс-буквы + джокер на позицию
    case anagram            // точные перестановки заданного набора (длина = |набор|)
    case subword            // любое подмножество заданных букв
    case combined           // часть позиций фиксирована + остальное из набора (Scrabble)
}

/// Порядок сортировки результатов.
public nonisolated enum AnagramSort: Equatable, Sendable {
    case byLengthDesc
    case byLengthAsc
    case alphabetical
}

/// Запрос к движку.
public nonisolated struct AnagramQuery: Equatable, Sendable {
    public var mode: AnagramMode
    public var pattern: String     // для .pattern/.combined: буквы + символ-джокер; напр. "к_т"
    public var letters: String     // для .anagram/.subword/.combined: доступные буквы
    public var minLength: Int?     // фильтр
    public var maxLength: Int?     // фильтр
    public var foldYo: Bool        // true → трактовать ё=е
    public var blankCount: Int     // число бланков/джокеров-букв; 0 по умолчанию
    public var sort: AnagramSort   // порядок результатов

    public init(
        mode: AnagramMode,
        pattern: String = "",
        letters: String = "",
        minLength: Int? = nil,
        maxLength: Int? = nil,
        foldYo: Bool = false,
        blankCount: Int = 0,
        sort: AnagramSort = .byLengthDesc
    ) {
        self.mode = mode
        self.pattern = pattern
        self.letters = letters
        self.minLength = minLength
        self.maxLength = maxLength
        self.foldYo = foldYo
        self.blankCount = blankCount
        self.sort = sort
    }
}

/// Страница результатов.
public nonisolated struct AnagramResultPage: Equatable, Sendable {
    public var words: [String]     // страница результатов (кириллица, нижний регистр)
    public var totalCount: Int     // общее число совпадений (может быть > words.count)
    public var hasMore: Bool       // есть ли ещё за пределами текущей страницы

    public init(words: [String], totalCount: Int, hasMore: Bool) {
        self.words = words
        self.totalCount = totalCount
        self.hasMore = hasMore
    }
}

/// Ошибки движка.
public nonisolated enum AnagramEngineError: Error, Equatable, Sendable {
    case notReady
    case dictionaryUnavailable   // ресурс не найден
    case dictionaryCorrupt       // magic/version/границы не сошлись
    case invalidQuery(String)    // пустой ввод, недопустимые символы и т.п.
}

/// Протокол движка. Реализация — `AnagramEngineImpl`.
/// `Sendable`, потому что движок иммутабелен после инициализации и рассчитан
/// на вызовы из фоновых `Task` вне MainActor.
public nonisolated protocol AnagramEngine: AnyObject, Sendable {
    /// Готов ли словарь (mmap загружен). Меняется на true off-main.
    nonisolated var isReady: Bool { get }

    /// Выполнить запрос. ДОЛЖЕН вызываться вне MainActor (тяжёлый скан).
    /// `limit` — размер страницы; `offset` — смещение для пагинации.
    nonisolated func search(_ query: AnagramQuery, limit: Int, offset: Int) throws -> AnagramResultPage
}
