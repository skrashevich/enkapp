import Foundation
import Observation

/// Состояние загрузки словаря анаграмайзера.
enum AnagramDictionaryState: Equatable {
    case loading
    case ready
    case error(String)
}

/// Видимый пользователю режим поиска. В интерфейсе только два семейства;
/// четыре движковых режима (`AnagramMode`) выводятся из UI-режима и опций.
enum AnagramUIMode: Equatable {
    case letters   // поиск слов из набора букв (подслова / точная анаграмма)
    case pattern   // поиск по шаблону с джокерами (+ опциональный пул букв)
}

@Observable
@MainActor
final class AnagramizerViewModel {
    // MARK: - Ввод

    /// Видимый режим (2 варианта). Движковый режим считается в `effectiveMode`.
    var uiMode: AnagramUIMode = .letters
    /// Только для `.letters`: искать точные анаграммы (использовать все буквы),
    /// иначе — любые подслова.
    var useAllLetters: Bool = false
    var pattern: String = ""
    /// Набор букв для режима «По буквам» (подслова / анаграмма).
    var letters: String = ""
    /// Пул букв для джокеров в режиме «По шаблону». Хранится отдельно от `letters`,
    /// чтобы буквы одного режима не протекали в другой и не переключали движковый
    /// режим неявно (иначе пустой шаблон-поиск молча стал бы `.combined`).
    var poolLetters: String = ""

    /// Движковый режим, выведенный из видимого режима и опций:
    /// - `.letters` + все буквы → `.anagram`, иначе → `.subword`;
    /// - `.pattern` с непустым пулом букв → `.combined`, иначе → `.pattern`.
    var effectiveMode: AnagramMode {
        switch uiMode {
        case .letters:
            return useAllLetters ? .anagram : .subword
        case .pattern:
            let hasPool = !poolLetters.trimmingCharacters(in: .whitespaces).isEmpty
            return hasPool ? .combined : .pattern
        }
    }

    /// Буквы, передаваемые движку. В режиме шаблона движок использует поле `letters`
    /// как пул для джокеров (`.combined`), поэтому подставляем `poolLetters`.
    var effectiveLetters: String {
        uiMode == .pattern ? poolLetters : letters
    }

    // MARK: - Фильтры

    var minLength: Int?
    var maxLength: Int?
    var foldYo: Bool = true
    var blankCount: Int = 0
    var sort: AnagramSort = .byLengthDesc

    // MARK: - Состояние словаря

    private(set) var dictionaryState: AnagramDictionaryState = .loading

    // MARK: - Результаты

    private(set) var words: [String] = []
    private(set) var totalCount: Int = 0
    private(set) var hasMore: Bool = false
    private(set) var isSearching: Bool = false
    private(set) var searchErrorMessage: String?
    private(set) var hasSearched: Bool = false

    private let pageLimit = 200

    private var engine: AnagramEngine?
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    /// В режиме скриншотов состояние засеяно фикстурой; настоящий словарь не грузим.
    private var isScreenshotFixture = false

    init(engine: AnagramEngine? = nil) {
        self.engine = engine
        if engine != nil {
            dictionaryState = .ready
        }
    }

    // MARK: - Скриншот-фикстура

    /// Готовая модель для скриншотов: детерминированное состояние без движка,
    /// сети и асинхронной загрузки словаря — по образцу фикстур `EncounterViewModel`.
    static func screenshotModel() -> AnagramizerViewModel {
        let model = AnagramizerViewModel()
        model.applyScreenshotFixture()
        return model
    }

    private func applyScreenshotFixture() {
        isScreenshotFixture = true
        uiMode = .letters
        useAllLetters = true // точная анаграмма: все буквы «снегурочки»
        letters = "снегурочка"
        foldYo = true
        sort = .byLengthDesc
        dictionaryState = .ready
        hasSearched = true
        isSearching = false
        searchErrorMessage = nil
        // Все варианты — честные анаграммы «снегурочки» (те же 10 букв),
        words = [
            "огнесручка", "кочегарнус", "чеснокруга",
            "огурченска", "негросучка", "сургеночка"
        ]
        totalCount = words.count
        hasMore = false
    }

    // MARK: - Загрузка словаря

    func loadDictionaryIfNeeded() {
        guard !isScreenshotFixture else { return }
        guard engine == nil else { return }
        dictionaryState = .loading
        Task {
            do {
                let loaded = try await AnagramDictionaryLoader.loadBundledDictionary()
                await MainActor.run {
                    self.engine = loaded
                    self.dictionaryState = .ready
                }
            } catch {
                await MainActor.run {
                    self.dictionaryState = .error(Self.message(for: error))
                }
            }
        }
    }

    // MARK: - Поиск (с дебаунсом)

    /// Вызывается при изменении полей ввода. Планирует поиск через 300мс,
    /// отменяя предыдущий запланированный поиск.
    func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await runSearch(offset: 0)
        }
    }

    /// Немедленный поиск (кнопка «Найти»).
    func searchNow() {
        searchTask?.cancel()
        searchTask = Task {
            await runSearch(offset: 0)
        }
    }

    /// Использовать найденное слово как новый набор букв и сразу искать по нему.
    /// Переключает режим на «По буквам», чтобы слово стало входом движка.
    func useWordAsInput(_ word: String) {
        uiMode = .letters
        letters = word
        searchNow()
    }

    /// Подгрузить следующую страницу результатов.
    func loadMore() {
        guard hasMore, !isSearching else { return }
        searchTask?.cancel()
        searchTask = Task {
            await runSearch(offset: words.count)
        }
    }

    private func runSearch(offset: Int) async {
        guard let engine else { return }

        searchGeneration += 1
        let generation = searchGeneration

        let query = AnagramQuery(
            mode: effectiveMode,
            pattern: pattern,
            letters: effectiveLetters,
            minLength: minLength,
            maxLength: maxLength,
            foldYo: foldYo,
            blankCount: blankCount,
            sort: sort
        )

        isSearching = true
        searchErrorMessage = nil

        let result: Result<AnagramResultPage, Error> = await Task.detached(priority: .userInitiated) {
            do {
                return .success(try engine.search(query, limit: self.pageLimit, offset: offset))
            } catch {
                return .failure(error)
            }
        }.value

        guard generation == searchGeneration else { return }
        isSearching = false
        hasSearched = true

        switch result {
        case .success(let page):
            if offset == 0 {
                words = page.words
            } else {
                words.append(contentsOf: page.words)
            }
            totalCount = page.totalCount
            hasMore = page.hasMore
        case .failure(let error):
            searchErrorMessage = Self.message(for: error)
            if offset == 0 {
                words = []
                totalCount = 0
                hasMore = false
            }
        }
    }

    private static func message(for error: Error) -> String {
        guard let engineError = error as? AnagramEngineError else {
            return error.localizedDescription
        }
        switch engineError {
        case .notReady:
            return "Словарь ещё не готов. Попробуйте чуть позже."
        case .dictionaryUnavailable:
            return "Словарь недоступен: файл не найден в приложении."
        case .dictionaryCorrupt:
            return "Словарь повреждён и не может быть загружен."
        case .invalidQuery(let detail):
            return detail.isEmpty ? "Некорректный запрос." : detail
        }
    }
}
