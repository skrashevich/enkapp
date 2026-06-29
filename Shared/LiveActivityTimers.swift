import SwiftUI

enum WidgetTheme {
    static let backgroundTop = Color(red: 0.10, green: 0.12, blue: 0.14)
    static let backgroundBottom = Color(red: 0.04, green: 0.05, blue: 0.06)
    static let panel = Color.white.opacity(0.08)
    static let panelStrong = Color.white.opacity(0.13)
    static let border = Color.white.opacity(0.12)
    static let accent = Color(red: 0.20, green: 0.72, blue: 0.35)
    static let warning = Color.orange
    static let hint = Color.yellow
    static let info = Color(red: 0.35, green: 0.85, blue: 0.95)
}

struct WidgetChip: View {
    let title: String
    let systemImage: String
    var tint: Color = WidgetTheme.accent

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tint.opacity(0.16), in: Capsule())
    }
}

struct LiveActivityTimerLabel: View {
    let title: String
    let endsAt: Date?
    var systemImage: String?
    var tint: Color = .primary

    var body: some View {
        if let endsAt, endsAt > Date() {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                }
                Text(title)
                    .foregroundStyle(.secondary)
                Text(timerInterval: Date()...endsAt, countsDown: true)
                    .foregroundStyle(.primary)
            }
        }
    }
}

struct LiveActivityTimersRow: View {
    let levelEndsAt: Date?
    let nextHintUnlocksAt: Date?
    var compact: Bool = false
    var vertical: Bool = false

    private var showsLevelTimer: Bool {
        levelEndsAt.map { $0 > Date() } ?? false
    }

    private var showsHintTimer: Bool {
        nextHintUnlocksAt.map { $0 > Date() } ?? false
    }

    private var timerFont: Font {
        compact ? .caption2 : .caption
    }

    @ViewBuilder
    var body: some View {
        if showsLevelTimer || showsHintTimer {
            Group {
                if vertical {
                    VStack(alignment: .trailing, spacing: 2) {
                        timerItems(separator: nil)
                    }
                } else {
                    HStack(spacing: compact ? 8 : 12) {
                        timerItems(separator: "·")
                        Spacer(minLength: 0)
                    }
                }
            }
            .font(timerFont)
            .foregroundStyle(.primary)
            .monospacedDigit()
        }
    }

    @ViewBuilder
    private func timerItems(separator: String?) -> some View {
        if showsLevelTimer && showsHintTimer, let separator {
            hintTimer
            Text(separator)
                .font(.caption2)
                .foregroundStyle(.secondary)
            levelTimer
        } else {
            if showsHintTimer {
                hintTimer
            }
            if showsLevelTimer {
                levelTimer
            }
        }
    }

    private var hintTimer: some View {
        LiveActivityTimerLabel(
            title: "Подсказка",
            endsAt: nextHintUnlocksAt,
            systemImage: "lightbulb.fill",
            tint: WidgetTheme.hint
        )
    }

    private var levelTimer: some View {
        LiveActivityTimerLabel(
            title: "Слив",
            endsAt: levelEndsAt,
            systemImage: "timer",
            tint: WidgetTheme.warning
        )
    }
}
