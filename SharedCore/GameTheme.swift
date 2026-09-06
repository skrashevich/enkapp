import SwiftUI

enum GameTheme {
    static let background = Color.black
    static let panel = Color(white: 0.08)
    static let border = Color(white: 0.22)
    static let text = Color.white
    static let muted = Color(white: 0.62)
    static let sectionHeader = Color(red: 0.95, green: 0.82, blue: 0.18)
    static let bonusTitle = Color(red: 0.35, green: 0.85, blue: 0.95)
    static let accent = Color(red: 0.2, green: 0.72, blue: 0.35)
    static let inputBackground = Color(white: 0.12)
    static let hairline = Color(white: 0.11)
    static let fieldStroke = Color(white: 0.20)
    static let fieldFill = Color(white: 0.102)
    static let trackEmpty = Color(white: 0.169)
    static let sectorEmptyStroke = Color(white: 0.184)
}

enum GameDurationFormatter {
    /// Examples: `45 сек.`, `56 мин. 54 сек.`, `1 ч. 10 мин. 5 сек.`
    nonisolated static func minutesAndSeconds(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        var parts: [String] = []
        if hours > 0 {
            parts.append("\(hours) ч.")
        }
        if minutes > 0 {
            parts.append("\(minutes) мин.")
        }
        if secs > 0 || parts.isEmpty {
            parts.append("\(secs) сек.")
        }
        return parts.joined(separator: " ")
    }

    nonisolated static func levelDrainLabel(seconds: Int) -> String {
        if seconds <= 0 {
            return "Слив…"
        }
        return "До слива: \(minutesAndSeconds(seconds))"
    }

    nonisolated static func helpUnlockLabel(seconds: Int) -> String {
        if seconds <= 0 {
            return "Открывается…"
        }
        return "Откроется через \(minutesAndSeconds(seconds))"
    }

    nonisolated static func gameStartLabel(seconds: Int) -> String {
        if seconds <= 0 {
            return "Игра начинается…"
        }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        if hours > 0 {
            return String(format: "До начала: %d:%02d:%02d", hours, minutes, remainder)
        }
        if minutes > 0 {
            return String(format: "До начала: %d:%02d", minutes, remainder)
        }
        return "До начала: \(remainder) сек."
    }

    /// Compact `m:ss` countdown label, e.g. `52:40`, `1:05`, `0:00`.
    nonisolated static func compactDrain(seconds: Int) -> String {
        let total = max(0, seconds)
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

struct TickingCountdownText: View {
    let countdown: SyncedSecondsCountdown
    let label: (Int) -> String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let elapsed = max(0, Int(timeline.date.timeIntervalSince(countdown.syncedAt)))
            let remaining = max(0, countdown.remainSeconds - elapsed)
            Text(label(remaining))
                .monospacedDigit()
        }
    }
}

struct GameSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(GameTheme.sectionHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
