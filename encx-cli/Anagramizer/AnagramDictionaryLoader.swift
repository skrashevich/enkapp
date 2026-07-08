import Foundation

// MARK: - Загрузчик словаря (off-main)
//
// Загружает бандл-ресурс "ru_dict.bin" через mmap вне MainActor и строит движок.
// НЕ материализует слова в String.

/// `nonisolated` на уровне типа: проект собирается с `-default-isolation MainActor`;
/// без опт-аута static-члены (включая resourceName/resourceExtension) стали бы
/// MainActor-изолированными, а сам загрузчик обязан работать off-main.
public nonisolated enum AnagramDictionaryLoader {

    /// Согласованное имя бандл-ресурса.
    public static let resourceName = "ru_dict"
    public static let resourceExtension = "bin"

    /// Загружает бандл-словарь и возвращает готовый движок.
    /// Бросает `.dictionaryUnavailable`, если ресурс не найден, `.dictionaryCorrupt` — при плохом формате.
    nonisolated public static func loadBundledDictionary() async throws -> AnagramEngine {
        // Тяжёлая операция — уводим с MainActor через detached-таск.
        return try await Task.detached(priority: .userInitiated) {
            guard let url = Bundle.main.url(
                forResource: resourceName,
                withExtension: resourceExtension
            ) else {
                throw AnagramEngineError.dictionaryUnavailable
            }
            return try AnagramEngineImpl(dictionaryURL: url)
        }.value
    }

    /// Тестируемая загрузка из произвольного URL (для харнесса/тестов).
    nonisolated public static func loadDictionary(at url: URL) async throws -> AnagramEngine {
        return try await Task.detached(priority: .userInitiated) {
            try AnagramEngineImpl(dictionaryURL: url)
        }.value
    }
}
