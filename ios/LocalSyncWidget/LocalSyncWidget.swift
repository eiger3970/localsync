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
//
// 2026-09-16 update: App Group feasibility confirmed on the current
// free/sideload signing identity (real device install succeeded with
// group.com.kworld.localsync wired into both targets). The Large
// layout's reserved space now holds a real backup-risk indicator,
// read directly from the shared UserDefaults suite -
// repository_provider.dart's _recordBackupTimestamp() (via
// AppDelegate.swift's BackupStatusChannel) is the only writer, this
// file only ever reads.

private let appGroupSuite = "group.com.kworld.localsync"
private let lastSyncKey = "lastSyncTimestamp"

// 2026-09-16: real feedback, live - "background looks default, rather
// than the LocalSync app icon background colours with a gradient."
// Sampled straight from assets/icon/icon.png (the real app icon, not
// the switchable in-app theme palettes - the icon itself is one fixed
// image): dark navy top fading to near-black bottom. Fixed dark
// background means every label/icon below needs an explicit light
// color instead of an adaptive system one - Divider()'s default tint
// assumes a light or system-material background and would be close to
// invisible here.
private let localSyncGradient = LinearGradient(
  colors: [
    Color(red: 14 / 255, green: 21 / 255, blue: 35 / 255),
    Color(red: 3 / 255, green: 5 / 255, blue: 12 / 255),
  ],
  startPoint: .top,
  endPoint: .bottom
)

// Divider()'s default tint is a system-adaptive gray built for an
// adaptive background - near-invisible on this fixed dark gradient.
private struct VDivider: View {
  var body: some View {
    Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1)
  }
}

private func daysSinceLastSync() -> Int? {
  // 2026-09-16: real bug, live - "still Never synced" even after the
  // missing reloadTimelines() fix. object(forKey:) as? Double relies on
  // NSNumber-to-Double bridging, which isn't always reliable - double(
  // forKey:) is Foundation's own typed accessor for exactly this and
  // doesn't go through that cast at all. 0 is being treated as "key
  // absent" (a real Unix timestamp near epoch will never occur here).
  let timestamp = UserDefaults(suiteName: appGroupSuite)?.double(forKey: lastSyncKey) ?? 0
  guard timestamp > 0 else { return nil }
  let elapsed = Date().timeIntervalSince1970 - timestamp
  return max(0, Int(elapsed / 86400))
}

struct LocalSyncEntry: TimelineEntry {
  let date: Date
  let daysSinceSync: Int?
}

struct LocalSyncProvider: TimelineProvider {
  func placeholder(in context: Context) -> LocalSyncEntry {
    LocalSyncEntry(date: Date(), daysSinceSync: 0)
  }

  func getSnapshot(in context: Context, completion: @escaping (LocalSyncEntry) -> Void) {
    completion(LocalSyncEntry(date: Date(), daysSinceSync: daysSinceLastSync()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<LocalSyncEntry>) -> Void) {
    // Risk grows day by day even with the app untouched, so unlike the
    // old .never policy this needs a real periodic refresh - every 6h
    // is often enough for a day-granularity indicator without wasting
    // the widget's limited refresh budget.
    let entry = LocalSyncEntry(date: Date(), daysSinceSync: daysSinceLastSync())
    let nextRefresh = Calendar.current.date(byAdding: .hour, value: 6, to: Date())!
    let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
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
          .foregroundStyle(.white)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

// 2026-09-16: agreed design - green <1 day, amber 2-6 days, red 7+
// days, growing more urgent the longer a device has gone without
// pushing/pulling. Gray/"Never synced" is its own state, not lumped
// into red - a fresh install with no sync yet isn't a backup risk in
// the same sense a device that's fallen behind is.
private func riskColor(_ days: Int?) -> Color {
  guard let days = days else { return .gray }
  if days < 1 { return .green }
  if days <= 6 { return .yellow }
  return .red
}

private func riskLabel(_ days: Int?) -> String {
  guard let days = days else { return "Never synced" }
  if days == 0 { return "Synced today" }
  if days == 1 { return "1 day ago" }
  return "\(days) days ago"
}

struct BackupRiskIndicator: View {
  let days: Int?

  var body: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(riskColor(days))
        .frame(width: 10, height: 10)
      Text(riskLabel(days))
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.75))
    }
  }
}

// 2026-09-16: real feedback, live - "regular icon as is, then the 3
// other larger sizes permit 3 different looks." Three real, distinct
// layouts (not one layout just scaled), all three now carrying the
// "LocalSync" title and the app icon's own dark gradient background
// (real feedback, live - "widgets 2 and 3 don't show LocalSync...
// background looks default"). Only Large gets the backup-risk
// indicator - no room for it at Small/Medium sizes.
struct LocalSyncWidgetView: View {
  @Environment(\.widgetFamily) var family
  let entry: LocalSyncEntry

  var body: some View {
    switch family {
    case .systemSmall:
      VStack(spacing: 4) {
        Text("LocalSync")
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(.white)
        HStack(spacing: 10) {
          SyncButton(imageName: "QuickActionPull", label: "Pull", url: "localsync://pull", iconSize: 22, font: .system(size: 9))
          VDivider()
          SyncButton(imageName: "QuickActionPush", label: "Push", url: "localsync://push", iconSize: 22, font: .system(size: 9))
        }
      }
      .padding(8)
      .containerBackground(localSyncGradient, for: .widget)
    case .systemLarge:
      VStack(spacing: 12) {
        Text("LocalSync")
          .font(.headline)
          .foregroundStyle(.white)
        BackupRiskIndicator(days: entry.daysSinceSync)
        HStack(spacing: 16) {
          SyncButton(imageName: "QuickActionPull", label: "Pull", url: "localsync://pull", iconSize: 44, font: .subheadline)
          VDivider()
          SyncButton(imageName: "QuickActionPush", label: "Push", url: "localsync://push", iconSize: 44, font: .subheadline)
        }
      }
      .padding()
      .containerBackground(localSyncGradient, for: .widget)
    default: // .systemMedium
      VStack(spacing: 6) {
        Text("LocalSync")
          .font(.caption)
          .fontWeight(.bold)
          .foregroundStyle(.white)
        HStack(spacing: 12) {
          SyncButton(imageName: "QuickActionPull", label: "Pull", url: "localsync://pull", iconSize: 30, font: .caption)
          VDivider()
          SyncButton(imageName: "QuickActionPush", label: "Push", url: "localsync://push", iconSize: 30, font: .caption)
        }
      }
      .padding()
      .containerBackground(localSyncGradient, for: .widget)
    }
  }
}

struct LocalSyncWidget: Widget {
  let kind: String = "LocalSyncWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: LocalSyncProvider()) { entry in
      LocalSyncWidgetView(entry: entry)
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
