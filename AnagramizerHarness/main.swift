import Foundation

// MARK: - Standalone-харнесс движка анаграмайзера
//
// Компиляция:
//   swiftc encx-cli/Anagramizer/*.swift AnagramizerHarness/main.swift -o /tmp/anagram-harness
//   /tmp/anagram-harness
//
// Харнесс:
//  - использует реальный ru_dict.bin (encx-cli/Resources/ru_dict.bin), если он есть;
//    иначе генерирует крошечный синтетический словарь по формату binary-format.md;
//  - при наличии docs/anagram-sample-words.txt делает round-trip проверку;
//  - гоняет юнит-проверки (assert) по всем режимам и edge-кейсам.

// MARK: Инфраструктура проверок

/// Reference-бокс для передачи результата из отменяемого Task обратно в
/// синхронный код без захвата mutable top-level переменных (которые под
/// -default-isolation MainActor были бы actor-изолированы).
nonisolated final class ResultBox: @unchecked Sendable {
    var caughtCancellation = false
    var caughtOther: Error? = nil
}

var passed = 0
var failed = 0

func check(_ cond: Bool, _ msg: String) {
    if cond {
        passed += 1
        print("  ok: \(msg)")
    } else {
        failed += 1
        print("  FAIL: \(msg)")
    }
}

/// Сравнивает ошибки по КЕЙСУ (для .invalidQuery сообщение не учитывается).
func sameCase(_ a: AnagramEngineError, _ b: AnagramEngineError) -> Bool {
    switch (a, b) {
    case (.notReady, .notReady),
         (.dictionaryUnavailable, .dictionaryUnavailable),
         (.dictionaryCorrupt, .dictionaryCorrupt),
         (.invalidQuery, .invalidQuery):
        return true
    default:
        return false
    }
}

func checkThrows<T>(_ expected: AnagramEngineError, _ label: String, _ body: () throws -> T) {
    do {
        _ = try body()
        failed += 1
        print("  FAIL: \(label) — ожидалась ошибка \(expected), но её не было")
    } catch let e as AnagramEngineError {
        if sameCase(e, expected) {
            passed += 1
            print("  ok: \(label) → \(e)")
        } else {
            failed += 1
            print("  FAIL: \(label) — ожидалась \(expected), получена \(e)")
        }
    } catch {
        failed += 1
        print("  FAIL: \(label) — неожиданная ошибка \(error)")
    }
}

// MARK: Генератор синтетического словаря (формат v1)

/// Пишет little-endian бинарный словарь в формате binary-format.md.
/// words — список кириллических строк. Дедупликация и сортировка выполняются здесь.
func buildSyntheticDictionary(words rawWords: [String], yoFolded: Bool) -> Data {
    // Кодируем слова в коды.
    func encodeWord(_ w: String) -> [UInt8]? {
        var codes: [UInt8] = []
        for ch in w.lowercased() {
            guard var c = AnagramCodec.code(for: ch) else { return nil }
            if yoFolded && c == 6 { c = 5 }
            codes.append(c)
        }
        return codes
    }

    var byLen: [Int: [[UInt8]]] = [:]
    for w in rawWords {
        guard let codes = encodeWord(w), !codes.isEmpty else { continue }
        byLen[codes.count, default: []].append(codes)
    }
    // Дедуп + лексикографическая сортировка по кодам внутри bucket'а.
    func lexLess(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        let n = min(a.count, b.count)
        for i in 0..<n where a[i] != b[i] { return a[i] < b[i] }
        return a.count < b.count
    }
    var maxLen = 0
    for (L, arr) in byLen {
        var seen = Set<[UInt8]>()
        let dedup = arr.filter { seen.insert($0).inserted }.sorted(by: lexLess)
        byLen[L] = dedup
        maxLen = max(maxLen, L)
    }

    let totalWords = byLen.values.reduce(0) { $0 + $1.count }

    var data = Data()
    func appendU16(_ v: UInt16) {
        data.append(UInt8(v & 0xFF)); data.append(UInt8((v >> 8) & 0xFF))
    }
    func appendU32(_ v: UInt32) {
        data.append(UInt8(v & 0xFF)); data.append(UInt8((v >> 8) & 0xFF))
        data.append(UInt8((v >> 16) & 0xFF)); data.append(UInt8((v >> 24) & 0xFF))
    }

    // Header (16 байт)
    data.append(contentsOf: [0x41, 0x4E, 0x47, 0x52]) // ANGR
    appendU16(1)                                       // version
    appendU16(yoFolded ? 1 : 0)                        // flags
    appendU32(UInt32(totalWords))                      // wordCount
    data.append(UInt8(maxLen))                         // maxLen
    data.append(contentsOf: [0, 0, 0])                 // reserved

    // Length table: для L=1..maxLen — (u32 relOffset, u32 count).
    // Считаем relOffset относительно начала WordBlock.
    var relOffset = 0
    var offsets: [Int] = []
    var counts: [Int] = []
    for L in 1...max(1, maxLen) {
        if maxLen == 0 { break }
        let bucket = byLen[L] ?? []
        offsets.append(relOffset)
        counts.append(bucket.count)
        relOffset += bucket.count * L
    }
    for i in 0..<offsets.count {
        appendU32(UInt32(offsets[i]))
        appendU32(UInt32(counts[i]))
    }

    // WordBlock
    for L in 1...max(1, maxLen) {
        if maxLen == 0 { break }
        let bucket = byLen[L] ?? []
        for codes in bucket { data.append(contentsOf: codes) }
    }

    return data
}

