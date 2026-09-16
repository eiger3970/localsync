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

struct LocalSyncWidgetView: View {
  var body: some View {
    HStack(spacing: 12) {
      Link(destination: URL(string: "localsync://pull")!) {
        VStack(spacing: 6) {
          Image("QuickActionPull")
            .resizable()
            .scaledToFit()
            .frame(width: 32, height: 32)
          Text("Pull")
            .font(.caption)
            .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      Divider()
      Link(destination: URL(string: "localsync://push")!) {
        VStack(spacing: 6) {
          Image("QuickActionPush")
            .resizable()
            .scaledToFit()
            .frame(width: 32, height: 32)
          Text("Push")
            .font(.caption)
            .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .padding()
    .containerBackground(.fill.tertiary, for: .widget)
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
    .supportedFamilies([.systemMedium])
  }
}

@main
struct LocalSyncWidgetBundle: WidgetBundle {
  var body: some Widget {
    LocalSyncWidget()
  }
}
