import SwiftUI

struct LiveActivityTimerLabel: View {
    let title: String
    let endsAt: Date?

    var body: some View {
        if let endsAt, endsAt > Date() {
            HStack(spacing: 3) {
                Text(title)
                Text(timerInterval: Date()...endsAt, countsDown: true)
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
        if showsLevelTimer {
            LiveActivityTimerLabel(title: "До слива:", endsAt: levelEndsAt)
        }
        if showsLevelTimer && showsHintTimer, let separator {
            Text(separator)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        if showsHintTimer {
            LiveActivityTimerLabel(title: "Подсказка:", endsAt: nextHintUnlocksAt)
        }
    }
}
