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
        let sorted = applySort(matches, sort: query.sort)

        // Записываем в кэш только полностью завершённый (не отменённый) результат.
        try Self.checkCancellation()
        cacheLock.lock()
        cachedKey = key
        cachedMatches = sorted
        cacheLock.unlock()

        return sorted
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

    // MARK: - .pattern

    /// Джокер-символы для pattern: _ . ? *
    private static let jokerChars: Set<Character> = ["_", ".", "?", "*"]

    /// Разбирает pattern в маску: элемент = код буквы (фикс) или nil (джокер).
    /// Возвращает nil при недопустимых символах (не буква и не джокер).
    private nonisolated func parsePatternMask(_ pattern: String, foldYo: Bool) -> [UInt8?]? {
        var mask: [UInt8?] = []
        for ch in pattern.lowercased() {
            if AnagramEngineImpl.jokerChars.contains(ch) {
                mask.append(nil)
                continue
            }
            guard let code = AnagramCodec.code(for: ch) else {
                return nil // недопустимый символ
            }
            mask.append(AnagramCodec.fold(code, foldYo: foldYo))
        }
        return mask
    }

    private nonisolated func matchPattern(_ query: AnagramQuery) throws -> [[UInt8]] {
        guard let mask = parsePatternMask(query.pattern, foldYo: query.foldYo), !mask.isEmpty else {
            throw AnagramEngineError.invalidQuery("empty or invalid pattern")
        }
        let L = mask.count
        // Длина фиксирована длиной паттерна; фильтры min/max могут отсечь её целиком.
        guard clampedLengthRange(lo: L, hi: L, query: query) != nil else {
            return []
        }

        var out: [[UInt8]] = []
        let foldYo = query.foldYo
        var cancelled = false
        reader.forEachWord(length: L) { buf, index in
            // Кооперативная отмена: раз в stride проверяем Task.isCancelled.
            if index & (AnagramEngineImpl.cancellationCheckStride - 1) == 0, Task.isCancelled {
                cancelled = true
                return false
            }
            for i in 0..<L {
                if let want = mask[i] {
                    let have = AnagramCodec.fold(buf[i], foldYo: foldYo)
                    if have != want { return true } // не совпало — следующее слово
                }
            }
            out.append(Array(buf))
            return true
        }
        if cancelled { throw CancellationError() }
        return out
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

    /// Часть позиций фиксирована (pattern с джокерами), джокер-позиции заполняются
    /// из доступного набора letters; blankCount бланков = wildcard-буквы.
    private nonisolated func matchCombined(_ query: AnagramQuery) throws -> [[UInt8]] {
        guard let mask = parsePatternMask(query.pattern, foldYo: query.foldYo), !mask.isEmpty else {
            throw AnagramEngineError.invalidQuery("empty or invalid pattern")
        }
        let L = mask.count
        guard clampedLengthRange(lo: L, hi: L, query: query) != nil else {
            return []
        }
        let enc = AnagramCodec.encode(query.letters, foldYo: query.foldYo)
        let pool = histogram(enc.codes)
        let blanks = max(0, query.blankCount)
        // Число джокер-позиций в маске.
        let jokerCount = mask.reduce(0) { $0 + ($1 == nil ? 1 : 0) }
        // Джокер-позиции должны покрываться буквами пула + бланками.
        guard jokerCount <= enc.codes.count + blanks else {
            return []
        }

        var out: [[UInt8]] = []
        let foldYo = query.foldYo
        var cancelled = false
        reader.forEachWord(length: L) { buf, index in
            if index & (AnagramEngineImpl.cancellationCheckStride - 1) == 0, Task.isCancelled {
                cancelled = true
                return false
            }
            // 1) Фиксированные позиции должны совпасть.
            var poolCopy = pool
            var blanksLeft = blanks
            var ok = true
            for i in 0..<L {
                let wordCode = AnagramCodec.fold(buf[i], foldYo: foldYo)
                if let want = mask[i] {
                    if wordCode != want { ok = false; break }
                }
            }
            if !ok { return true }
            // 2) Джокер-позиции покрываются пулом букв (или бланком).
            for i in 0..<L where mask[i] == nil {
                let wordCode = AnagramCodec.fold(buf[i], foldYo: foldYo)
                if let cnt = poolCopy[wordCode], cnt > 0 {
                    poolCopy[wordCode] = cnt - 1
                } else if blanksLeft > 0 {
                    blanksLeft -= 1
                } else {
                    ok = false; break
                }
            }
            if ok { out.append(Array(buf)) }
            return true
        }
        if cancelled { throw CancellationError() }
        return out
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
