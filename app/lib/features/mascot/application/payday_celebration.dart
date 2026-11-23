// T-215: decides when Captain Zaghlol celebrates a payday (08-mascot-motion
// section 1: "salary detected, once per payday"). Pure logic here; the Home
// slot reads [paydayCelebrationProvider]. Nothing logs or shows an amount.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_providers.dart';
import '../../budget/application/budget_providers.dart' show todayProvider;
import '../../salary/application/salary_providers.dart';

/// A salary tied to a payday older than this many days is history (e.g. the
/// first import of old messages) and never celebrates.
const int kPaydayFreshDays = 3;

enum PaydayVerdict { celebrate, markSilently, nothing }

/// The newest captured (bank-message) salary anchor in [state], or null.
CivilDate? latestCapturedPayday(SalaryState state) {
  CivilDate? best;
  for (final e in state.entries) {
    if (!e.captured) continue;
    if (best == null || e.anchor > best) best = e.anchor;
  }
  return best;
}

/// [lastCelebrated] is the epoch day stored after the last celebration.
PaydayVerdict paydayVerdict({
  required CivilDate? latest,
  required int? lastCelebrated,
  required CivilDate today,
}) {
  if (latest == null) return PaydayVerdict.nothing;
  if (lastCelebrated != null && latest.epochDay <= lastCelebrated) {
    return PaydayVerdict.nothing;
  }
  return today.difference(latest) <= kPaydayFreshDays
      ? PaydayVerdict.celebrate
      : PaydayVerdict.markSilently;
}

/// Emits the payday to celebrate (once), after storing it as celebrated.
/// Old salaries are stored silently. Survives restarts: the mark is in the
/// encrypted settings.
final paydayCelebrationProvider = StreamProvider<CivilDate?>((ref) async* {
  final repo = await ref.watch(settingsRepositoryProvider.future);
  final state = ref.watch(salaryStateProvider).value;
  final today = ref.watch(todayProvider);
  if (state == null) {
    yield null;
    return;
  }
  final latest = latestCapturedPayday(state);
  final last = await repo.get(Settings.mascotPaydayCelebrated);
  final verdict = paydayVerdict(
    latest: latest,
    lastCelebrated: last,
    today: today,
  );
  if (verdict != PaydayVerdict.nothing) {
    await repo.set(Settings.mascotPaydayCelebrated, latest!.epochDay);
  }
  yield verdict == PaydayVerdict.celebrate ? latest : null;
});
