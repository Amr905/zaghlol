import SwiftUI
import WidgetKit

/// T-118 / W-01 (FR-WID-01): safe-to-spend and days to payday. The widget only
/// draws the redacted strings the app stored in the App Group
/// (`WidgetSnapshotStore`); it computes nothing, never talks to the network and
/// logs nothing. Without a readable snapshot it shows only the app name. Tap
/// opens `zaghlol://home` (the app routes it through the lock screen when
/// locked). The text follows the system layout direction (RTL-first).
struct SnapshotEntry: TimelineEntry {
  let date: Date
  let view: WidgetView?
}

struct SnapshotProvider: TimelineProvider {
  private func current() -> SnapshotEntry {
    SnapshotEntry(date: Date(), view: WidgetSnapshotStore.production()?.readOrNil())
  }

  /// The gallery placeholder carries no amount (the mask only).
  func placeholder(in context: Context) -> SnapshotEntry {
    SnapshotEntry(
      date: Date(),
      view: WidgetView(
        state: WidgetView.stateOk, primaryText: "•••", secondaryText: "", currency: "",
        updatedAtMs: 0, daysToPayday: nil))
  }

  func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
    completion(context.isPreview ? placeholder(in: context) : current())
  }

  /// One entry, never refreshed by the widget itself: the app reloads the
  /// timeline (`WidgetCenter.reloadAllTimelines`) after each new snapshot.
  func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
    completion(Timeline(entries: [current()], policy: .never))
  }
}

private extension Color {
  static let widgetBackground = Color(
    UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.031, green: 0.075, blue: 0.059, alpha: 1)
      : UIColor(red: 0.953, green: 0.984, blue: 0.969, alpha: 1) })
  static let widgetInk = Color(
    UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.90, green: 0.96, blue: 0.93, alpha: 1)
      : UIColor(red: 0.059, green: 0.165, blue: 0.125, alpha: 1) })
  static let widgetMuted = Color(
    UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.62, green: 0.72, blue: 0.67, alpha: 1)
      : UIColor(red: 0.302, green: 0.412, blue: 0.361, alpha: 1) })
}

struct ZaghlolWidgetView: View {
  let entry: SnapshotEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      if let v = entry.view {
        Text(v.primaryText)
          .font(.headline.weight(.bold))
          .foregroundColor(.widgetInk)
          .minimumScaleFactor(0.6)
          .lineLimit(2)
          .privacySensitive()
        if !v.secondaryText.isEmpty {
          Text(v.secondaryText)
            .font(.caption)
            .foregroundColor(.widgetMuted)
            .lineLimit(2)
        }
      } else {
        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "")
          .font(.headline.weight(.bold))
          .foregroundColor(.widgetInk)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .widgetURL(URL(string: "zaghlol://home"))
    .containerBackground(for: .widget) { Color.widgetBackground }
  }
}

struct SafeToSpendWidget: Widget {
  let kind = "app.zaghlol.widget.safeToSpend"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
      ZaghlolWidgetView(entry: entry)
    }
    .configurationDisplayName("widget_safeToSpend_name")
    .description("widget_safeToSpend_description")
    .supportedFamilies([.systemSmall])
  }
}

@main
struct ZaghlolWidgetBundle: WidgetBundle {
  var body: some Widget {
    SafeToSpendWidget()
  }
}
