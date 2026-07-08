import Foundation

/// Язык алфавита для утилит-дешифровщиков.
enum CipherAlphabet: String, CaseIterable, Identifiable, Hashable {
    case ru
    case en

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ru: return "Русский"
        case .en: return "English"
        }
    }

    var shortTitle: String {
        switch self {
        case .ru: return "RU"
        case .en: return "EN"
        }
    }

    /// Буквы алфавита в каноническом порядке (нижний регистр).
    /// Для русского `includeYo` управляет тем, считать ли «ё» отдельной буквой (33 против 32).
    func letters(includeYo: Bool = true) -> [Character] {
        switch self {
        case .ru:
            let full = "абвгдеёжзийклмнопрстуфхцчшщъыьэюя"
            let noYo = "абвгдежзийклмнопрстуфхцчшщъыьэюя"
            return Array(includeYo ? full : noYo)
        case .en:
            return Array("abcdefghijklmnopqrstuvwxyz")
        }
    }
}

/// Сохраняет исходный регистр `original` при подстановке буквы `replacement` (нижний регистр).
private func matchingCase(of original: Character, to replacement: Character) -> Character {
    if original.isUppercase {
        return Character(String(replacement).uppercased())
    }
    return replacement
}

// MARK: - Шифр Цезаря

/// Один вариант перебора сдвигов шифра Цезаря.
struct CaesarShiftResult: Identifiable {
    let shift: Int
    let text: String
    var id: Int { shift }
}

enum CaesarCipher {
    /// Сдвигает каждую букву `text` на `amount` позиций внутри `alphabet`.
    /// Небуквенные символы и буквы вне алфавита остаются без изменений.
    static func shift(_ text: String, by amount: Int, alphabet: [Character]) -> String {
        guard !alphabet.isEmpty else { return text }
        let count = alphabet.count
        var index: [Character: Int] = [:]
        for (i, ch) in alphabet.enumerated() {
            index[ch] = i
        }

        var result = String()
        result.reserveCapacity(text.count)
        for ch in text {
            let lower = Character(String(ch).lowercased())
            if let i = index[lower] {
                let shifted = ((i + amount) % count + count) % count
                result.append(matchingCase(of: ch, to: alphabet[shifted]))
            } else {
                result.append(ch)
            }
        }
        return result
    }

    /// Все ненулевые сдвиги: результаты для перебора при дешифровке.
    static func allShifts(_ text: String, alphabet: [Character]) -> [CaesarShiftResult] {
        guard alphabet.count > 1 else { return [] }
        return (1..<alphabet.count).map { amount in
            CaesarShiftResult(shift: amount, text: shift(text, by: amount, alphabet: alphabet))
        }
    }
}

// MARK: - Атбаш

enum AtbashCipher {
    /// Симметричная замена: буква на позиции `i` меняется на букву с позиции `n-1-i`.
    static func transform(_ text: String, alphabet: [Character]) -> String {
        guard !alphabet.isEmpty else { return text }
        let count = alphabet.count
        var index: [Character: Int] = [:]
        for (i, ch) in alphabet.enumerated() {
            index[ch] = i
        }

        var result = String()
        result.reserveCapacity(text.count)
        for ch in text {
            let lower = Character(String(ch).lowercased())
            if let i = index[lower] {
                result.append(matchingCase(of: ch, to: alphabet[count - 1 - i]))
            } else {
                result.append(ch)
            }
        }
        return result
    }
}

// MARK: - Шифр Виженера

