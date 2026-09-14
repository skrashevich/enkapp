import Foundation

/// Reads the engine's sector-label color assignments without executing author JavaScript.
nonisolated enum SectorTitleStyle {
    static func colors(in html: String) -> [Int: UInt32] {
        let pattern = #"document\s*\.\s*getElementById\s*\(\s*(["'])(\d+)\1\s*\)\s*\.\s*style\s*\.\s*color\s*=\s*(["'])([^"']+)\3"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        var result: [Int: UInt32] = [:]
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let idRange = Range(match.range(at: 2), in: html),
                  let colorRange = Range(match.range(at: 4), in: html),
                  let id = Int(html[idRange]),
                  let color = rgb(String(html[colorRange])) else { continue }
            result[id] = color
        }
        return result
    }

    private static func rgb(_ value: String) -> UInt32? {
        let color = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if color.hasPrefix("#") {
            var hex = String(color.dropFirst())
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard hex.count == 6 else { return nil }
            return UInt32(hex, radix: 16)
        }
        // CSS names use sRGB values (SwiftUI's semantic colors differ).
        return ["black": 0x000000, "silver": 0xc0c0c0, "gray": 0x808080,
                "white": 0xffffff, "maroon": 0x800000, "red": 0xff0000,
                "purple": 0x800080, "fuchsia": 0xff00ff, "green": 0x008000,
                "lime": 0x00ff00, "olive": 0x808000, "yellow": 0xffff00,
                "navy": 0x000080, "blue": 0x0000ff, "teal": 0x008080,
                "aqua": 0x00ffff, "orange": 0xffa500][color]
    }
}
