import WidgetKit
import SwiftUI

// 2026-09-16: real feedback, live - "the larger screen can simply
// show the push pull functionality, simple... not much this app needs
// to show really." Deliberately no live sync data (last-synced time,
// conflict count) - static, and no real content beyond two tappable
// actions per direct ask. Buttons are plain Link(destination:) URLs
// (localsync://push, localsync://pull), not an AppIntent - avoids
// needing an App Group entitlement (Developer Portal registration may
// not work on a free/sideload signing identity, the same real
// constraint already documented elsewhere in this app's history).
// Tapping opens the main app, which then runs the real push/pull
// through the exact same _runAndShow every other push/pull already
// goes through (see AppDelegate.swift's WidgetActionChannel and
// main.dart's own handling) - this widget never touches sync logic
// itself, it can't: WidgetKit extensions don't run the Flutter/Dart
// engine at all.

struct LocalSyncEntry: TimelineEntry {
  let date: Date
}

struct LocalSyncProvider: TimelineProvider {
  func placeholder(in context: Context) -> LocalSyncEntry {
    LocalSyncEntry(date: Date())
  }

  func getSnapshot(in context: Context, completion: @escaping (LocalSyncEntry) -> Void) {
    completion(LocalSyncEntry(date: Date()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<LocalSyncEntry>) -> Void) {
    // Static content, nothing to refresh - one entry, .never policy.
    let timeline = Timeline(entries: [LocalSyncEntry(date: Date())], policy: .never)
    completion(timeline)
  }
}

// 2026-09-16: one button, reused across all 3 sizes at different
// scales, instead of three near-duplicate button definitions.
struct SyncButton: View {
  let imageName: String
  let label: String
  let url: String
  let iconSize: CGFloat
  let font: Font

  var body: some View {
    Link(destination: URL(string: url)!) {
      VStack(spacing: 6) {
        Image(imageName)
          .resizable()
          .scaledToFit()
          .frame(width: iconSize, height: iconSize)
        Text(label)
          .font(font)
          .fontWeight(.semibold)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

// 2026-09-16: real feedback, live - "regular icon as is, then the 3
// other larger sizes permit 3 different looks." Three real, distinct
// layouts (not one layout just scaled) - Small has room for icons
// only, Medium (the original layout) fits icon+label side by side,
// Large adds real breathing room and a title. All three stay within
// this session's own scope decision: static buttons only, no live
// data - Large's extra space is reserved for the backup-risk
// indicator once the App Group question (real, still open) is solved,
// not filled with anything invented in the meantime.
struct LocalSyncWidgetView: View {
  @Environment(\.widgetFamily) var family

  var body: some View {
    switch family {
    case .systemSmall:
      VStack(spacing: 8) {
        SyncButton(imageName: "QuickActionPull", label: "Pull", url: "localsync://pull", iconSize: 26, font: .caption2)
        Divider()
        SyncButton(imageName: "QuickActionPush", label: "Push", url: "localsync://push", iconSize: 26, font: .caption2)
      }
      .padding(10)
      .containerBackground(.fill.tertiary, for: .widget)
    case .systemLarge:
      VStack(spacing: 16) {
        Text("LocalSync")
          .font(.headline)
        HStack(spacing: 16) {
          SyncButton(imageName: "QuickActionPull", label: "Pull", url: "localsync://pull", iconSize: 44, font: .subheadline)
          Divider()
          SyncButton(imageName: "QuickActionPush", label: "Push", url: "localsync://push", iconSize: 44, font: .subheadline)
        }
      }
      .padding()
      .containerBackground(.fill.tertiary, for: .widget)
    default: // .systemMedium
      HStack(spacing: 12) {
        SyncButton(imageName: "QuickActionPull", label: "Pull", url: "localsync://pull", iconSize: 32, font: .caption)
        Divider()
        SyncButton(imageName: "QuickActionPush", label: "Push", url: "localsync://push", iconSize: 32, font: .caption)
      }
      .padding()
      .containerBackground(.fill.tertiary, for: .widget)
    }
  }
}

struct LocalSyncWidget: Widget {
  let kind: String = "LocalSyncWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: LocalSyncProvider()) { _ in
      LocalSyncWidgetView()
    }
    .configurationDisplayName("LocalSync")
    .description("Push or pull without opening the app.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

@main
struct LocalSyncWidgetBundle: WidgetBundle {
  var body: some Widget {
    LocalSyncWidget()
  }
}