enum VigenereCipher {
    /// Шифрует или дешифрует `text` ключевым словом `key` в пределах `alphabet`.
    /// Ключ циклически повторяется и продвигается только на буквах алфавита;
    /// небуквенные символы проходят без изменений и не расходуют ключ.
    static func transform(_ text: String, key: String, alphabet: [Character], decrypt: Bool) -> String {
        guard !alphabet.isEmpty else { return text }
        let count = alphabet.count
        var index: [Character: Int] = [:]
        for (i, ch) in alphabet.enumerated() {
            index[ch] = i
        }

        let keyShifts = key.lowercased().compactMap { index[Character(String($0))] }
        guard !keyShifts.isEmpty else { return text }

        var result = String()
        result.reserveCapacity(text.count)
        var keyPos = 0
        for ch in text {
            let lower = Character(String(ch).lowercased())
            if let i = index[lower] {
                let shift = keyShifts[keyPos % keyShifts.count]
                let amount = decrypt ? -shift : shift
                let newIndex = ((i + amount) % count + count) % count
                result.append(matchingCase(of: ch, to: alphabet[newIndex]))
                keyPos += 1
            } else {
                result.append(ch)
            }
        }
        return result
    }
}

// MARK: - Код букв (A1Z26)

enum LetterNumberCipher {
    /// Текст → числа (позиции букв). Слова разделяются « / », буквы — пробелом.
    static func encode(_ text: String, alphabet: [Character]) -> String {
        var position: [Character: Int] = [:]
        for (i, ch) in alphabet.enumerated() {
            position[ch] = i + 1
        }

        var words: [String] = []
        for rawWord in text.lowercased().split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
            let numbers = rawWord.compactMap { position[$0].map(String.init) }
            if !numbers.isEmpty {
                words.append(numbers.joined(separator: " "))
            }
        }
        return words.joined(separator: " / ")
    }

    /// Числа → текст. Разделитель слов — «/», числа — любые небуквенные символы.
    static func decode(_ text: String, alphabet: [Character]) -> String {
        var result = String()
        var current = String()

        func flushNumber() {
            guard let value = Int(current) else { current = ""; return }
            if value >= 1, value <= alphabet.count {
                result.append(alphabet[value - 1])
            }
            current = ""
        }

        for ch in text {
            if ch.isNumber {
                current.append(ch)
            } else {
                flushNumber()
                if ch == "/" {
                    result.append(" ")
                }
            }
        }
        flushNumber()
        return result
    }
}

// MARK: - Азбука Морзе

enum MorseCode {
    private static let digits: [Character: String] = [
        "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
        "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----."
    ]

    private static let english: [Character: String] = [
        "a": ".-", "b": "-...", "c": "-.-.", "d": "-..", "e": ".", "f": "..-.",
        "g": "--.", "h": "....", "i": "..", "j": ".---", "k": "-.-", "l": ".-..",
        "m": "--", "n": "-.", "o": "---", "p": ".--.", "q": "--.-", "r": ".-.",
        "s": "...", "t": "-", "u": "..-", "v": "...-", "w": ".--", "x": "-..-",
        "y": "-.--", "z": "--.."
    ]

    private static let russian: [Character: String] = [
        "а": ".-", "б": "-...", "в": ".--", "г": "--.", "д": "-..", "е": ".",
        "ё": ".", "ж": "...-", "з": "--..", "и": "..", "й": ".---", "к": "-.-",
        "л": ".-..", "м": "--", "н": "-.", "о": "---", "п": ".--.", "р": ".-.",
        "с": "...", "т": "-", "у": "..-", "ф": "..-.", "х": "....", "ц": "-.-.",
        "ч": "---.", "ш": "----", "щ": "--.-", "ъ": "--.--", "ы": "-.--",
        "ь": "-..-", "э": "..-..", "ю": "..--", "я": ".-.-"
    ]

    private static func table(for alphabet: CipherAlphabet) -> [Character: String] {
        var table = digits
        switch alphabet {
        case .ru: table.merge(russian) { _, new in new }
        case .en: table.merge(english) { _, new in new }
        }
        return table
    }

    /// Буквы, которые уступают канонической букве с тем же кодом при декодировании.
    /// «ё» в Морзе передаётся как «е» (·) и при обратном переводе неотличима от «е»,
    /// поэтому результатом декодирования всегда должна быть «е».
    private static let secondaryLetters: [CipherAlphabet: Set<Character>] = [
        .ru: ["ё"]
    ]

