import Foundation

// MARK: - Ридер бинарного словаря (см. docs/anagramizer-binary-format.md)
//
// Работает поверх mmap-Data. Слова НЕ материализуются в String — доступ идёт
// байтовыми срезами по offset. Все границы проверяются; нарушение → dictionaryCorrupt.

/// Read-only ридер бинарного словаря анаграмайзера, формат v1.
///
/// `@unchecked Sendable`: после `init` всё состояние иммутабельно (read-only
/// mmap `Data` + `let`-поля), мутабельных полей нет. Обход `forEachWord` читает
/// только неизменяемую память, поэтому безопасен для конкурентных вызовов из
/// фоновых `Task`. Явная `nonisolated`-разметка (на типе) снимает `-default-isolation
/// MainActor` со всех членов, включая static-константы и static-хелперы,
/// чтобы движок реально исполнялся вне MainActor.
nonisolated final class AnagramDictionaryReader: @unchecked Sendable {

    // Константы формата.
    private static let magic: [UInt8] = [0x41, 0x4E, 0x47, 0x52] // "ANGR"
    private static let expectedVersion: UInt16 = 1
    private static let headerSize = 16
    private static let lengthEntrySize = 8

    /// mmap-данные всего файла (держим, чтобы не отпустить mmap).
    private let data: Data

    /// Смещение WordBlock от начала файла (в байтах).
    private let wordBlockOffset: Int

    // Разобранный header.
    let version: UInt16
    let flags: UInt16
    let wordCount: Int
    let maxLen: Int
    /// yoFolded из header: если true, код 6 в словах не встречается.
    var yoFoldedOnDisk: Bool { (flags & 0x1) != 0 }

    /// Запись length-table: absolute offset начала bucket'а (от начала файла) и число слов.
    struct Bucket {
        let absoluteOffset: Int  // абсолютное смещение в файле
        let count: Int           // число слов длины L
    }

    /// bucket[L] для L=1..maxLen. Индекс 0 не используется (заглушка).
    private let buckets: [Bucket]

    /// Инициализация из mmap-Data. Бросает `dictionaryCorrupt` при несоответствии формата/границ.
    nonisolated init(data: Data) throws {
        self.data = data
        let total = data.count

        // --- Header (16 байт) ---
        guard total >= AnagramDictionaryReader.headerSize else {
            throw AnagramEngineError.dictionaryCorrupt
        }

        // Работаем через withUnsafeBytes для little-endian чтения без материализации.
        let parsed: (version: UInt16, flags: UInt16, wordCount: UInt32, maxLen: UInt8)? =
            data.withUnsafeBytes { rawBuf -> (UInt16, UInt16, UInt32, UInt8)? in
                let base = rawBuf.bindMemory(to: UInt8.self).baseAddress!
                // magic
                for i in 0..<4 where base[i] != AnagramDictionaryReader.magic[i] {
                    return nil
                }
                let version = AnagramDictionaryReader.readU16LE(base, at: 4)
                let flags = AnagramDictionaryReader.readU16LE(base, at: 6)
                let wordCount = AnagramDictionaryReader.readU32LE(base, at: 8)
                let maxLen = base[12]
                return (version, flags, wordCount, maxLen)
            }

        guard let hdr = parsed else {
            throw AnagramEngineError.dictionaryCorrupt
        }
        guard hdr.version == AnagramDictionaryReader.expectedVersion else {
            throw AnagramEngineError.dictionaryCorrupt
        }
        // maxLen ≤ 40 по контракту; maxLen == 0 допустим (пустой словарь).
        guard hdr.maxLen <= 40 else {
            throw AnagramEngineError.dictionaryCorrupt
        }

        self.version = hdr.version
        self.flags = hdr.flags
        self.wordCount = Int(hdr.wordCount)
        self.maxLen = Int(hdr.maxLen)

        // --- Length table ---
        let lenTableSize = Int(hdr.maxLen) * AnagramDictionaryReader.lengthEntrySize
        let lenTableStart = AnagramDictionaryReader.headerSize
        let wordBlockStart = lenTableStart + lenTableSize
        guard total >= wordBlockStart else {
            throw AnagramEngineError.dictionaryCorrupt
        }
        self.wordBlockOffset = wordBlockStart

        // Разбор записей length-table. offset в записи — относительно начала WordBlock.
        var parsedBuckets: [Bucket] = [Bucket(absoluteOffset: wordBlockStart, count: 0)] // индекс 0 — заглушка
        var corrupt = false
        data.withUnsafeBytes { rawBuf in
            let base = rawBuf.bindMemory(to: UInt8.self).baseAddress!
            for L in 1...max(1, Int(hdr.maxLen)) {
                if Int(hdr.maxLen) == 0 { break }
                let entryAt = lenTableStart + (L - 1) * AnagramDictionaryReader.lengthEntrySize
                let relOffset = AnagramDictionaryReader.readU32LE(base, at: entryAt)
                let count = AnagramDictionaryReader.readU32LE(base, at: entryAt + 4)
                let absOffset = wordBlockStart + Int(relOffset)

                // Проверка границ: bucket из `count` слов по L байт должен помещаться в файл.
                if count > 0 {
                    let bucketBytes = Int(count) * L
                    // absOffset может переполниться при абсурдных данных — считаем в Int64.
                    let end = Int64(absOffset) + Int64(bucketBytes)
                    if absOffset < wordBlockStart || end > Int64(total) {
                        corrupt = true
                        break
                    }
                }
                parsedBuckets.append(Bucket(absoluteOffset: absOffset, count: Int(count)))
            }
        }

        if corrupt {
            throw AnagramEngineError.dictionaryCorrupt
        }
        // Если maxLen == 0 — пустой словарь: buckets содержит только заглушку.
        self.buckets = parsedBuckets
    }

    // MARK: - Доступ к bucket'ам

    /// Число слов длины L (1..maxLen). Вне диапазона → 0.
    nonisolated func count(length L: Int) -> Int {
        guard L >= 1, L <= maxLen, L < buckets.count else { return 0 }
        return buckets[L].count
    }

    /// Выполняет `body` для каждого слова длины L, передавая байтовый указатель на L кодов.
    /// Указатель валиден только внутри вызова body. Возврат false из body прерывает обход.
    /// Слова НЕ материализуются в String.
    nonisolated func forEachWord(length L: Int, _ body: (UnsafeBufferPointer<UInt8>, _ index: Int) -> Bool) {
        guard L >= 1, L <= maxLen, L < buckets.count else { return }
        let bucket = buckets[L]
        guard bucket.count > 0 else { return }
        data.withUnsafeBytes { rawBuf in
            let base = rawBuf.bindMemory(to: UInt8.self).baseAddress!
            var ptr = base + bucket.absoluteOffset
            for i in 0..<bucket.count {
                let buf = UnsafeBufferPointer(start: ptr, count: L)
                if !body(buf, i) { return }
                ptr += L
            }
        }
    }

    // MARK: - LE-хелперы

    @inline(__always)
    private static func readU16LE(_ base: UnsafePointer<UInt8>, at offset: Int) -> UInt16 {
        return UInt16(base[offset]) | (UInt16(base[offset + 1]) << 8)
    }

    @inline(__always)
    private static func readU32LE(_ base: UnsafePointer<UInt8>, at offset: Int) -> UInt32 {
        return UInt32(base[offset])
            | (UInt32(base[offset + 1]) << 8)
            | (UInt32(base[offset + 2]) << 16)
            | (UInt32(base[offset + 3]) << 24)
    }
}
