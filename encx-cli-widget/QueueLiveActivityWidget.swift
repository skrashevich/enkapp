import ActivityKit
import SwiftUI
import WidgetKit

struct QueueLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: QueueActivityAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ур. \(context.state.levelNumber)")
                            .font(.headline.monospacedDigit())
                        if !context.state.teamName.isEmpty {
                            Text(context.state.teamName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        LiveActivityTimersRow(
                            levelEndsAt: context.state.levelEndsAt,
                            nextHintUnlocksAt: context.state.nextHintUnlocksAt,
                            compact: true,
                            vertical: true
                        )
                        if context.state.sectorsRequired > 0 {
                            Text(context.state.sectorsSummary)
                                .font(.caption.bold())
                        }
                        if context.state.pendingCount > 0 {
                            Text("\(context.state.pendingCount) в оч.")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    expandedBottom(context: context)
                }
            } compactLeading: {
                Text("\(context.state.levelNumber)")
                    .font(.caption.bold().monospacedDigit())
            } compactTrailing: {
                if let code = context.state.lastCode {
                    Text(code)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                } else if context.state.pendingCount > 0 {
                    Text("\(context.state.pendingCount)")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.orange)
                } else if context.state.sectorsRequired > 0 {
                    Text("\(context.state.sectorsPassed)/\(context.state.sectorsRequired)")
                        .font(.caption2.monospacedDigit())
                }
            } minimal: {
                Text("\(context.state.levelNumber)")
                    .font(.caption2.bold().monospacedDigit())
            }
        }
    }

    @ViewBuilder
    private func expandedBottom(context: ActivityViewContext<QueueActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !context.state.recentCodes.isEmpty {
                HStack(spacing: 6) {
                    ForEach(context.state.recentCodes.prefix(QueueLiveActivityLayout.dynamicIslandMaxCodes), id: \.self) { code in
                        Text(code)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.2), in: Capsule())
                    }
                }
            }

            if let hint = context.state.hints.first {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text(context.state.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<QueueActivityAttributes>) -> some View {
        ViewThatFits(in: .vertical) {
            lockScreenContent(context: context, compact: false)
            lockScreenContent(context: context, compact: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .activityBackgroundTint(.black.opacity(0.85))
        .activitySystemActionForegroundColor(.white)
    }

    @ViewBuilder
    private func lockScreenContent(
        context: ActivityViewContext<QueueActivityAttributes>,
        compact: Bool
    ) -> some View {
        let maxCodes = compact ? 1 : QueueLiveActivityLayout.lockScreenMaxCodes
        let codes = Array(context.state.recentCodes.prefix(maxCodes))
        let showHint = context.state.hints.first
        let showFooter = !compact
            && !context.state.status.isEmpty
            && showHint == nil
            && codes.isEmpty

        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            headerRow(context: context, compact: compact)
            progressRow(context: context, compact: compact)
            LiveActivityTimersRow(
                levelEndsAt: context.state.levelEndsAt,
                nextHintUnlocksAt: context.state.nextHintUnlocksAt,
                compact: compact
            )

            if !codes.isEmpty {
                codesSection(codes: codes, compact: compact)
            }

            if let hint = showHint {
                hintRow(hint, compact: compact)
            }

            if showFooter {
                footerRow(context: context)
            }
        }
    }

    private func headerRow(
        context: ActivityViewContext<QueueActivityAttributes>,
        compact: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text("EN")
                .font(.caption2.bold())
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.green.opacity(0.25), in: RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 1) {
                if !context.attributes.gameTitle.isEmpty {
                    Text(context.attributes.gameTitle)
                        .font(compact ? .subheadline.weight(.semibold) : .headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                if !context.state.lockScreenSubtitle.isEmpty {
                    Text(context.state.lockScreenSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }

            Spacer(minLength: 4)

            Image(systemName: context.state.isOnline ? "wifi" : "wifi.slash")
                .font(.caption)
                .foregroundStyle(context.state.isOnline ? .green : .orange)
        }
    }

    private func progressRow(
        context: ActivityViewContext<QueueActivityAttributes>,
        compact: Bool
    ) -> some View {
        HStack(spacing: compact ? 8 : 10) {
            if context.state.sectorsRequired > 0 {
                Label(context.state.sectorsSummary, systemImage: "square.grid.2x2")
                    .font(.caption2)
                    .lineLimit(1)
            }
            if context.state.bonusesTotal > 0 {
                Label(context.state.bonusesSummary, systemImage: "gift")
                    .font(.caption2)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if context.state.pendingCount > 0 {
                Label("\(context.state.pendingCount)", systemImage: "tray.full")
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
    }

    private func codesSection(codes: [String], compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 3) {
            Text("Пробитые коды")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            ForEach(codes, id: \.self) { code in
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text(code)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }

    private func hintRow(_ hint: String, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 3) {
            Text("Подсказки")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "lightbulb.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                Text(hint)
                    .font(.caption2)
                    .lineLimit(compact ? 1 : QueueLiveActivityLayout.lockScreenMaxHintLines)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func footerRow(context: ActivityViewContext<QueueActivityAttributes>) -> some View {
        if !context.state.status.isEmpty {
            Text(context.state.status)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

@main
struct EncxWidgetBundle: WidgetBundle {
    var body: some Widget {
        QueueLiveActivityWidget()
    }
}

#Preview("Lock Screen", as: .content, using: QueueActivityAttributes(gameTitle: "Demo Game")) {
    QueueLiveActivityWidget()
} contentStates: {
    QueueActivityAttributes.ContentState.preview
}
