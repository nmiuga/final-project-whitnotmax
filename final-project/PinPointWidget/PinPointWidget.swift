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
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "location.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Circle().fill(Color.accentColor))

                Spacer()

                Text("PinPoint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 18)

            VStack(alignment: .leading, spacing: 6) {
                Text("Quick Save")
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text("Tap to save Quick Spot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.9)
            }

            Spacer(minLength: 14)

            bottomStatus
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .pinPointWidgetBackground()
    }

    @ViewBuilder
    private var bottomStatus: some View {
        if let quickSpot = entry.quickSpot {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    WidgetSpotIcon(iconEmoji: quickSpot.iconEmoji)
                    Text(quickSpot.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Text("Saved \(relativeTimestampText(for: quickSpot.timestamp))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        } else {
            Text("No quick spot yet")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct PinPointGuideWidgetView: View {
    let entry: PinPointWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "location.north.line.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.orange)

                Spacer()

                Text("Guide")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let quickSpot = entry.quickSpot {
                Text("Guide Me")
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                HStack(spacing: 6) {
                    WidgetSpotIcon(iconEmoji: quickSpot.iconEmoji)
                    Text(quickSpot.name)
                        .font(.subheadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Text("Saved \(relativeTimestampText(for: quickSpot.timestamp))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            } else {
                Text("No Quick Spot")
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text("Save a quick spot in PinPoint first, then this widget will take you back to it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.9)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(entry.quickSpot == nil ? 0.72 : 1)
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
