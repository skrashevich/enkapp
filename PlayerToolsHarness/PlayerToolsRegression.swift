import Foundation

// Build and run, including the real bundled resource: PlayerToolsHarness/run.sh

nonisolated final class SlowEngine: AnagramEngine, @unchecked Sendable {
    let isReady = true
    private let lock = NSLock()
    private var calls = 0
    let hasMore: Bool
    init(hasMore: Bool = false) { self.hasMore = hasMore }
    var callCount: Int { lock.withLock { calls } }

    func search(_ query: AnagramQuery, limit: Int, offset: Int) throws -> AnagramResultPage {
        lock.withLock { calls += 1 }
        // Simulate an engine that cannot immediately interrupt its current work.
        Thread.sleep(forTimeInterval: 0.15)
        return AnagramResultPage(words: [query.letters], totalCount: hasMore ? 2 : 1, hasMore: hasMore)
    }
}

@main
struct PlayerToolsRegression {
    @MainActor
    static func waitForSearch(_ model: AnagramizerViewModel) async throws {
        await Task.yield()
        for _ in 0..<300 {
            if model.hasSearched && !model.isSearching { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        fatalError("Search did not finish")
    }

    @MainActor
    static func main() async throws {
        precondition(Bundle.main.url(forResource: "ru_dict", withExtension: "bin") != nil,
                     "Run PlayerToolsHarness/run.sh to install the bundled dictionary fixture")
        let startup = AnagramizerViewModel()
        startup.letters = "тко"
        startup.searchNow()
        try await Task.sleep(for: .milliseconds(20))
        precondition(startup.dictionaryState == .loading && !startup.hasSearched)
        startup.loadDictionaryIfNeeded()
        try await waitForSearch(startup)
        precondition(startup.dictionaryState == .ready && startup.searchErrorMessage == nil)
        precondition(startup.words.contains("кот"),
                     "Input submitted before dictionary loading must be searched automatically when ready")
        print("PASS: real Bundle.main dictionary loading retries the pending Cyrillic input")

        let engine = try await AnagramDictionaryLoader.loadDictionary(
            at: URL(fileURLWithPath: "encx-cli/Resources/ru_dict.bin"))
        let model = AnagramizerViewModel(engine: engine)
        model.searchNow()
        try await Task.sleep(for: .milliseconds(20))
        precondition(!model.hasSearched && model.searchErrorMessage == nil)

        model.letters = " КОТ! "
        model.searchNow()
        try await waitForSearch(model)
        precondition(model.words.contains("ток"), "Real Cyrillic anagram must find ток")
        precondition(model.searchErrorMessage == nil)

        model.letters = ""
        model.scheduleSearch()
        precondition(!model.hasSearched && model.words.isEmpty && model.searchErrorMessage == nil)
        model.uiMode = .pattern
        model.scheduleSearch()
        try await Task.sleep(for: .milliseconds(350))
        precondition(!model.hasSearched && model.searchErrorMessage == nil)

        model.pattern = "  к_т\n"
        model.searchNow()
        try await waitForSearch(model)
        precondition(model.words.contains("кот"), "Trimmed pattern must find кот")

        model.uiMode = .letters
        model.letters = "abc123"
        model.searchNow()
        try await waitForSearch(model)
        precondition(model.searchErrorMessage?.contains("русские буквы") == true)
        precondition(model.words.isEmpty)
        model.letters = "тко"
        model.searchNow()
        try await waitForSearch(model)
        precondition(model.words.contains("кот") && model.searchErrorMessage == nil)
        model.useAllLetters = false
        model.searchNow()
        try await Task.sleep(for: .milliseconds(20))
        try await waitForSearch(model)
        precondition(model.words.contains("то"), "Subword mode must find shorter words")

        let slow = SlowEngine()
        let queued = AnagramizerViewModel(engine: slow)
        queued.letters = "кот"
        queued.searchNow()
        queued.letters = ""
        queued.scheduleSearch()
        try await Task.sleep(for: .milliseconds(200))
        precondition(!queued.isSearching && !queued.hasSearched && slow.callCount == 0,
                     "Canceling before the search starts must keep the model idle")
        let racing = AnagramizerViewModel(engine: slow)
        racing.letters = "кот"
        racing.searchNow()
        while slow.callCount == 0 { try await Task.sleep(for: .milliseconds(5)) }
        racing.letters = ""
        racing.scheduleSearch()
        try await Task.sleep(for: .milliseconds(200))
        precondition(racing.words.isEmpty && !racing.hasSearched && !racing.isSearching,
                     "Canceled search must not restore cleared results")
        racing.letters = "кот"
        racing.searchNow()
        while slow.callCount < 2 { try await Task.sleep(for: .milliseconds(5)) }
        racing.letters = "нос"
        racing.scheduleSearch()
        try await Task.sleep(for: .milliseconds(200))
        precondition(racing.words.isEmpty && !racing.hasSearched,
                     "Previous result must not publish during debounce")
        try await waitForSearch(racing)
        precondition(racing.words == ["нос"])

        let pagedEngine = SlowEngine(hasMore: true)
        let paged = AnagramizerViewModel(engine: pagedEngine)
        paged.letters = "кот"
        paged.searchNow()
        try await waitForSearch(paged)
        precondition(paged.hasMore)
        paged.letters = "нос"
        paged.scheduleSearch()
        precondition(!paged.hasMore, "Previous query's pagination must be disabled immediately")
        paged.loadMore()
        try await Task.sleep(for: .milliseconds(550))
        precondition(pagedEngine.callCount == 2 && paged.words == ["нос"],
                     "Load more must not replace debounce or append a new query to old results")

        let ru = CipherAlphabet.ru.letters()
        let en = CipherAlphabet.en.letters()
        precondition(CaesarCipher.shift("Ая Zz!", by: 1, alphabet: ru) == "Ба Zz!")
        precondition(CaesarCipher.shift("Abz", by: -1, alphabet: en) == "Zay")
        precondition(CaesarCipher.allShifts("abc", alphabet: en).count == 25)
        precondition(AtbashCipher.transform("Ая Az", alphabet: ru) == "Яа Az")
        precondition(AtbashCipher.transform("Az", alphabet: en) == "Za")
        precondition(VigenereCipher.transform("ATTACKATDAWN", key: "LEMON", alphabet: en, decrypt: false) == "LXFOPVEFRNHR")
        let encrypted = VigenereCipher.transform("Привет, ёж!", key: "ключ", alphabet: ru, decrypt: false)
        precondition(VigenereCipher.transform(encrypted, key: "ключ", alphabet: ru, decrypt: true) == "Привет, ёж!")
        precondition(LetterNumberCipher.encode("А Я", alphabet: ru) == "1 / 33")
        precondition(LetterNumberCipher.decode("1,26 / 2", alphabet: en) == "az b")
        precondition(MorseCode.encode("SOS 2", alphabet: .en) == "... --- ... / ..---")
        precondition(MorseCode.decode("… — — — …", alphabet: .en) == "sttts")
        precondition(MorseCode.decode(MorseCode.encode("привет ёж", alphabet: .ru), alphabet: .ru) == "привет еж")
        precondition(KeyboardLayout.convert("Ghbdtn") == "Привет")
        precondition(KeyboardLayout.convert("Привет") == "Ghbdtn")
        print("PASS: real dictionary, anagram model empty/input/mode/debounce/cancellation regressions, all six cipher engines (RU/EN)")
    }
}