    /// Обратная таблица код → буква. При коллизии выигрывает буква (цифры добавляются первыми),
    /// а вторичные буквы (см. `secondaryLetters`) в таблицу не попадают, чтобы декодирование
    /// было детерминированным и давало каноническую букву.
    private static func reverseTable(for alphabet: CipherAlphabet) -> [String: Character] {
        var reverse: [String: Character] = [:]
        for (ch, code) in digits {
            reverse[code] = ch
        }
        let letters = alphabet == .ru ? russian : english
        let secondary = secondaryLetters[alphabet] ?? []
        for (ch, code) in letters where !secondary.contains(ch) {
            reverse[code] = ch
        }
        return reverse
    }

    /// Текст → код Морзе. Буквы разделяются пробелом, слова — « / ».
    static func encode(_ text: String, alphabet: CipherAlphabet) -> String {
        let table = table(for: alphabet)
        var words: [String] = []
        for rawWord in text.lowercased().split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
            let codes = rawWord.compactMap { table[$0] }
            if !codes.isEmpty {
                words.append(codes.joined(separator: " "))
            }
        }
        return words.joined(separator: " / ")
    }

    /// Код Морзе → текст. Слова разделяются «/», буквы — пробелами.
    static func decode(_ text: String, alphabet: CipherAlphabet) -> String {
        let reverse = reverseTable(for: alphabet)
        let normalized = text
            .replacingOccurrences(of: "·", with: ".")
            .replacingOccurrences(of: "•", with: ".")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "−", with: "-")

        var words: [String] = []
        for word in normalized.components(separatedBy: "/") {
            let letters = word
                .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
                .compactMap { reverse[String($0)].map(String.init) }
            if !letters.isEmpty {
                words.append(letters.joined())
            }
        }
        return words.joined(separator: " ")
    }
}

// MARK: - Раскладка клавиатуры

enum KeyboardLayout {
    /// Пары «русская буква/символ ЙЦУКЕН» → «латинская клавиша QWERTY».
    private static let ruToEnPairs: [(Character, Character)] = [
        ("й", "q"), ("ц", "w"), ("у", "e"), ("к", "r"), ("е", "t"), ("н", "y"),
        ("г", "u"), ("ш", "i"), ("щ", "o"), ("з", "p"), ("х", "["), ("ъ", "]"),
        ("ф", "a"), ("ы", "s"), ("в", "d"), ("а", "f"), ("п", "g"), ("р", "h"),
        ("о", "j"), ("л", "k"), ("д", "l"), ("ж", ";"), ("э", "'"),
        ("я", "z"), ("ч", "x"), ("с", "c"), ("м", "v"), ("и", "b"), ("т", "n"),
        ("ь", "m"), ("б", ","), ("ю", "."), ("ё", "`")
    ]

    /// Двунаправленная карта: переводит символ в противоположную раскладку.
    /// Один прогон исправляет текст, набранный не в той раскладке (в обе стороны).
    private static let map: [Character: Character] = {
        var map: [Character: Character] = [:]
        for (ru, en) in ruToEnPairs {
            map[ru] = en
            map[en] = ru
            let ruUpper = Character(String(ru).uppercased())
            let enUpper = Character(String(en).uppercased())
            let ruHasCase = ruUpper != ru
            let enHasCase = enUpper != en
            if ruHasCase, enHasCase {
                // Обе стороны — буквы: добавляем прописную пару.
                map[ruUpper] = enUpper
                map[enUpper] = ruUpper
            } else if ruHasCase {
                // Русская буква на клавише латинской пунктуации ([, ], ; …):
                // прописная буква даёт тот же символ, строчную пунктуацию не трогаем.
                map[ruUpper] = en
            } else if enHasCase {
                map[enUpper] = ru
            }
        }
        return map
    }()

    /// Переводит каждый известный символ в противоположную раскладку, прочие оставляет как есть.
    static func convert(_ text: String) -> String {
        var result = String()
        result.reserveCapacity(text.count)
        for ch in text {
            result.append(map[ch] ?? ch)
        }
        return result
    }
}
