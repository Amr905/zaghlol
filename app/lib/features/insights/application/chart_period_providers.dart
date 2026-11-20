// T-188 (FR-CHT-04, D-68): the chart period the user picked, remembered in
// the `settings` table (`charts.period`), and its resolution against today
// and the payday schedule. Every chart, the explainer, the currency list and
// the detail screen read [chartsResolvedPeriodProvider].

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/setting_key.dart';
import '../../../core/settings/settings_providers.dart';
import '../../budget/application/budget_providers.dart';
import '../domain/chart_period_selection.dart';

/// The stored selection. Unset or unreadable text is this cycle.
final SettingKey<ChartPeriodSelection> chartPeriodSetting =
    SettingKey.custom<ChartPeriodSelection>(
      'charts.period',
      byDefault: ChartPeriodSelection.thisCycle,
      decode: ChartPeriodSelection.tryDecode,
      encode: (v) => v.encode(),
    );

/// The user's selection. Read once from the settings; after that this
/// notifier is the source of truth for the session and writes through.
final chartPeriodSelectionProvider =
    AsyncNotifierProvider<ChartPeriodSelectionNotifier, ChartPeriodSelection>(
      ChartPeriodSelectionNotifier.new,
      name: 'chartPeriodSelectionProvider',
    );

class ChartPeriodSelectionNotifier extends AsyncNotifier<ChartPeriodSelection> {
  @override
  Future<ChartPeriodSelection> build() async {
    final repo = await ref.watch(settingsRepositoryProvider.future);
    return repo.get(chartPeriodSetting);
  }

  /// Applies [selection] at once and saves it. A failed save only means the
  /// choice does not survive a restart: it is a display preference, so the
  /// session keeps it and the charts never wait on the disk.
  Future<void> select(ChartPeriodSelection selection) async {
    state = AsyncData(selection);
    try {
      final repo = await ref.read(settingsRepositoryProvider.future);
      await repo.set(chartPeriodSetting, selection);
    } on Exception {
      // Deliberately not rethrown (see above); nothing sensitive to log.
    }
  }
}

/// The selection resolved on today's date under the payday schedule. A
/// relative preset follows the date (midnight, resume); a payday change
/// moves the cycles.
final chartsResolvedPeriodProvider = FutureProvider<ResolvedChartPeriod>((
  ref,
) async {
  final selection = await ref.watch(chartPeriodSelectionProvider.future);
  final schedule = await ref.watch(paydayScheduleProvider.future);
  return selection.resolveAll(ref.watch(todayProvider), schedule);
}, name: 'chartsResolvedPeriodProvider');
