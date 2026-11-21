// T-118 (FR-WID-01): keeps the home-screen widget in step with the app.
// [WidgetSnapshotPublisher] sends a snapshot through the platform channel
// only when its visible content changed; [widgetBridgeWiringProvider] watches
// the inputs (cycle overview, which a TransactionsChanged event recomputes;
// hide-amounts; app lock; language; primary currency) and publishes after a
// short debounce, so the widget follows a new transaction within seconds
// (AC: within a minute). Watch the wiring provider once from the app shell.
// Nothing here logs; platform errors are swallowed as codes (the widget
// then keeps its previous, already redacted snapshot).

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/platform/widget_bridge_api.g.dart';
import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_providers.dart';
import '../../budget/application/budget_providers.dart';
import '../../security/domain/app_lock_controller.dart';
import '../../transactions/data/transactions_providers.dart' show clockProvider;
import '../domain/widget_snapshot_builder.dart';

/// Debounce between an input change and the platform call.
const widgetPublishDebounce = Duration(seconds: 2);

final hideAmountsWidgetProvider = settingProvider(Settings.hideAmountsWidget);

final widgetBridgeHostProvider = Provider<WidgetBridgeHostApi>(
  (ref) => WidgetBridgeHostApi(),
  name: 'widgetBridgeHostProvider',
);

/// The localized copy for [languageCode] (`ar` or `en`), from the ARB strings
/// (`commonUnitPerDay`, `homeHeroDaysToPayday`, `homeHeroSetBudget`,
/// `widgetOpenZaghlol`). Tests may override it.
final widgetCopyProvider = Provider.family<WidgetCopy, String>((
  ref,
  languageCode,
) {
  final l = lookupAppLocalizations(ui.Locale(languageCode));
  return WidgetCopy(
    perDay: l.commonUnitPerDay,
    daysToPayday: l.homeHeroDaysToPayday,
    setBudget: l.homeHeroSetBudget,
    openApp: l.widgetOpenZaghlol,
  );
}, name: 'widgetCopyProvider');

/// True when the snapshot content (not its timestamp) is the same.
bool sameWidgetContent(WidgetSnapshot a, WidgetSnapshot b) =>
    a.state == b.state &&
    a.primaryText == b.primaryText &&
    a.secondaryText == b.secondaryText &&
    a.daysToPayday == b.daysToPayday &&
    _sameList(a.secondaryTextByDay, b.secondaryTextByDay) &&
    a.currency == b.currency;

bool _sameList(List<String>? a, List<String>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class WidgetSnapshotPublisher {
  WidgetSnapshotPublisher(this._host);

  final WidgetBridgeHostApi _host;
  WidgetSnapshot? _last;

  /// Sends [next] unless it shows the same as the last one that was
  /// delivered. Returns whether a platform call succeeded.
  Future<bool> publish(WidgetSnapshot next) async {
    final last = _last;
    if (last != null && sameWidgetContent(last, next)) return false;
    try {
      await _host.updateSnapshot(next);
      _last = next;
      return true;
    } on PlatformException {
      return false; // code only; the old snapshot stays.
    }
  }

  /// Removes the stored snapshot ("Delete everything").
  Future<void> clear() async {
    _last = null;
    try {
      await _host.clear();
    } on PlatformException {
      // Nothing to do; native clear is idempotent and retried next time.
    }
  }
}

final widgetSnapshotPublisherProvider = Provider<WidgetSnapshotPublisher>(
  (ref) => WidgetSnapshotPublisher(ref.watch(widgetBridgeHostProvider)),
  name: 'widgetSnapshotPublisherProvider',
);

String _languageFor(ui.Locale? pref) {
  final code = (pref ?? ui.PlatformDispatcher.instance.locale).languageCode;
  return supportedLanguageCodes.contains(code) ? code : 'en';
}

final widgetBridgeWiringProvider = Provider<void>((ref) {
  final overview = ref.watch(currentCycleOverviewProvider);
  // D-67: the app-wide eye toggle also hides the widget (OR); it reads as
  // hidden while it loads (fail closed).
  final hide =
      (ref.watch(hideAmountsWidgetProvider).value ?? false) ||
      ref.watch(hideAmountsProvider);
  // FU-206a: until the lock setting has loaded, keep the previous snapshot
  // (a cold start is locked; never publish amounts on a guess).
  final lockSetting = ref.watch(appLockEnabledProvider).value;
  if (lockSetting == null) return;
  final lockOn = lockSetting;
  final locked = ref.watch(appLockControllerProvider.select((s) => s.locked));
  // FU-206a: with the lock on, leaving the app masks the widget at once, not
  // only when the lock timeout later engages; resuming (unlocked) shows the
  // amount again.
  final away = ref.watch(appBackgroundedProvider);
  final maskForLock = lockOn && (locked || away);
  final primary = ref.watch(primaryCurrencyProvider).value;
  final lang = _languageFor(ref.watch(appLocaleProvider));
  final digits = ref.watch(digitsModeProvider(lang));
  if (primary == null) return;
  // While the overview loads, keep the previous snapshot (do not flash
  // "Open Zaghlol"); an error counts as "no data".
  if (overview.isLoading && !overview.hasValue) return;

  // Read here, not in the timer, so a missing override shows as a provider
  // error instead of an uncaught timer exception.
  final copy = ref.watch(widgetCopyProvider(lang));
  // FU-206a: the masked snapshot goes out at once when the app locks or goes
  // to the background with the lock on (the app may be suspended a moment later); other changes are debounced.
  final delay = maskForLock ? Duration.zero : widgetPublishDebounce;
  final timer = Timer(delay, () {
    final snapshot = buildWidgetSnapshot(
      WidgetSnapshotInput(
        overview: overview.value,
        primaryCurrency: primary,
        hideAmounts: hide,
        appLocked: maskForLock,
        languageCode: lang,
        digits: digits,
        copy: copy,
        nowMs: ref.read(clockProvider)().toUtc().millisecondsSinceEpoch,
      ),
    );
    unawaited(ref.read(widgetSnapshotPublisherProvider).publish(snapshot));
  });
  ref.onDispose(timer.cancel);
}, name: 'widgetBridgeWiringProvider');
