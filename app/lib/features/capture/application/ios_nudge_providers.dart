// T-066 (EC-14): what the Home / Settings nudge shows. It appears when the
// iOS setup checker says "silent" and the user has not snoozed it; a snooze
// hides it for 7 days (then it comes back if it is still silent).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_providers.dart';
import '../../transactions/data/transactions_providers.dart' show clockProvider;
import 'ios_setup_providers.dart';

/// Days a dismissed nudge stays hidden.
const int kIosNudgeSnoozeDays = 7;

final iosNudgeSnoozedUntilProvider = settingProvider(
  Settings.iosNudgeSnoozedUntil,
);

/// Days of silence to show; null: no nudge (not iOS, not silent, snoozed).
final iosNudgeDaysProvider = Provider<int?>((ref) {
  final status = ref.watch(iosSetupStatusProvider);
  if (!status.shouldNudge) return null;
  final until = ref.watch(iosNudgeSnoozedUntilProvider).value;
  final nowMs = ref.watch(clockProvider)().toUtc().millisecondsSinceEpoch;
  if (until != null && nowMs < until) return null;
  return status.silentDays;
}, name: 'iosNudgeDaysProvider');

/// Hides the nudge for [kIosNudgeSnoozeDays] days from now.
Future<void> snoozeIosNudge(WidgetRef ref) async {
  final repo = await ref.read(settingsRepositoryProvider.future);
  final now = ref.read(clockProvider)().toUtc();
  await repo.set(
    Settings.iosNudgeSnoozedUntil,
    now.add(const Duration(days: kIosNudgeSnoozeDays)).millisecondsSinceEpoch,
  );
}
