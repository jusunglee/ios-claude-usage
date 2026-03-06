import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct UsageEntry: TimelineEntry {
    let date: Date
    let usage: UsageData?
    let error: String?

    static let placeholder = UsageEntry(date: .now, usage: .placeholder, error: nil)
}

// MARK: - Timeline Provider

struct UsageTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        if let cached = UsageService.cachedUsage() {
            completion(UsageEntry(date: .now, usage: cached, error: nil))
        } else {
            completion(.placeholder)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
            do {
                let usage = try await UsageService.fetchUsage()
                let entry = UsageEntry(date: .now, usage: usage, error: nil)
                completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
            } catch {
                let cached = UsageService.cachedUsage()
                let entry = UsageEntry(date: .now, usage: cached, error: cached == nil ? error.localizedDescription : nil)
                completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
            }
        }
    }
}

// MARK: - Widget Views

struct SmallWidgetView: View {
    let entry: UsageEntry

    var body: some View {
        if let usage = entry.usage {
            VStack(spacing: 8) {
                HStack(spacing: 16) {
                    UsageRing(label: "Session", percent: usage.sessionWindow.utilizationPercent)
                    UsageRing(label: "Weekly", percent: usage.weeklyUsage.utilizationPercent)
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            VStack(spacing: 4) {
                Image(systemName: "key.fill")
                    .foregroundStyle(.secondary)
                Text("Open app to set up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

struct MediumWidgetView: View {
    let entry: UsageEntry

    var body: some View {
        if let usage = entry.usage {
            HStack(spacing: 16) {
                UsageRing(label: "Session", percent: usage.sessionWindow.utilizationPercent, showReset: usage.sessionWindow.timeUntilReset)
                UsageRing(label: "Weekly", percent: usage.weeklyUsage.utilizationPercent, showReset: usage.weeklyUsage.timeUntilReset)
                if let opus = usage.opusWeekly {
                    UsageRing(label: "Opus", percent: opus.utilizationPercent, showReset: opus.timeUntilReset)
                }
            }
            .frame(maxWidth: .infinity)
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            VStack(spacing: 4) {
                Image(systemName: "key.fill")
                    .foregroundStyle(.secondary)
                Text("Open app to configure session key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

// MARK: - Shared Components

struct UsageRing: View {
    let label: String
    let percent: Double
    var showReset: String? = nil

    private var color: Color {
        switch percent {
        case ..<50: return .green
        case ..<80: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: percent / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(percent))%")
                    .font(.system(.caption, design: .rounded, weight: .bold))
            }
            .frame(width: 50, height: 50)

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            if let showReset {
                Text(showReset)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Entry View Router

struct WidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: UsageEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        default:
            MediumWidgetView(entry: entry)
        }
    }
}

// MARK: - Widget Definition

struct ClaudeUsageWidget: Widget {
    let kind = "ClaudeUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageTimelineProvider()) { entry in
            WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Claude Usage")
        .description("Track your Claude usage limits.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct ClaudeUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClaudeUsageWidget()
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    ClaudeUsageWidget()
} timeline: {
    UsageEntry.placeholder
}

#Preview("Medium", as: .systemMedium) {
    ClaudeUsageWidget()
} timeline: {
    UsageEntry.placeholder
}
