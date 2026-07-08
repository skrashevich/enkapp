import Foundation

// MARK: - Кодек букв: кириллица ↔ коды 0..32 (см. docs/anagramizer-binary-format.md)

/// Конверсия между кириллическими буквами и кодами алфавита.
/// Алфавит фиксирован: а=0 … я=32, 33 буквы. Коды 33..255 недопустимы в словах.
///
/// `nonisolated` на уровне типа: проект собирается с `-default-isolation MainActor`,
/// который иначе привязал бы все static-члены к MainActor. Кодек — чистые функции
/// над иммутабельными таблицами, должен вызываться из фонового скана вне MainActor.
nonisolated enum AnagramCodec {
    /// Коды спец-значений.
    static let yoCode: UInt8 = 6   // «ё»
    static let yeCode: UInt8 = 5   // «е»
    static let alphabetSize: UInt8 = 33

    /// code → Character (кириллица нижнего регистра). Индекс = код.
    static let codeToChar: [Character] = [
        "а","б","в","г","д","е","ё","ж","з","и","й","к","л","м","н","о","п",
        "р","с","т","у","ф","х","ц","ч","ш","щ","ъ","ы","ь","э","ю","я"
    ]

    /// Character → code. Заполняется из `codeToChar`.
    private static let charToCode: [Character: UInt8] = {
        var map: [Character: UInt8] = [:]
        for (i, ch) in codeToChar.enumerated() {
            map[ch] = UInt8(i)
        }
        return map
    }()

    /// Декодирует один код в символ. Возвращает nil при коде вне 0..32.
    static func char(for code: UInt8) -> Character? {
        guard code < codeToChar.count else { return nil }
        return codeToChar[Int(code)]
    }

    /// Декодирует последовательность кодов в строку (кириллица, нижний регистр).
    /// Возвращает nil, если встретился недопустимый код.
    static func decode<S: Sequence>(_ codes: S) -> String? where S.Element == UInt8 {
        var out = ""
        for code in codes {
            guard let ch = char(for: code) else { return nil }
            out.append(ch)
        }
        return out
    }

    /// Кодирует один символ в код. Возвращает nil для символов вне алфавита.
    /// Сам символ уже должен быть нижнего регистра.
    static func code(for ch: Character) -> UInt8? {
        return charToCode[ch]
    }

    /// Результат нормализации набора букв в коды.
    struct EncodeResult {
        var codes: [UInt8]      // валидные коды в порядке следования
        var droppedInvalid: Bool // были ли отброшены недопустимые символы
    }

    /// Нормализует строку: lowercase, отсев небукв, опция foldYo (ё→е).
    /// Небуквенные символы (латиница, цифры, пробелы) отбрасываются с флагом.
    static func encode(_ raw: String, foldYo: Bool) -> EncodeResult {
        var codes: [UInt8] = []
        var dropped = false
        for ch in raw.lowercased() {
            guard var code = code(for: ch) else {
                dropped = true
                continue
            }
            if foldYo && code == yoCode { code = yeCode }
            codes.append(code)
        }
        return EncodeResult(codes: codes, droppedInvalid: dropped)
    }

    /// Применяет foldYo к уже готовому коду (для нормализации словаря на лету).
    @inline(__always)
    static func fold(_ code: UInt8, foldYo: Bool) -> UInt8 {
        if foldYo && code == yoCode { return yeCode }
        return code
    }
}
