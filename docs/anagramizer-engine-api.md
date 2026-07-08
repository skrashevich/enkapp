# Контракт: API движка анаграмайзера (Swift, v1)

Общий контракт между **движком** (Track B) и **UI** (Track C). UI кодит против этих типов/протокола;
движок их реализует. Пока движок не готов — UI использует мок, соответствующий этому протоколу.

## Типы запроса

```swift
enum AnagramMode: Equatable {
    case pattern            // шаблон: фикс-буквы + джокер на позицию
    case anagram            // точные перестановки заданного набора (длина = |набор|)
    case subword            // любое подмножество заданных букв
    case combined           // часть позиций фиксирована + остальное из набора (Scrabble)
}

struct AnagramQuery: Equatable {
    var mode: AnagramMode
    var pattern: String     // для .pattern/.combined: буквы + символ-джокер (см. jokerChar); напр. "к_т"
    var letters: String     // для .anagram/.subword/.combined: доступные буквы (могут включать бланк)
    var minLength: Int?     // фильтр
    var maxLength: Int?     // фильтр
    var foldYo: Bool        // true → трактовать ё=е
    var blankCount: Int     // число бланков/джокеров-букв (пустая клетка = любая буква); 0 по умолчанию
    var sort: AnagramSort   // порядок результатов
}

enum AnagramSort: Equatable { case byLengthDesc, byLengthAsc, alphabetical }

// Символ-джокер в pattern (одна позиция = любая буква). Договорённость:
// принимать '_' , '.' , '?' и '*' как джокер одной позиции.
```

## Результат

```swift
struct AnagramResultPage: Equatable {
    var words: [String]     // страница результатов (кириллица, нижний регистр)
    var totalCount: Int     // общее число совпадений (может быть > words.count)
    var hasMore: Bool       // есть ли ещё за пределами текущей страницы
}
```

## Протокол движка

```swift
protocol AnagramEngine: AnyObject {
    // Готов ли словарь (mmap загружен, индексы построены). Меняется на true off-main.
    var isReady: Bool { get }

    // Выполнить запрос. ДОЛЖЕН вызываться вне MainActor (тяжёлый скан).
    // limit — размер страницы; offset — смещение для пагинации.
    // Бросает AnagramEngineError при не-готовности/повреждении.
    func search(_ query: AnagramQuery, limit: Int, offset: Int) throws -> AnagramResultPage
}

enum AnagramEngineError: Error, Equatable {
    case notReady
    case dictionaryUnavailable   // ресурс не найден
    case dictionaryCorrupt       // magic/version/границы не сошлись
    case invalidQuery(String)    // пустой ввод, недопустимые символы и т.п.
}
```

## Загрузчик (off-main)

```swift
// Загружает словарь через mmap вне MainActor. Возвращает готовый движок или бросает ошибку.
// Реализация: Data(contentsOf: url, options: .mappedIfSafe), парсинг header/length-table,
// НЕ материализовать слова в String.
enum AnagramDictionaryLoader {
    static func loadBundledDictionary() async throws -> AnagramEngine
    // Ищет ресурс "ru_dict.bin" (или согласованное имя) в Bundle.main.
}
```

## Ограничения/поведение
- **Нормализация ввода**: lowercase; отсев символов вне русского алфавита (латиница/цифры) → либо `.invalidQuery`, либо игнор с подсказкой (UI решает отображение). Джокер-символы разрешены в pattern.
- **foldYo=true**: и словарь, и ввод приводятся к коду 5 (е) при сопоставлении.
- **Лимит результатов**: движок отдаёт страницами (limit/offset). Сортировка выполняется движком (на фоне), не в UI на MainActor.
- **Пустой ввод** → `.invalidQuery`.
- Все тяжёлые операции — вне MainActor; UI публикует результат на MainActor сам.

## Имя ресурса словаря
Согласованное имя бандл-ресурса: **`ru_dict.bin`** в `Bundle.main`. Генератор кладёт файл так, чтобы он попал в бандл основного приложения (synchronized groups — достаточно положить в папку `encx-cli/Resources/`).
