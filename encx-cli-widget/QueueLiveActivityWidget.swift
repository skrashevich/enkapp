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
                    VStack(alignment: .leading, spacing: 4) {
                        WidgetChip(
                            title: "Ур. \(context.state.levelNumber)",
                            systemImage: "flag.checkered",
                            tint: WidgetTheme.accent
                        )
                        if !context.state.teamName.isEmpty {
                            Text(context.state.teamName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        LiveActivityTimersRow(
                            levelEndsAt: context.state.levelEndsAt,
                            nextHintUnlocksAt: context.state.nextHintUnlocksAt,
                            compact: true,
                            vertical: true
                        )
                        if context.state.sectorsRequired > 0 {
                            WidgetChip(
                                title: "\(context.state.sectorsPassed)/\(context.state.sectorsRequired)",
                                systemImage: "square.grid.2x2",
                                tint: WidgetTheme.info
                            )
                        }
                        if context.state.pendingCount > 0 {
                            WidgetChip(
                                title: "\(context.state.pendingCount)",
                                systemImage: "tray.full",
                                tint: WidgetTheme.warning
                            )
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    expandedBottom(context: context)
                }
            } compactLeading: {
                DynamicIslandCompactLeading(state: context.state)
            } compactTrailing: {
                DynamicIslandCompactTrailing(state: context.state)
            } minimal: {
                DynamicIslandMinimalContent(state: context.state)
            }
        }
    }

    @ViewBuilder
    private func expandedBottom(context: ActivityViewContext<QueueActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !context.state.recentCodes.isEmpty {
                HStack(spacing: 6) {
                    ForEach(context.state.recentCodes.prefix(QueueLiveActivityLayout.dynamicIslandMaxCodes), id: \.self) { code in
                        Text(code)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(WidgetTheme.accent.opacity(0.20), in: Capsule())
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
        .activityBackgroundTint(WidgetTheme.backgroundBottom.opacity(0.92))
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

        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
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
        HStack(alignment: .center, spacing: 10) {
            Text(context.state.levelNumber > 0 ? "\(context.state.levelNumber)" : "EN")
                .font((compact ? Font.caption : Font.subheadline).weight(.black).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: compact ? 28 : 34, height: compact ? 28 : 34)
                .background(WidgetTheme.accent, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 1) {
                if !context.attributes.gameTitle.isEmpty {
                    Text(context.attributes.gameTitle)
                        .font(compact ? .subheadline.weight(.semibold) : .headline.weight(.bold))
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
                .foregroundStyle(context.state.isOnline ? WidgetTheme.accent : WidgetTheme.warning)
                .padding(7)
                .background(WidgetTheme.panel, in: Circle())
        }
    }

    private func progressRow(
        context: ActivityViewContext<QueueActivityAttributes>,
        compact: Bool
    ) -> some View {
        HStack(spacing: compact ? 7 : 8) {
            if context.state.sectorsRequired > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "square.grid.2x2")
                            .font(.caption2)
                            .foregroundStyle(WidgetTheme.info)
                        Text(context.state.sectorsSummary)
                            .font(.caption2.weight(.semibold))
                    }
                    ProgressView(value: Double(context.state.sectorsPassed), total: Double(context.state.sectorsRequired))
                        .tint(WidgetTheme.accent)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(WidgetTheme.panel, in: RoundedRectangle(cornerRadius: 8))
            }
            if context.state.bonusesTotal > 0 {
                WidgetChip(
                    title: "\(context.state.bonusesPassed)/\(context.state.bonusesTotal)",
                    systemImage: "gift",
                    tint: WidgetTheme.info
                )
            }
            Spacer(minLength: 0)
            if context.state.pendingCount > 0 {
                WidgetChip(
                    title: "\(context.state.pendingCount)",
                    systemImage: "tray.full",
                    tint: WidgetTheme.warning
                )
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
                        .foregroundStyle(WidgetTheme.accent)
                    Text(code)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(WidgetTheme.panel, in: RoundedRectangle(cornerRadius: 8))
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
                    .foregroundStyle(WidgetTheme.hint)
                Text(hint)
                    .font(.caption2)
                    .lineLimit(compact ? 1 : QueueLiveActivityLayout.lockScreenMaxHintLines)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(WidgetTheme.panel, in: RoundedRectangle(cornerRadius: 8))
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
        GameHomeScreenWidget()
        QueueLiveActivityWidget()
    }
}

#Preview("Lock Screen", as: .content, using: QueueActivityAttributes(gameTitle: "Demo Game")) {
    QueueLiveActivityWidget()
} contentStates: {
    QueueActivityAttributes.ContentState.preview
}
