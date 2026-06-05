import SwiftUI
import WidgetKit

private enum GameWidgetURLs {
    static let game = URL(string: "encx-cli://game")!
    static let flushQueue = URL(string: "encx-cli://flush-queue")!
    static let codes = URL(string: "encx-cli://codes")!
}

struct GameHomeScreenWidget: Widget {
    static let kind = GameWidgetSnapshotStore.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: GameHomeScreenProvider()) { entry in
            GameHomeScreenWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color(red: 0.12, green: 0.13, blue: 0.16), Color(red: 0.08, green: 0.09, blue: 0.11)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("Игра Encounter")
        .description("Уровень, секторы, таймеры и очередь кодов прямо на рабочем столе.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct GameHomeScreenEntry: TimelineEntry {
    let date: Date
    let snapshot: GameWidgetSnapshot
}

struct GameHomeScreenProvider: TimelineProvider {
    func placeholder(in context: Context) -> GameHomeScreenEntry {
        GameHomeScreenEntry(date: Date(), snapshot: .previewActiveGame)
    }

    func getSnapshot(in context: Context, completion: @escaping (GameHomeScreenEntry) -> Void) {
        completion(GameHomeScreenEntry(date: Date(), snapshot: loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GameHomeScreenEntry>) -> Void) {
        let snapshot = loadSnapshot()
        let entry = GameHomeScreenEntry(date: Date(), snapshot: snapshot)
        let refresh = snapshot.hasActiveGame ? snapshot.nextRefreshDate : Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func loadSnapshot() -> GameWidgetSnapshot {
        GameWidgetSnapshotStore.load() ?? .loggedOut
    }
}

struct GameHomeScreenWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GameHomeScreenEntry

    var body: some View {
        if entry.snapshot.hasActiveGame {
            activeGameView
        } else {
            placeholderView
        }
    }

    private var activeGameView: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 6) {
            headerRow
            if family == .systemLarge {
                levelStatusBlock
                sectorProgressBlock
                LiveActivityTimersRow(
                    levelEndsAt: entry.snapshot.levelEndsAt,
                    nextHintUnlocksAt: entry.snapshot.nextHintUnlocksAt,
                    compact: false
                )
                if !entry.snapshot.recentCodes.isEmpty {
                    recentCodesRow
                } else if let hint = entry.snapshot.hints.first {
                    hintRow(hint)
                }
                Spacer(minLength: 0)
                actionButtons
            } else {
                mediumBody
            }
        }
        .padding(14)
        .widgetURL(GameWidgetURLs.game)
    }

    private var headerRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                if !entry.snapshot.gameTitle.isEmpty {
                    Text(entry.snapshot.gameTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(entry.snapshot.levelTitle.isEmpty ? "Encounter" : entry.snapshot.levelTitle)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(entry.date, format: .dateTime.day().month().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Image(systemName: entry.snapshot.isOnline ? "wifi" : "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(entry.snapshot.isOnline ? .green : .orange)
            }
        }
    }

    private var levelStatusBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Состояние игры")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                if !entry.snapshot.teamName.isEmpty {
                    Text(entry.snapshot.teamName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if entry.snapshot.pendingQueueCount > 0 {
                    Label("\(entry.snapshot.pendingQueueCount) в оч.", systemImage: "tray.full")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }
                if !entry.snapshot.status.isEmpty {
                    Text(entry.snapshot.status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var sectorProgressBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            if entry.snapshot.sectorsRequired > 0 {
                ProgressView(value: entry.snapshot.sectorProgress)
                    .tint(.white)
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2")
                        .font(.caption2)
                    Text(entry.snapshot.sectorsSummary)
                        .font(.caption)
                    if entry.snapshot.bonusesTotal > 0 {
                        Text("· Бонусы \(entry.snapshot.bonusesPassed)/\(entry.snapshot.bonusesTotal)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var mediumBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !entry.snapshot.teamName.isEmpty {
                Text(entry.snapshot.teamName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if entry.snapshot.sectorsRequired > 0 {
                ProgressView(value: entry.snapshot.sectorProgress)
                    .tint(.white)
                Text(entry.snapshot.sectorsSummary)
                    .font(.caption2)
            }
            LiveActivityTimersRow(
                levelEndsAt: entry.snapshot.levelEndsAt,
                nextHintUnlocksAt: entry.snapshot.nextHintUnlocksAt,
                compact: true
            )
            if entry.snapshot.pendingQueueCount > 0 {
                Label("\(entry.snapshot.pendingQueueCount) в очереди", systemImage: "tray.full")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
        }
    }

    private var recentCodesRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Пробитые коды")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            ForEach(entry.snapshot.recentCodes.prefix(2), id: \.self) { code in
                Label(code, systemImage: "checkmark.circle.fill")
                    .font(.caption.monospaced())
                    .foregroundStyle(.green)
                    .lineLimit(1)
            }
        }
    }

    private func hintRow(_ hint: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "lightbulb.fill")
                .font(.caption2)
                .foregroundStyle(.yellow)
            Text(hint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            widgetActionLink(title: "Игра", systemImage: "gamecontroller.fill", url: GameWidgetURLs.game)
            widgetActionLink(title: "Очередь", systemImage: "arrow.up.circle.fill", url: GameWidgetURLs.flushQueue)
            widgetActionLink(title: "Коды", systemImage: "number", url: GameWidgetURLs.codes)
            Spacer(minLength: 0)
        }
    }

    private func widgetActionLink(title: String, systemImage: String, url: URL) -> some View {
        Link(destination: url) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.body)
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var placeholderView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("EN")
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.green.opacity(0.25), in: RoundedRectangle(cornerRadius: 5))
                Spacer()
            }
            Text("enkapp")
                .font(.headline)
            Text(entry.snapshot.placeholderMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if family == .systemLarge {
                Text("Удерживайте иконку enkapp → «Изменить главный экран» → «Добавить виджет», или добавьте виджет «Игра Encounter» из галереи.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .widgetURL(GameWidgetURLs.game)
    }
}

#Preview(as: .systemLarge) {
    GameHomeScreenWidget()
} timeline: {
    GameHomeScreenEntry(date: Date(), snapshot: .previewActiveGame)
}

#Preview("Placeholder", as: .systemMedium) {
    GameHomeScreenWidget()
} timeline: {
    GameHomeScreenEntry(date: Date(), snapshot: .loggedOut)
}
