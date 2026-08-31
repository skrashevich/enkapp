import SwiftUI
import UIKit

/// Displays decimal latitude/longitude pairs as links to Yandex Maps.
struct CoordinateText: View {
    let text: String

    var body: some View {
        Text(CoordinateLinkifier.attributedString(from: text))
            .environment(\.openURL, OpenURLAction { url in
                guard CoordinateLinkifier.isYandexMapsURL(url) else {
                    return .systemAction
                }

                CoordinateLinkifier.openYandexMaps(url)
                return .handled
            })
    }
}

enum CoordinateLinkifier {
    private struct Match {
        let range: Range<String.Index>
        let latitude: Double
        let longitude: Double
    }

    /// Supports the two formats most often used in level text:
    /// `55.7558, 37.6173` and `55,7558 37,6173`.
    private static let patterns = [
        #"(?<![\d.,])([+-]?\d{1,2}\.\d+)\s*(?:[,;]|\s+)\s*([+-]?\d{1,3}\.\d+)(?![\d.,])"#,
        #"(?<![\d.,])([+-]?\d{1,2},\d+)\s*(?:;|\s+)\s*([+-]?\d{1,3},\d+)(?![\d.,])"#
    ]

    static func attributedString(from text: String) -> AttributedString {
        var result = AttributedString()
        var cursor = text.startIndex

        for match in matches(in: text) {
            result.append(AttributedString(String(text[cursor..<match.range.lowerBound])))

            var coordinate = AttributedString(String(text[match.range]))
            coordinate.link = yandexMapsURL(latitude: match.latitude, longitude: match.longitude)
            coordinate.foregroundColor = GameTheme.bonusTitle
            coordinate.underlineStyle = .single
            result.append(coordinate)

            cursor = match.range.upperBound
        }

        result.append(AttributedString(String(text[cursor...])))
        return result
    }

    static func isYandexMapsURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "yandexmaps"
    }

    static func openYandexMaps(_ url: URL) {
        UIApplication.shared.open(url) { didOpen in
            guard !didOpen, let fallbackURL = webFallbackURL(for: url) else { return }
            UIApplication.shared.open(fallbackURL)
        }
    }

    private static func matches(in text: String) -> [Match] {
        let fullRange = NSRange(text.startIndex..., in: text)
        var candidates: [Match] = []

        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }

            for result in expression.matches(in: text, range: fullRange) {
                guard result.numberOfRanges == 3,
                      let range = Range(result.range(at: 0), in: text),
                      let latitudeRange = Range(result.range(at: 1), in: text),
                      let longitudeRange = Range(result.range(at: 2), in: text),
                      let latitude = decimalNumber(text[latitudeRange]),
                      let longitude = decimalNumber(text[longitudeRange]),
                      (-90...90).contains(latitude),
                      (-180...180).contains(longitude) else {
                    continue
                }

                candidates.append(Match(range: range, latitude: latitude, longitude: longitude))
            }
        }

        let sorted = candidates.sorted { $0.range.lowerBound < $1.range.lowerBound }
        var nonOverlapping: [Match] = []
        for candidate in sorted
        where (nonOverlapping.last?.range.upperBound ?? text.startIndex) <= candidate.range.lowerBound {
            nonOverlapping.append(candidate)
        }
        return nonOverlapping
    }

    private static func decimalNumber(_ value: Substring) -> Double? {
        Double(value.replacingOccurrences(of: ",", with: "."))
    }

    private static func yandexMapsURL(latitude: Double, longitude: Double) -> URL? {
        var components = URLComponents()
        components.scheme = "yandexmaps"
        components.host = "maps.yandex.ru"
        components.path = "/"
        components.queryItems = [
            URLQueryItem(name: "ll", value: "\(longitude),\(latitude)"),
            URLQueryItem(name: "pt", value: "\(longitude),\(latitude)"),
            URLQueryItem(name: "z", value: "16")
        ]
        return components.url
    }

    private static func webFallbackURL(for url: URL) -> URL? {
        guard let source = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let coordinates = source.queryItems?.first(where: { $0.name == "ll" })?.value else {
            return nil
        }

        var components = URLComponents(string: "https://yandex.ru/maps/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: coordinates),
            URLQueryItem(name: "pt", value: coordinates),
            URLQueryItem(name: "z", value: "16")
        ]
        return components?.url
    }
}