// MARK: Хелперы запросов

func words(_ page: AnagramResultPage) -> Set<String> { Set(page.words) }

// MARK: Выбор словаря

let fm = FileManager.default
let cwd = fm.currentDirectoryPath
let realDictPath = "\(cwd)/encx-cli/Resources/ru_dict.bin"
let samplePath = "\(cwd)/docs/anagram-sample-words.txt"

var usedRealDict = false
var engine: AnagramEngine

// Слова синтетического словаря: покрывают все тестовые сценарии.
// Длины 1..5, включая анаграммы {к,о,т} и слово с ё для foldYo.
let syntheticWords = [
    "а", "к",
    "от", "то", "но", "он",
    "кот", "кто", "ток", "сон", "нос",
    "лето", "тело",
    "полёт",     // с ё — для foldYo-теста (код 6)
]

if fm.fileExists(atPath: realDictPath) {
    do {
        engine = try AnagramEngineImpl(dictionaryURL: URL(fileURLWithPath: realDictPath))
        usedRealDict = true
        print("Словарь: РЕАЛЬНЫЙ (\(realDictPath))")
    } catch {
        print("Реальный словарь не открылся (\(error)); переключаюсь на синтетический.")
        let data = buildSyntheticDictionary(words: syntheticWords, yoFolded: false)
        engine = try! AnagramEngineImpl(data: data)
        print("Словарь: СИНТЕТИЧЕСКИЙ (in-memory)")
    }
} else {
    let data = buildSyntheticDictionary(words: syntheticWords, yoFolded: false)
    // Пишем во временный файл, чтобы дополнительно проверить mmap-путь через URL.
    let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("anagram-synthetic-\(UUID().uuidString).bin")
    try! data.write(to: tmpURL)
    engine = try! AnagramEngineImpl(dictionaryURL: tmpURL)
    print("Словарь: СИНТЕТИЧЕСКИЙ (mmap из \(tmpURL.lastPathComponent))")
}

print("isReady = \(engine.isReady)")
print("")

// MARK: 1. Round-trip (только для реального словаря + sample)

