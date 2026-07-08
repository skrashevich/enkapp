import SwiftUI

/// Compact and minimal Dynamic Island layouts — space is ~40 pt per side.
struct DynamicIslandCompactLeading: View {
    let state: QueueActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 3) {
            if !state.isOnline {
                Image(systemName: "wifi.slash")
                    .font(.caption2)
                    .foregroundStyle(WidgetTheme.warning)
            }
            Text(state.dynamicIslandCompactLeading)
                .font(.caption.bold().monospacedDigit())
        }
    }
}

struct DynamicIslandCompactTrailing: View {
    let state: QueueActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.hasActiveHintTimer, state.hasActiveLevelTimer,
               let hintEndsAt = state.nextHintUnlocksAt,
               let levelEndsAt = state.levelEndsAt {
                VStack(alignment: .trailing, spacing: -1) {
                    compactCountdownRow(
                        endsAt: hintEndsAt,
                        systemImage: "lightbulb.fill",
                        tint: WidgetTheme.hint
                    )
                    compactCountdownRow(
                        endsAt: levelEndsAt,
                        systemImage: "timer",
                        tint: WidgetTheme.warning
                    )
                }
            } else if state.hasActiveHintTimer, let endsAt = state.nextHintUnlocksAt {
                compactCountdownRow(
                    endsAt: endsAt,
                    systemImage: "lightbulb.fill",
                    tint: WidgetTheme.hint
                )
            } else if state.hasActiveLevelTimer, let endsAt = state.levelEndsAt {
                compactCountdown(endsAt: endsAt, tint: .primary)
            } else if state.pendingCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "tray.full")
                        .font(.caption2)
                    Text("\(state.pendingCount)")
                        .font(.caption.bold().monospacedDigit())
                }
                .foregroundStyle(.orange)
            } else if state.sectorsRequired > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "square.grid.2x2")
                        .font(.caption2)
                    Text("\(state.sectorsPassed)/\(state.sectorsRequired)")
                        .font(.caption2.bold().monospacedDigit())
                }
            } else if let code = state.compactDisplayCode {
                HStack(spacing: 2) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(WidgetTheme.accent)
                    Text(code)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                }
            } else if state.hasRecentLongCode {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(WidgetTheme.accent)
            } else if state.bonusesTotal > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "gift")
                        .font(.caption2)
                    Text("\(state.bonusesPassed)/\(state.bonusesTotal)")
                        .font(.caption2.bold().monospacedDigit())
                }
            } else {
                // Fallback so the trailing region is never blank (no timers/queue/codes/bonuses).
                Image(systemName: "gamecontroller.fill")
                    .font(.caption2)
                    .foregroundStyle(WidgetTheme.accent)
            }
        }
    }

    private func compactCountdownRow(endsAt: Date, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.caption2)
                .foregroundStyle(tint)
            compactCountdown(endsAt: endsAt, tint: .primary)
        }
    }

    private func compactCountdown(endsAt: Date, tint: Color) -> some View {
        Text(timerInterval: Date()...endsAt, countsDown: true)
            .font(.caption.bold().monospacedDigit())
            .foregroundStyle(tint)
            .multilineTextAlignment(.trailing)
    }
}

struct DynamicIslandMinimalContent: View {
    let state: QueueActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.hasActiveLevelTimer, let endsAt = state.levelEndsAt {
                Text(timerInterval: Date()...endsAt, countsDown: true)
                    .font(.caption2.bold().monospacedDigit())
            } else if state.pendingCount > 0 {
                Text("\(state.pendingCount)")
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(WidgetTheme.warning)
            } else if state.levelNumber > 0 {
                Text("\(state.levelNumber)")
                    .font(.caption2.bold().monospacedDigit())
            } else {
                Text("EN")
                    .font(.caption2.bold())
            }
        }
    }
}
