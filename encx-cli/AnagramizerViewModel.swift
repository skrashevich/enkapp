import Foundation
import Observation

/// Состояние загрузки словаря анаграмайзера.
enum AnagramDictionaryState: Equatable {
    case loading
    case ready
    case error(String)
}

@Observable
@MainActor
final class AnagramizerViewModel {
    // MARK: - Ввод

    var mode: AnagramMode = .pattern
    var pattern: String = ""
    var letters: String = ""

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

    init(engine: AnagramEngine? = nil) {
        self.engine = engine
        if engine != nil {
            dictionaryState = .ready
        }
    }

    // MARK: - Загрузка словаря

    func loadDictionaryIfNeeded() {
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
            mode: mode,
            pattern: pattern,
            letters: letters,
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