print("== Round-trip ==")
if usedRealDict, fm.fileExists(atPath: samplePath),
   let sampleText = try? String(contentsOfFile: samplePath, encoding: .utf8) {
    let sample = sampleText.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
        .map { String($0).trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    var rtOk = 0
    var rtMiss = 0
    for w in sample.prefix(200) {
        // Проверяем, что слово находится точным pattern-поиском самого себя.
        // (Анаграммный поиск для round-trip не годится: входное слово
        // исключается из выдачи по контракту.)
        let q = AnagramQuery(mode: .pattern, pattern: w, foldYo: false, sort: .alphabetical)
        if let page = try? engine.search(q, limit: 1000, offset: 0),
           page.words.contains(w.lowercased()) {
            rtOk += 1
        } else {
            rtMiss += 1
        }
    }
    check(rtMiss == 0, "round-trip sample (\(rtOk) найдено, \(rtMiss) промахов)")
} else {
    print("  (пропуск: нет реального словаря или sample-файла — round-trip неприменим к синтетике по контракту)")
}
print("")

// MARK: 2. Юнит-проверки режимов (работают на синтетике; на реальном словаре — как надмножество)

// Для стабильности проверок работаем на СИНТЕТИЧЕСКОМ словаре с известным составом.
let synthData = buildSyntheticDictionary(words: syntheticWords, yoFolded: false)
let synth = try! AnagramEngineImpl(data: synthData)

print("== .pattern ==")
do {
    // к_т → кот, кит(нет), … в нашем словаре: кот.
    let q = AnagramQuery(mode: .pattern, pattern: "к_т", sort: .alphabetical)
    let page = try synth.search(q, limit: 100, offset: 0)
    check(page.words.contains("кот"), "к_т содержит 'кот'")
    check(page.words.allSatisfy { $0.count == 3 }, "к_т: все результаты длины 3")
    // Одиночные плейсхолдеры '.' и '?' эквивалентны '_' (ровно один символ).
    for j in ["к.т", "к?т"] {
        let qj = AnagramQuery(mode: .pattern, pattern: j, sort: .alphabetical)
        let pj = try synth.search(qj, limit: 100, offset: 0)
        check(words(pj) == words(page), "одиночный джокер '\(j)' эквивалентен '_'")
    }
    // Полностью джокерный паттерн длины 2 → все двухбуквенные.
    let q2 = AnagramQuery(mode: .pattern, pattern: "__", sort: .alphabetical)
    let p2 = try synth.search(q2, limit: 100, offset: 0)
    check(words(p2).isSuperset(of: ["от", "то", "но", "он"]), "'__' даёт все 2-буквенные")
}
print("")

print("== .pattern со '*' (любое число символов) ==")
do {
    // 'к*т' — начинается на к, кончается на т, между — сколько угодно.
    // В словаре: кот (star='о'). 'кт' нет; кто/ток не подходят.
    let qStar = AnagramQuery(mode: .pattern, pattern: "к*т", sort: .alphabetical)
    let pStar = try synth.search(qStar, limit: 100, offset: 0)
    check(words(pStar) == ["кот"], "'к*т' = [кот] (получено: \(pStar.words))")

    // '*от' — любое (в т.ч. пустое) начало + 'от': от, кот.
    let qSuf = AnagramQuery(mode: .pattern, pattern: "*от", sort: .alphabetical)
    let pSuf = try synth.search(qSuf, limit: 100, offset: 0)
    check(words(pSuf) == ["кот", "от"], "'*от' = [кот, от] (получено: \(pSuf.words))")

    // 'к*' — всё, что начинается на к: к, кот, кто.
    let qPre = AnagramQuery(mode: .pattern, pattern: "к*", sort: .alphabetical)
    let pPre = try synth.search(qPre, limit: 100, offset: 0)
    check(words(pPre) == ["к", "кот", "кто"], "'к*' = [к, кот, кто] (получено: \(pPre.words))")

    // Одиночный '*' матчит все слова словаря.
    let qAll = AnagramQuery(mode: .pattern, pattern: "*", sort: .alphabetical)
    let pAll = try synth.search(qAll, limit: 1000, offset: 0)
    check(pAll.totalCount == syntheticWords.count, "'*' матчит все слова (\(pAll.totalCount) из \(syntheticWords.count))")

    // '**' схлопывается в один '*'.
    let qDbl = AnagramQuery(mode: .pattern, pattern: "**", sort: .alphabetical)
    let pDbl = try synth.search(qDbl, limit: 1000, offset: 0)
    check(pDbl.totalCount == pAll.totalCount, "'**' эквивалентно '*'")

    // Фильтр по длине сужает диапазон '*'.
    let qLen = AnagramQuery(mode: .pattern, pattern: "к*т", maxLength: 2, sort: .alphabetical)
    let pLen = try synth.search(qLen, limit: 100, offset: 0)
    check(pLen.words.isEmpty, "'к*т' + maxLength=2 → пусто (кот длиннее)")
}
print("")

print("== .anagram ==")
do {
    // Входное слово ('кот') исключается из выдачи по контракту.
    let q = AnagramQuery(mode: .anagram, letters: "кот", sort: .alphabetical)
    let page = try synth.search(q, limit: 100, offset: 0)
    check(words(page) == ["кто", "ток"], "анаграммы {к,о,т} = кто/ток, без входного 'кот' (получено: \(page.words))")
    check(page.totalCount == 2, "totalCount == 2 (входное слово не в счёте)")
    // Ввод 'тко' — не словарное слово: исключать нечего, находятся все три.
    let q2 = AnagramQuery(mode: .anagram, letters: "тко", sort: .alphabetical)
    let p2 = try synth.search(q2, limit: 100, offset: 0)
    check(words(p2) == ["кот", "кто", "ток"], "ввод 'тко' (не слово) даёт все анаграммы, включая 'кот'")
    // Набор из 2 букв не даёт 3-буквенных; входное 'от' исключено.
    let q3 = AnagramQuery(mode: .anagram, letters: "от", sort: .alphabetical)
    let p3 = try synth.search(q3, limit: 100, offset: 0)
    check(words(p3) == ["то"], "анаграммы {о,т} = то (входное 'от' исключено)")
}
print("")

print("== .subword ==")
do {
    let q = AnagramQuery(mode: .subword, letters: "кот", sort: .alphabetical)
    let page = try synth.search(q, limit: 100, offset: 0)
    // Подслова из {к,о,т}: к, от, то, кто, ток; входное 'кот' исключено.
    check(words(page).isSuperset(of: ["от", "то", "к"]), "subword {к,о,т} включает от/то/к (получено: \(page.words))")
    check(words(page).isSuperset(of: ["кто", "ток"]), "subword {к,о,т} включает полные анаграммы")
    check(!page.words.contains("кот"), "subword {к,о,т} НЕ включает входное 'кот'")
    check(!page.words.contains("а"), "subword {к,о,т} НЕ включает 'а'")
    check(!page.words.contains("сон"), "subword {к,о,т} НЕ включает 'сон'")
    check(page.words.allSatisfy { $0.count <= 3 }, "subword: длины ≤ |набор|")
}
print("")

print("== .combined ==")
do {
    // Паттерн "_о_" + буквы "кт": фикс середина = о, крайние из {к,т}.
    // Подходят: кот (к,о,т) и ток (т,о,к).
    let q = AnagramQuery(mode: .combined, pattern: "_о_", letters: "кт", sort: .alphabetical)
    let page = try synth.search(q, limit: 100, offset: 0)
    check(words(page).isSuperset(of: ["кот", "ток"]), "combined '_о_'+кт включает кот/ток (получено: \(page.words))")
    check(page.words.allSatisfy { Array($0)[1] == "о" }, "combined: середина всегда 'о'")
    // Без нужных букв в наборе — пусто на джокер-позициях.
    let q2 = AnagramQuery(mode: .combined, pattern: "_о_", letters: "к", sort: .alphabetical)
    let p2 = try synth.search(q2, limit: 100, offset: 0)
    check(!p2.words.contains("кот"), "combined '_о_'+к (одна к) не даёт кот (нужны к и т)")
    // С бланком добираем недостающее.
    let q3 = AnagramQuery(mode: .combined, pattern: "_о_", letters: "к", blankCount: 1, sort: .alphabetical)
    let p3 = try synth.search(q3, limit: 100, offset: 0)
    check(p3.words.contains("кот"), "combined '_о_'+к+1бланк даёт кот")

    // '*' в combined: позиции под звездой тоже берутся из пула букв.
    // 'к*т' + буквы 'о': звезда покрывает 'о' из пула → кот.
    let qs = AnagramQuery(mode: .combined, pattern: "к*т", letters: "о", sort: .alphabetical)
    let ps = try synth.search(qs, limit: 100, offset: 0)
    check(ps.words.contains("кот"), "combined 'к*т'+о: звезда берёт 'о' из пула → кот")
    // Пустой пул без бланка — звезде нечем покрыть 'о' ('кт' в словаре нет) → пусто.
    let qs2 = AnagramQuery(mode: .combined, pattern: "к*т", letters: "", sort: .alphabetical)
    let ps2 = try synth.search(qs2, limit: 100, offset: 0)
    check(!ps2.words.contains("кот"), "combined 'к*т'+пустой пул не даёт кот (нечем покрыть 'о')")
    // Бланк покрывает позицию под звездой.
    let qs3 = AnagramQuery(mode: .combined, pattern: "к*т", letters: "", blankCount: 1, sort: .alphabetical)
    let ps3 = try synth.search(qs3, limit: 100, offset: 0)
    check(ps3.words.contains("кот"), "combined 'к*т'+1бланк: звезда берёт бланк → кот")
}
print("")

print("== edge-кейсы ==")
do {
    // Пустой ввод → invalidQuery.
    checkThrows(.invalidQuery(""), "пустой pattern → invalidQuery") {
        try synth.search(AnagramQuery(mode: .pattern, pattern: ""), limit: 10, offset: 0)
    }
    checkThrows(.invalidQuery(""), "пустой letters (anagram) → invalidQuery") {
        try synth.search(AnagramQuery(mode: .anagram, letters: ""), limit: 10, offset: 0)
    }
    checkThrows(.invalidQuery(""), "пустой letters (subword) → invalidQuery") {
        try synth.search(AnagramQuery(mode: .subword, letters: ""), limit: 10, offset: 0)
    }
    // Недопустимые символы в pattern → invalidQuery (латиница не буква и не джокер).
    checkThrows(.invalidQuery(""), "латиница в pattern → invalidQuery") {
        try synth.search(AnagramQuery(mode: .pattern, pattern: "abc"), limit: 10, offset: 0)
    }
    // Длина > maxLen: паттерн длиннее самого длинного слова → пусто, без краша.
    let longQ = AnagramQuery(mode: .pattern, pattern: "______________________________________________________", sort: .alphabetical)
    let longPage = try synth.search(longQ, limit: 10, offset: 0)
    check(longPage.words.isEmpty && longPage.totalCount == 0, "паттерн длиннее maxLen → пусто, без краша")
    // maxLength-фильтр отсекает длинные слова.
    let fq = AnagramQuery(mode: .subword, letters: "кот", maxLength: 2, sort: .alphabetical)
    let fpage = try synth.search(fq, limit: 100, offset: 0)
    check(fpage.words.allSatisfy { $0.count <= 2 }, "maxLength=2 отсекает 3-буквенные")
    check(!fpage.words.contains("кот"), "maxLength=2: 'кот' исключён")
    // minLength-фильтр.
    let mq = AnagramQuery(mode: .subword, letters: "кот", minLength: 3, sort: .alphabetical)
    let mpage = try synth.search(mq, limit: 100, offset: 0)
    check(mpage.words.allSatisfy { $0.count >= 3 }, "minLength=3 отсекает короткие")
}
print("")

print("== foldYo ==")
do {
    // Словарь содержит «полёт» (с ё, код 6). При foldYo=true 'полет' (через е)
    // фолдится в то же слово, что и хранимое 'полёт' → это входное слово,
    // и по контракту оно исключается из выдачи.
    let q = AnagramQuery(mode: .anagram, letters: "полет", foldYo: true, sort: .alphabetical)
    let page = try synth.search(q, limit: 100, offset: 0)
    check(page.words.isEmpty, "foldYo=true: 'полет' == хранимое 'полёт' → исключено как входное (получено: \(page.words))")

    // Перемешанный ввод 'тполе' — не то же слово: 'полёт' находится (fold в скане работает).
    let qMix = AnagramQuery(mode: .anagram, letters: "тполе", foldYo: true, sort: .alphabetical)
    let pMix = try synth.search(qMix, limit: 100, offset: 0)
    check(pMix.words.contains("полёт"), "foldYo=true: 'тполе' находит хранимое 'полёт' (получено: \(pMix.words))")

    // Без foldYo — не находит (е≠ё).
    let q2 = AnagramQuery(mode: .anagram, letters: "полет", foldYo: false, sort: .alphabetical)
    let p2 = try synth.search(q2, limit: 100, offset: 0)
    check(p2.words.isEmpty, "foldYo=false: 'полет' НЕ находит 'полёт'")

    // Pattern с foldYo: "поле_" где _ на месте т — проверим 'пол_т' через букву е в паттерне?
    // Точечная проверка: pattern "полёт" точно == хранимому; pattern "полет" с foldYo тоже.
    let q3 = AnagramQuery(mode: .pattern, pattern: "полет", foldYo: true, sort: .alphabetical)
    let p3 = try synth.search(q3, limit: 100, offset: 0)
    check(p3.words.contains("полёт"), "pattern 'полет'+foldYo матчит 'полёт'")
}
print("")

print("== пагинация ==")
do {
    let base = AnagramQuery(mode: .subword, letters: "кот", sort: .alphabetical)
    let full = try synth.search(base, limit: 1000, offset: 0)
    let total = full.totalCount
    check(total > 2, "есть достаточно результатов для пагинации (total=\(total))")
    let p1 = try synth.search(base, limit: 2, offset: 0)
    check(p1.words.count == 2, "страница 1: 2 элемента")
    check(p1.hasMore == (total > 2), "страница 1: hasMore корректен")
    check(p1.totalCount == total, "totalCount стабилен на страницах")
    let p2 = try synth.search(base, limit: 2, offset: 2)
    check(Set(p1.words).isDisjoint(with: Set(p2.words)), "страницы не пересекаются")
    // offset за пределами → пусто, без hasMore.
    let pEnd = try synth.search(base, limit: 2, offset: total + 100)
    check(pEnd.words.isEmpty && !pEnd.hasMore, "offset за пределами → пусто, hasMore=false")
}
print("")

print("== dictionaryCorrupt ==")
do {
    // Битый magic.
    var bad = synthData
    bad[0] = 0x00
    checkThrows(.dictionaryCorrupt, "битый magic → dictionaryCorrupt") {
        try AnagramEngineImpl(data: bad)
    }
    // Неверная версия.
    var badVer = synthData
    badVer[4] = 0x09
    checkThrows(.dictionaryCorrupt, "неверная version → dictionaryCorrupt") {
        try AnagramEngineImpl(data: badVer)
    }
    // Обрезанный файл.
    let truncated = synthData.prefix(8)
    checkThrows(.dictionaryCorrupt, "обрезанный header → dictionaryCorrupt") {
        try AnagramEngineImpl(data: Data(truncated))
    }
}
print("")

print("== кэш пагинации (FIX 3) ==")
do {
    // Повторные страницы того же запроса должны давать консистентный срез
    // одного и того же отсортированного матч-листа (кэш-хит, без рескана).
    let base = AnagramQuery(mode: .subword, letters: "кот", sort: .alphabetical)
    let full = try synth.search(base, limit: 1000, offset: 0)
    let allWords = full.words
    // Собираем постранично по 1 и сверяем с полным списком.
    var paged: [String] = []
    var off = 0
    while true {
        let pg = try synth.search(base, limit: 1, offset: off)
        if pg.words.isEmpty { break }
        paged.append(contentsOf: pg.words)
        off += 1
        if !pg.hasMore { break }
    }
    check(paged == allWords, "постраничная выборка (limit=1) == полному списку (кэш консистентен)")
    // Смена запроса инвалидирует кэш, но результат остаётся корректным.
    let other = AnagramQuery(mode: .anagram, letters: "кот", sort: .alphabetical)
    let op = try synth.search(other, limit: 100, offset: 0)
    check(words(op) == ["кто", "ток"], "после смены запроса кэш инвалидирован, результат верен")
    // Возврат к исходному запросу — снова консистентно.
    let again = try synth.search(base, limit: 1000, offset: 0)
    check(again.words == allWords, "возврат к прежнему запросу даёт тот же результат")
}
print("")

print("== кооперативная отмена (FIX 2) ==")
do {
    // Захватываем движок в Sendable-константу, чтобы Task-замыкание не тянуло
    // MainActor-изолированную top-level переменную `engine`.
    let eng: AnagramEngine = engine
    // Синхронный search() внутри уже отменённого Task должен бросить CancellationError.
    let sem = DispatchSemaphore(value: 0)
    let box = ResultBox()
    let task = Task {
        // Ждём, пока сам себя отменим ниже (гарантируем isCancelled=true до скана).
        // Отмена приходит извне до фактического вызова search.
        while !Task.isCancelled { await Task.yield() }
        do {
            // Тяжёлый запрос: на реальном словаре это полный скан subword.
            _ = try eng.search(
                AnagramQuery(mode: .subword, letters: "апельсинка", sort: .byLengthDesc),
                limit: 50, offset: 0
            )
        } catch is CancellationError {
            box.caughtCancellation = true
        } catch {
            box.caughtOther = error
        }
        sem.signal()
    }
    task.cancel()
    // Ждём завершения таска (с запасом).
    _ = sem.wait(timeout: .now() + 5)
    check(box.caughtCancellation, "search() в отменённом Task бросает CancellationError (other=\(String(describing: box.caughtOther)))")

    // Контроль: без отмены тот же запрос отрабатывает нормально.
    let ok = try eng.search(
        AnagramQuery(mode: .subword, letters: "кот", sort: .byLengthDesc),
        limit: 50, offset: 0
    )
    check(ok.totalCount >= 1, "без отмены запрос отрабатывает нормально (total=\(ok.totalCount))")
}
print("")

// MARK: Итог

print("========================================")
print("PASSED: \(passed)   FAILED: \(failed)")
print("Словарь для юнит-проверок: СИНТЕТИЧЕСКИЙ")
print("Открытый словарь движка: \(usedRealDict ? "РЕАЛЬНЫЙ ru_dict.bin" : "СИНТЕТИЧЕСКИЙ")")
print("========================================")

if failed > 0 {
    exit(1)
}
