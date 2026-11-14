// Pigeon contract: home-screen widget snapshot (T-118, FR-WID-01). Contract:
// docs/03-technical/platform-channels.md section 5 (WidgetBridgeHostApi, with
// the T-118 contract note). Regenerate with app/tool/generate_pigeon.sh; CI
// fails when the generated files are stale.
//
// Rules for the native side (both platforms): store only what is passed (the
// strings are already formatted, locale-aware and redaction-aware by Dart;
// when amounts are hidden Dart sends the mask and never the amount); keep it
// encrypted with the spool key in a directory excluded from backups; never
// log it; no parsing or financial logic.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/widget_bridge_api.g.dart',
    dartPackageName: 'zaghlol',
    kotlinOut: 'android/app/src/main/kotlin/app/zaghlol/platform/widget/WidgetBridgeApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'app.zaghlol.platform.widget',
      errorClassName: 'WidgetBridgeApiError',
    ),
    swiftOut: 'ios/Runner/Platform/WidgetBridgeApi.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'WidgetBridgeApiError'),
  ),
)
/// What the widget shows (UX screen 80, W-01).
enum WidgetDisplayState {
  /// Safe-to-spend and days to payday (amount possibly masked).
  ok,

  /// No budget: "Set a budget".
  noBudget,

  /// Nothing to show yet: "Open Zaghlol".
  noData,
}

class WidgetSnapshot {
  WidgetSnapshot({
    required this.state,
    required this.primaryText,
    required this.secondaryText,
    required this.currency,
    required this.updatedAtMs,
    this.daysToPayday,
  });

  WidgetDisplayState state;

  /// Formatted line one, e.g. "314.28 EGP/day", "•••/day" (hidden or locked
  /// app: no amount is ever sent), "Set a budget" or "Open Zaghlol".
  String primaryText;

  /// Formatted line two, e.g. "7 days to payday"; empty when not applicable.
  String secondaryText;

  /// ISO 4217 code of the primary currency (never a sum across currencies).
  String currency;

  /// Epoch ms, the phone's clock, when Dart built this snapshot.
  int updatedAtMs;

  int? daysToPayday;
}

@HostApi()
abstract class WidgetBridgeHostApi {
  /// Stores the snapshot (encrypted, excluded from backups) and asks the
  /// widgets to redraw. Errors: `IO_ERROR`, `NOT_AVAILABLE` (code only).
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  void updateSnapshot(WidgetSnapshot snapshot);

  /// Deletes the stored snapshot and redraws the widgets as "Open Zaghlol"
  /// ("Delete everything", sign-out of financial data). Idempotent.
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  void clear();
}
