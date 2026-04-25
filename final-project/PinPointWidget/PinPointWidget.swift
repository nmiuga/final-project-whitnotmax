//
//  PinPointWidget.swift
//  PinPointWidget
//
//  Created by Codex on 4/22/26.
//

import SwiftUI
import WidgetKit

private struct WidgetQuickSpot: Decodable {
    let name: String
    let timestamp: Date
    let iconEmoji: String?
}

private struct PinPointWidgetEntry: TimelineEntry {
    let date: Date
    let quickSpot: WidgetQuickSpot?
}

private struct PinPointWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PinPointWidgetEntry {
        PinPointWidgetEntry(
            date: .now,
            quickSpot: WidgetQuickSpot(
                name: "Saved Place",
                timestamp: .now.addingTimeInterval(-900),
                iconEmoji: "📍"
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PinPointWidgetEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PinPointWidgetEntry>) -> Void) {
        let entry = makeEntry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func makeEntry() -> PinPointWidgetEntry {
        PinPointWidgetEntry(
            date: .now,
            quickSpot: SharedWidgetStore.loadQuickSpot()
        )
    }
}

private enum SharedWidgetStore {
    static let appGroupIdentifier = "group.whitmans.final-project"
    static let quickSpotStorageKey = "quickSpot"

    static func loadQuickSpot() -> WidgetQuickSpot? {
        guard
            let defaults = UserDefaults(suiteName: appGroupIdentifier),
            let data = defaults.data(forKey: quickSpotStorageKey)
        else {
            return nil
        }

        return try? JSONDecoder().decode(WidgetQuickSpot.self, from: data)
    }
}

struct PinPointQuickSaveWidget: Widget {
    private let kind = "PinPointQuickSaveWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PinPointWidgetProvider()) { entry in
            PinPointQuickSaveWidgetView(entry: entry)
                .widgetURL(URL(string: "pinpoint://save-quick"))
        }
        .configurationDisplayName("Quick Save")
        .description("Open PinPoint and save your current spot right away.")
        .supportedFamilies([.systemSmall])
    }
}

struct PinPointGuideWidget: Widget {
    private let kind = "PinPointGuideWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PinPointWidgetProvider()) { entry in
            PinPointGuideWidgetView(entry: entry)
                .widgetURL(entry.quickSpot == nil ? nil : URL(string: "pinpoint://guide-quick"))
        }
        .configurationDisplayName("Guide Me")
        .description("Jump back into PinPoint and guide yourself to your saved quick spot.")
        .supportedFamilies([.systemSmall])
    }
}

private struct PinPointQuickSaveWidgetView: View {
    let entry: PinPointWidgetEntry

    var body: some View {
        PinPointWidgetCard(
            headerSymbol: "location.fill",
            headerTint: Color.accentColor,
            headerText: "Quick Save",
            title: "Quick Save",
            subtitle: "Save your current spot."
        ) {
            statusBlock(for: entry.quickSpot, emptyText: "No quick spot yet")
        }
    }
}

private struct PinPointGuideWidgetView: View {
    let entry: PinPointWidgetEntry

    var body: some View {
        PinPointWidgetCard(
            headerSymbol: "location.north.line.fill",
            headerTint: .orange,
            headerText: "Guide Me",
            title: "Guide Me",
            subtitle: entry.quickSpot == nil
                ? "Save a quick spot first."
                : "Open your saved spot."
        ) {
            statusBlock(for: entry.quickSpot, emptyText: "No quick spot yet")
        }
        .opacity(entry.quickSpot == nil ? 0.72 : 1)
    }
}

private struct PinPointWidgetCard<StatusContent: View>: View {
    let headerSymbol: String
    let headerTint: Color
    let headerText: String
    let title: String
    let subtitle: String
    @ViewBuilder let statusContent: () -> StatusContent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Image(systemName: headerSymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(headerTint))

                Spacer()

                Text(headerText)
                    .font(.caption)
                    .foregroundStyle(widgetSecondaryTextColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 18)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(widgetSecondaryTextColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.9)
            }

            Spacer(minLength: 14)

            statusContent()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .pinPointWidgetBackground()
    }
}

private struct WidgetSpotIcon: View {
    let iconEmoji: String?

    var body: some View {
        if let iconEmoji, !iconEmoji.isEmpty {
            Text(iconEmoji)
                .font(.body)
        } else {
            Image(systemName: "mappin.circle.fill")
                .font(.body)
                .foregroundStyle(Color.accentColor)
        }
    }
}

@ViewBuilder
private func statusBlock(for quickSpot: WidgetQuickSpot?, emptyText: String) -> some View {
    if let quickSpot {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                WidgetSpotIcon(iconEmoji: quickSpot.iconEmoji)
                    .frame(width: 18, alignment: .leading)

                Text(quickSpot.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Text("Saved \(relativeTimestampText(for: quickSpot.timestamp))")
                .font(.caption2)
                .foregroundStyle(widgetSecondaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    } else {
        Text(emptyText)
            .font(.caption2)
            .foregroundStyle(widgetSecondaryTextColor)
            .lineLimit(1)
    }
}

private let widgetSecondaryTextColor = Color(uiColor: .secondaryLabel)

private extension View {
    @ViewBuilder
    func pinPointWidgetBackground() -> some View {
        if #available(iOS 17.0, *) {
            self
                .containerBackground(
                    LinearGradient(
                        colors: [
                            Color(.systemBackground),
                            Color(.secondarySystemBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    for: .widget
                )
        } else {
            self
                .padding()
                .background(Color(.systemBackground))
        }
    }
}

private func relativeTimestampText(for date: Date) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince(date)))

    if seconds < 60 {
        return "just now"
    }

    let minutes = seconds / 60
    if minutes < 60 {
        return "\(minutes)m ago"
    }

    let hours = minutes / 60
    if hours < 24 {
        return "\(hours)h ago"
    }

    let days = hours / 24
    return "\(days)d ago"
}
