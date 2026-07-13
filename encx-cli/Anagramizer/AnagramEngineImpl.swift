import Foundation

// MARK: - Движок поиска (реализация AnagramEngine)
//
// Все запросы синхронны и предназначены для вызова вне MainActor (nonisolated).
// Слова не материализуются в String во время скана — только на этапе выдачи страницы.

/// Реализация движка поиска поверх mmap-ридера.
///
/// `@unchecked Sendable`: единственное мутабельное состояние — кэш последнего
/// запроса (`cachedKey`/`cachedMatches`), доступ к которому сериализуется `cacheLock`.
/// Ридер и коды иммутабельны. Явная `nonisolated`-разметка (на типе) снимает
/// `-default-isolation MainActor` со ВСЕХ членов — хранимых свойств кэша,
/// static-констант и вложенного `CacheKey` — чтобы тяжёлый скан реально
/// исполнялся вне MainActor.
public nonisolated final class AnagramEngineImpl: AnagramEngine, @unchecked Sendable {

    private let reader: AnagramDictionaryReader

    /// Готовность: ридер построен успешно.
    public nonisolated var isReady: Bool { true }

    // MARK: Кэш последнего запроса (FIX 3)
    //
    // Один слот: keyed по нормализованному запросу (mode+pattern+letters+фильтры+
    // foldYo+blankCount+sort, БЕЗ limit/offset). Храним уже отсортированный
    // матч-лист [[UInt8]]; пагинация становится срезом без повторного скана.

    /// Ключ кэша — запрос без limit/offset (они не влияют на матч-лист).
    private struct CacheKey: Equatable {
        let query: AnagramQuery
    }

    private let cacheLock = NSLock()
    private var cachedKey: CacheKey?
    private var cachedMatches: [[UInt8]] = []

    // MARK: Инициализация

    /// Инициализация из готовых mmap-данных (для харнесса/тестов).
    public nonisolated init(data: Data) throws {
        self.reader = try AnagramDictionaryReader(data: data)
    }

    /// Инициализация из URL: mmap-чтение файла словаря (для харнесса/тестов).
    public nonisolated convenience init(dictionaryURL url: URL) throws {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw AnagramEngineError.dictionaryUnavailable
        }
        try self.init(data: data)
    }

    // MARK: - Публичный поиск

    public nonisolated func search(_ query: AnagramQuery, limit: Int, offset: Int) throws -> AnagramResultPage {
        guard limit >= 0, offset >= 0 else {
            throw AnagramEngineError.invalidQuery("limit/offset must be non-negative")
        }

        // Отсортированный матч-лист: из кэша при повторе того же запроса, иначе — скан.
        let sorted = try sortedMatches(for: query)

        let total = sorted.count

        // Пагинация — простой срез отсортированного списка.
        let start = min(offset, total)
        let end = min(offset + limit, total)
        let pageCodes = (start < end) ? Array(sorted[start..<end]) : []

        let words = pageCodes.map { codes -> String in
            AnagramCodec.decode(codes) ?? ""
        }
        let hasMore = end < total
        return AnagramResultPage(words: words, totalCount: total, hasMore: hasMore)
    }

    // MARK: - Кэш + скан (FIX 3)

    /// Возвращает отсортированный матч-лист для запроса.
    /// При повторном запросе с тем же ключом (другой offset/limit) — из кэша,
    /// без повторного скана и сортировки. При смене запроса кэш инвалидируется.
    private nonisolated func sortedMatches(for query: AnagramQuery) throws -> [[UInt8]] {
        let key = CacheKey(query: query)

        // Быстрый путь: кэш-хит.
        cacheLock.lock()
        if cachedKey == key {
            let hit = cachedMatches
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        // Промах: полный скан + сортировка (может бросить CancellationError / invalidQuery).
        let matches = try collectMatches(query)
        let filtered = excludeInputWord(matches, query: query)
        let sorted = applySort(filtered, sort: query.sort)

        // Записываем в кэш только полностью завершённый (не отменённый) результат.
        try Self.checkCancellation()
        cacheLock.lock()
        cachedKey = key
        cachedMatches = sorted
        cacheLock.unlock()

        return sorted
    }

    // MARK: - Исключение входного слова

    /// Убирает из выдачи слово, совпадающее с введённым набором букв: пользователь
    /// ищет другие слова, а не собственный ввод. Сравнение — по кодам с учётом
    /// foldYo (в матчах коды словаря сырые, ё не свёрнута). Для .pattern letters
    /// пуст — фильтр не срабатывает.
    private nonisolated func excludeInputWord(_ matches: [[UInt8]], query: AnagramQuery) -> [[UInt8]] {
        let input = AnagramCodec.encode(query.letters, foldYo: query.foldYo).codes
        guard !input.isEmpty else { return matches }
        let foldYo = query.foldYo
        return matches.filter { codes in
            guard codes.count == input.count else { return true }
            for i in 0..<codes.count where AnagramCodec.fold(codes[i], foldYo: foldYo) != input[i] {
                return true
            }
            return false
        }
    }

    // MARK: - Кооперативная отмена (FIX 2)

    /// Порог: проверяем отмену раз в N обработанных слов, чтобы не платить за
    /// `Task.isCancelled` на каждом слове.
    private static let cancellationCheckStride = 4096

    /// Бросает `CancellationError`, если объемлющий `Task` отменён.
    /// Синхронный `Task.isCancelled` читается корректно и внутри sync-кода.
    @inline(__always)
    private nonisolated static func checkCancellation() throws {
        if Task.isCancelled { throw CancellationError() }
    }

    // MARK: - Сбор совпадений

    /// Возвращает список совпадений как массивы кодов (нормализованных foldYo при необходимости).
    private nonisolated func collectMatches(_ query: AnagramQuery) throws -> [[UInt8]] {
        try Self.checkCancellation()
        switch query.mode {
        case .pattern:
            return try matchPattern(query)
        case .anagram:
            return try matchAnagram(query)
        case .subword:
            return try matchSubword(query)
        case .combined:
            return try matchCombined(query)
        }
    }

    // MARK: Диапазон длин с учётом фильтров

    /// Ограничивает [lo, hi] фильтрами min/max и допустимым диапазоном словаря [1, maxLen].
    private nonisolated func clampedLengthRange(lo: Int, hi: Int, query: AnagramQuery) -> ClosedRange<Int>? {
        var low = max(1, lo)
        var high = min(reader.maxLen, hi)
        if let mn = query.minLength { low = max(low, mn) }
        if let mx = query.maxLength { high = min(high, mx) }
        guard low <= high, low >= 1 else { return nil }
        return low...high
    }

    // MARK: - Разбор шаблона

    /// Токен разобранного шаблона.
    /// - `.fixed` — конкретная буква (должна совпасть точно).
    /// - `.single` — плейсхолдер на одну позицию (`_`, `.`, `?`).
    /// - `.star` — плейсхолдер на любое число позиций, включая ноль (`*`).
    private enum PatternToken: Equatable {
        case fixed(UInt8)
        case single
        case star
    }

    /// Одиночные плейсхолдеры: ровно один любой символ.
    private static let singleJokers: Set<Character> = ["_", ".", "?"]
    /// Плейсхолдер переменной длины: ноль или более любых символов.
    private static let starJoker: Character = "*"

    /// Разбирает шаблон в список токенов. Идущие подряд `*` схлопываются в один
    /// (эквивалентны, а один звёздный токен исключает экспоненциальный перебор).
    /// Возвращает nil при недопустимом символе (не буква и не плейсхолдер).
    private nonisolated func parsePatternTokens(_ pattern: String, foldYo: Bool) -> [PatternToken]? {
        var tokens: [PatternToken] = []
        for ch in pattern.lowercased() {
            if ch == AnagramEngineImpl.starJoker {
                if tokens.last == .star { continue } // схлопываем «**» → «*»
                tokens.append(.star)
                continue
            }
            if AnagramEngineImpl.singleJokers.contains(ch) {
                tokens.append(.single)
                continue
            }
            guard let code = AnagramCodec.code(for: ch) else {
                return nil // недопустимый символ
            }
            tokens.append(.fixed(AnagramCodec.fold(code, foldYo: foldYo)))
        }
        return tokens
    }

    // MARK: - .pattern

    private nonisolated func matchPattern(_ query: AnagramQuery) throws -> [[UInt8]] {
        guard let tokens = parsePatternTokens(query.pattern, foldYo: query.foldYo), !tokens.isEmpty else {
            throw AnagramEngineError.invalidQuery("empty or invalid pattern")
        }
        let hasStar = tokens.contains(.star)
        // Минимальная длина слова = число нестар-токенов (каждый занимает 1 позицию).
        let minLen = tokens.reduce(0) { $0 + ($1 == .star ? 0 : 1) }

        // Без `*` длина слова фиксирована длиной шаблона; со `*` — диапазон до maxLen.
        // Фильтры min/max могут отсечь весь диапазон.
        let hi = hasStar ? reader.maxLen : minLen
        guard let range = clampedLengthRange(lo: minLen, hi: hi, query: query) else {
            return []
        }

        var out: [[UInt8]] = []
        let foldYo = query.foldYo
        var cancelled = false
        for L in range {
            // Проверка отмены между length-бакетами (дешёвая точка выхода).
            try Self.checkCancellation()
            reader.forEachWord(length: L) { buf, index in
                // Кооперативная отмена: раз в stride проверяем Task.isCancelled.
                if index & (AnagramEngineImpl.cancellationCheckStride - 1) == 0, Task.isCancelled {
                    cancelled = true
                    return false
                }
                if AnagramEngineImpl.globMatch(word: buf, tokens: tokens, foldYo: foldYo) {
                    out.append(Array(buf))
                }
                return true
            }
            if cancelled { throw CancellationError() }
        }
        return out
    }

    /// Glob-сопоставление слова с токенами: `.single` = один любой символ,
    /// `.star` = ноль или более любых символов. Классический двухуказательный
    /// алгоритм с откатом к последней `*` (O(n·m), без аллокаций).
    private nonisolated static func globMatch(
        word: UnsafeBufferPointer<UInt8>,
        tokens: [PatternToken],
        foldYo: Bool
    ) -> Bool {
        let n = word.count
        let m = tokens.count
        var i = 0            // индекс в слове
        var j = 0            // индекс в токенах
        var starIdx = -1     // позиция последней `*` в токенах
        var matchIdx = 0     // индекс в слове, откуда `*` начала поглощать
        while i < n {
            if j < m {
                switch tokens[j] {
                case .star:
                    starIdx = j
                    matchIdx = i
                    j += 1
                    continue
                case .single:
                    i += 1; j += 1
                    continue
                case .fixed(let code):
                    if AnagramCodec.fold(word[i], foldYo: foldYo) == code {
                        i += 1; j += 1
                        continue
                    }
                }
            }
            // Рассогласование или токены кончились — откат к последней `*`.
            if starIdx != -1 {
                j = starIdx + 1
                matchIdx += 1
                i = matchIdx
            } else {
                return false
            }
        }
        // Хвост из токенов допустим, только если это оставшиеся `*`.
        while j < m, tokens[j] == .star { j += 1 }
        return j == m
    }

    // MARK: - .anagram

    /// Точные перестановки набора: длина слова = |набор|, мультимножество кодов совпадает.
    private nonisolated func matchAnagram(_ query: AnagramQuery) throws -> [[UInt8]] {
        let enc = AnagramCodec.encode(query.letters, foldYo: query.foldYo)
        let letters = enc.codes
        let blanks = max(0, query.blankCount)
        let targetLen = letters.count + blanks
        guard targetLen >= 1 else {
            throw AnagramEngineError.invalidQuery("empty letter set")
        }
        guard clampedLengthRange(lo: targetLen, hi: targetLen, query: query) != nil else {
            return []
        }

        // Сигнатура набора: гистограмма кодов.
        var need = histogram(letters)

        var out: [[UInt8]] = []
        let foldYo = query.foldYo
        var cancelled = false
        reader.forEachWord(length: targetLen) { buf, index in
            if index & (AnagramEngineImpl.cancellationCheckStride - 1) == 0, Task.isCancelled {
                cancelled = true
                return false
            }
            // Проверяем multiset-совпадение с учётом blanks как wildcard.
            if AnagramEngineImpl.multisetMatchesExact(word: buf, need: &need, blanks: blanks, foldYo: foldYo) {
                out.append(Array(buf))
            }
            return true
        }
        if cancelled { throw CancellationError() }
        return out
    }

    // MARK: - .subword

    /// Слова, чьи буквы — подмножество набора (multiset-вложенность), длиной ≤ |набор|.
    private nonisolated func matchSubword(_ query: AnagramQuery) throws -> [[UInt8]] {
        let enc = AnagramCodec.encode(query.letters, foldYo: query.foldYo)
        let letters = enc.codes
        let blanks = max(0, query.blankCount)
        let available = letters.count + blanks
        guard available >= 1 else {
            throw AnagramEngineError.invalidQuery("empty letter set")
        }
        guard let range = clampedLengthRange(lo: 1, hi: available, query: query) else {
            return []
        }

        var have = histogram(letters)

        var out: [[UInt8]] = []
        let foldYo = query.foldYo
        var cancelled = false
        for L in range {
            // Проверка отмены между length-бакетами (дешёвая точка выхода).
            try Self.checkCancellation()
            reader.forEachWord(length: L) { buf, index in
                if index & (AnagramEngineImpl.cancellationCheckStride - 1) == 0, Task.isCancelled {
                    cancelled = true
                    return false
                }
                if AnagramEngineImpl.multisetSubsetOf(word: buf, have: &have, blanks: blanks, foldYo: foldYo) {
                    out.append(Array(buf))
                }
                return true
            }
            if cancelled { throw CancellationError() }
        }
        return out
    }

    // MARK: - .combined

    /// Часть позиций фиксирована (pattern с плейсхолдерами), джокер-позиции
    /// (одиночные `_ . ?` и позиции под `*`) заполняются из набора letters;
    /// blankCount бланков = wildcard-буквы.
    private nonisolated func matchCombined(_ query: AnagramQuery) throws -> [[UInt8]] {
        guard let tokens = parsePatternTokens(query.pattern, foldYo: query.foldYo), !tokens.isEmpty else {
            throw AnagramEngineError.invalidQuery("empty or invalid pattern")
        }
        let enc = AnagramCodec.encode(query.letters, foldYo: query.foldYo)
        let pool = histogram(enc.codes)
        let blanks = max(0, query.blankCount)

        var fixedCount = 0
        var singleCount = 0
        var hasStar = false
        for token in tokens {
            switch token {
            case .fixed: fixedCount += 1
            case .single: singleCount += 1
            case .star: hasStar = true
            }
        }
        // Обязательные джокер-позиции (одиночные) покрываются пулом + бланками.
        guard singleCount <= enc.codes.count + blanks else {
            return []
        }

        // Без `*` длина слова фиксирована длиной шаблона. Со `*` — от minLen
        // (звёзды пустые) до fixedCount + (буквы пула + бланки): каждая нефикс-
        // позиция расходует букву пула или бланк, значит их число ограничено.
        let minLen = fixedCount + singleCount
        let hi = hasStar ? fixedCount + enc.codes.count + blanks : minLen
        guard let range = clampedLengthRange(lo: minLen, hi: hi, query: query) else {
            return []
        }

        var out: [[UInt8]] = []
        let foldYo = query.foldYo
        var cancelled = false
        for L in range {
            try Self.checkCancellation()
            reader.forEachWord(length: L) { buf, index in
                if index & (AnagramEngineImpl.cancellationCheckStride - 1) == 0, Task.isCancelled {
                    cancelled = true
                    return false
                }
                var poolCopy = pool
                var blanksLeft = blanks
                if AnagramEngineImpl.combinedMatch(
                    word: buf, wi: 0, tokens: tokens, ti: 0,
                    pool: &poolCopy, blanks: &blanksLeft, foldYo: foldYo
                ) {
                    out.append(Array(buf))
                }
                return true
            }
            if cancelled { throw CancellationError() }
        }
        return out
    }

    /// Что израсходовано под джокер-позицию — буква пула или бланк (для отката).
    private enum ConsumedUnit {
        case pool(UInt8)
        case blank
    }

    /// Расходует один символ `code` под джокер-позицию: сначала из пула (буква
    /// покрывает только себя), при отсутствии — бланк (покрывает что угодно).
    /// Предпочтение пула бланку оптимально: бланк выгоднее приберечь под символ,
    /// которого в пуле нет. Возвращает nil, если покрыть нечем.
    @inline(__always)
    private nonisolated static func consume(
        _ pool: inout [UInt8: Int], _ blanks: inout Int, _ code: UInt8
    ) -> ConsumedUnit? {
        if let cnt = pool[code], cnt > 0 {
            pool[code] = cnt - 1
            return .pool(code)
        }
        if blanks > 0 {
            blanks -= 1
            return .blank
        }
        return nil
    }

    @inline(__always)
    private nonisolated static func restore(
        _ unit: ConsumedUnit, _ pool: inout [UInt8: Int], _ blanks: inout Int
    ) {
        switch unit {
        case .pool(let code): pool[code, default: 0] += 1
        case .blank: blanks += 1
        }
    }

    /// Рекурсивно проверяет, можно ли выровнять `tokens` на `word`: фикс-токены
    /// совпадают точно (пул не тратят), одиночные плейсхолдеры и позиции под `*`
    /// покрываются буквами пула или бланками. Пул/бланки восстанавливаются при
    /// откате. Слова короткие (≤ maxLen), звёзды схлопнуты — перебор ограничен.
    private nonisolated static func combinedMatch(
        word: UnsafeBufferPointer<UInt8>, wi: Int,
        tokens: [PatternToken], ti: Int,
        pool: inout [UInt8: Int], blanks: inout Int,
        foldYo: Bool
    ) -> Bool {
        if ti == tokens.count {
            return wi == word.count
        }
        switch tokens[ti] {
        case .fixed(let code):
            guard wi < word.count, AnagramCodec.fold(word[wi], foldYo: foldYo) == code else {
                return false
            }
            return combinedMatch(word: word, wi: wi + 1, tokens: tokens, ti: ti + 1,
                                  pool: &pool, blanks: &blanks, foldYo: foldYo)
        case .single:
            guard wi < word.count else { return false }
            let code = AnagramCodec.fold(word[wi], foldYo: foldYo)
            guard let unit = consume(&pool, &blanks, code) else { return false }
            if combinedMatch(word: word, wi: wi + 1, tokens: tokens, ti: ti + 1,
                             pool: &pool, blanks: &blanks, foldYo: foldYo) {
                return true
            }
            restore(unit, &pool, &blanks)
            return false
        case .star:
            // `*` покрывает 0..k позиций; каждая покрытая позиция расходует пул/бланк.
            // Пробуем 0 позиций, затем расширяем на одну за раз с откатом.
            if combinedMatch(word: word, wi: wi, tokens: tokens, ti: ti + 1,
                             pool: &pool, blanks: &blanks, foldYo: foldYo) {
                return true
            }
            var consumed: [ConsumedUnit] = []
            var k = wi
            while k < word.count {
                let code = AnagramCodec.fold(word[k], foldYo: foldYo)
                guard let unit = consume(&pool, &blanks, code) else { break }
                consumed.append(unit)
                if combinedMatch(word: word, wi: k + 1, tokens: tokens, ti: ti + 1,
                                 pool: &pool, blanks: &blanks, foldYo: foldYo) {
                    return true
                }
                k += 1
            }
            for unit in consumed.reversed() { restore(unit, &pool, &blanks) }
            return false
        }
    }

    // MARK: - Мультимножество / гистограммы

    /// Гистограмма кодов: словарь код→кратность.
    private nonisolated func histogram(_ codes: [UInt8]) -> [UInt8: Int] {
        var h: [UInt8: Int] = [:]
        for c in codes { h[c, default: 0] += 1 }
        return h
    }

    /// Точное совпадение мультимножества слова с набором `need` + `blanks` wildcard.
    /// `need` передаётся inout для избежания копий, но восстанавливается перед возвратом.
    private nonisolated static func multisetMatchesExact(
        word: UnsafeBufferPointer<UInt8>,
        need: inout [UInt8: Int],
        blanks: Int,
        foldYo: Bool
    ) -> Bool {
        var blanksLeft = blanks
        var used: [UInt8] = [] // для отката
        var ok = true
        for i in 0..<word.count {
            let code = AnagramCodec.fold(word[i], foldYo: foldYo)
            if let cnt = need[code], cnt > 0 {
                need[code] = cnt - 1
                used.append(code)
            } else if blanksLeft > 0 {
                blanksLeft -= 1
            } else {
                ok = false
                break
            }
        }
        // Для точной анаграммы: всё должно быть израсходовано (длина уже = |набор|+blanks),
        // значит по построению если дошли до конца без нехватки — совпадение точное.
        // Откат need.
        for code in used { need[code, default: 0] += 1 }
        return ok
    }

    /// Проверка, что мультимножество слова ⊆ (`have` + `blanks` wildcard).
    /// `have` восстанавливается перед возвратом.
    private nonisolated static func multisetSubsetOf(
        word: UnsafeBufferPointer<UInt8>,
        have: inout [UInt8: Int],
        blanks: Int,
        foldYo: Bool
    ) -> Bool {
        var blanksLeft = blanks
        var used: [UInt8] = []
        var ok = true
        for i in 0..<word.count {
            let code = AnagramCodec.fold(word[i], foldYo: foldYo)
            if let cnt = have[code], cnt > 0 {
                have[code] = cnt - 1
                used.append(code)
            } else if blanksLeft > 0 {
                blanksLeft -= 1
            } else {
                ok = false
                break
            }
        }
        for code in used { have[code, default: 0] += 1 }
        return ok
    }

    // MARK: - Сортировка

    private nonisolated func applySort(_ matches: [[UInt8]], sort: AnagramSort) -> [[UInt8]] {
        switch sort {
        case .byLengthDesc:
            return matches.sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lexLess(lhs, rhs)
            }
        case .byLengthAsc:
            return matches.sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count < rhs.count }
                return lexLess(lhs, rhs)
            }
        case .alphabetical:
            return matches.sorted { lhs, rhs in lexLess(lhs, rhs) }
        }
    }

    /// Лексикографическое сравнение по кодам (коды отражают алфавитный порядок).
    @inline(__always)
    private nonisolated func lexLess(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        let n = min(a.count, b.count)
        var i = 0
        while i < n {
            if a[i] != b[i] { return a[i] < b[i] }
            i += 1
        }
        return a.count < b.count
    }
}
