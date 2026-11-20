// T-188 AC4: the selection survives a restart; a corrupt stored value falls
// back to this cycle; a failed save keeps the choice for the session.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/features/budget/application/budget_providers.dart';
import 'package:zaghlol/features/insights/application/chart_period_providers.dart';
import 'package:zaghlol/features/insights/domain/chart_period_selection.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

class _Today extends TodayNotifier {
  @override
  CivilDate build() => CivilDate(2026, 11, 10);
}

void main() {
  late EncryptedDb edb;

  setUp(() async => edb = await EncryptedDb.open());
  tearDown(() => edb.close());

  ProviderContainer open() {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => edb.db),
        paydayScheduleProvider.overrideWith(
          (ref) async => PaydaySchedule.single(25),
        ),
        todayProvider.overrideWith(_Today.new),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('default is this cycle, resolved against payday and today', () async {
    final c = open();
    expect(
      await c.read(chartPeriodSelectionProvider.future),
      ChartPeriodSelection.thisCycle,
    );
    final r = await c.read(chartsResolvedPeriodProvider.future);
    expect(r.period.key, '2026-10-25..2026-11-24');
  });

  test('every preset and a custom range survive a restart', () async {
    final selections = [
      for (final p in ChartPreset.values)
        if (p != ChartPreset.custom) ChartPeriodSelection(p, offset: 1),
      ChartPeriodSelection.custom(
        CivilDate(2026, 2, 18),
        CivilDate(2026, 3, 19),
      ),
    ];
    for (final s in selections) {
      final first = open();
      await first.read(chartPeriodSelectionProvider.future);
      await first.read(chartPeriodSelectionProvider.notifier).select(s);
      // The same database, a new container: a restart.
      final second = open();
      expect(
        await second.read(chartPeriodSelectionProvider.future),
        s,
        reason: s.encode(),
      );
    }
  });

  test('select updates the resolved period at once', () async {
    final c = open();
    await c.read(chartPeriodSelectionProvider.future);
    final seen = <String>[];
    c.listen(chartsResolvedPeriodProvider, (_, next) {
      if (next.hasValue) seen.add(next.requireValue.period.key);
    }, fireImmediately: true);
    await c
        .read(chartPeriodSelectionProvider.notifier)
        .select(const ChartPeriodSelection(ChartPreset.last3Months));
    await pumpEventQueue();
    expect(seen.last, '2026-09-01..2026-11-10');
  });

  test('stored text that cannot be read is this cycle', () async {
    final dao = SettingsDao(edb.db);
    for (final bad in [
      'x',
      'thisCycle|99999||',
      'custom|0|2026-13-01|2026-12-01',
    ]) {
      await dao.write(chartPeriodSetting.name, bad, at: 1);
      final c = open();
      expect(
        await c.read(chartPeriodSelectionProvider.future),
        ChartPeriodSelection.thisCycle,
        reason: bad,
      );
    }
  });

  test('a failed save keeps the choice for the session', () async {
    final c = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWith(
          (ref) async => _Failing(SettingsDao(edb.db)),
        ),
      ],
    );
    addTearDown(c.dispose);
    await c.read(chartPeriodSelectionProvider.future);
    const s = ChartPeriodSelection(ChartPreset.thisYear);
    await c.read(chartPeriodSelectionProvider.notifier).select(s);
    expect(c.read(chartPeriodSelectionProvider).value, s);
  });

  test(
    'the key is a settings row like the others (no schema change)',
    () async {
      final repo = SettingsRepository(SettingsDao(edb.db));
      await repo.set(
        chartPeriodSetting,
        const ChartPeriodSelection(ChartPreset.lastMonth),
      );
      expect(await SettingsDao(edb.db).read('charts.period'), 'lastMonth|0||');
    },
  );
}

class _Failing extends SettingsRepository {
  _Failing(super.dao);
  @override
  Future<void> set<T>(key, T value) async => throw Exception('disk full');
}
