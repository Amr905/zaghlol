import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/features/onboarding/application/contextual.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

SetupContext ctx({
  CivilDate? today,
  CivilDate? installed,
  bool payday = false,
  bool budgets = false,
  bool backup = false,
  CivilDate? salary,
  CivilDate? cycleEnd,
}) => SetupContext(
  today: today ?? CivilDate(2026, 11, 3),
  installedOn: installed ?? CivilDate(2026, 11, 1),
  paydayConfigured: payday,
  hasBudgets: budgets,
  backupExists: backup,
  latestSalaryCredit: salary,
  firstCycleEnd: cycleEnd,
);

void main() {
  test('AC: salary on day 25 suggests payday 25 (once)', () {
    final s = nextSetupSuggestion(ctx(salary: CivilDate(2026, 10, 25)));
    expect(s, const SetupSuggestion(SetupSuggestionKind.payday, paydayDay: 25));
    expect(s!.kind.messageKey, 'suggestPayday');
    expect(
      nextSetupSuggestion(
        ctx(salary: CivilDate(2026, 10, 25)),
        handled: {'payday'},
      ),
      isNull,
    );
  });

  test('salary on 29-31 proposes 28; none when payday already set', () {
    expect(
      nextSetupSuggestion(ctx(salary: CivilDate(2026, 10, 31)))!.paydayDay,
      28,
    );
    expect(
      nextSetupSuggestion(ctx(payday: true, salary: CivilDate(2026, 10, 25))),
      isNull,
    );
    expect(nextSetupSuggestion(ctx()), isNull);
  });

  test('budget suggestion only after the first cycle ended, no budgets', () {
    final end = CivilDate(2026, 11, 24);
    expect(
      nextSetupSuggestion(ctx(today: end, cycleEnd: end, backup: true)),
      isNull,
      reason: 'cycle still running on its last day',
    );
    final after = nextSetupSuggestion(
      ctx(today: end.plusDays(1), cycleEnd: end, backup: true),
    );
    expect(after?.kind, SetupSuggestionKind.budget);
    expect(
      nextSetupSuggestion(
        ctx(today: end.plusDays(1), cycleEnd: end, budgets: true, backup: true),
      ),
      isNull,
    );
  });

  test('backup suggestion on day 7, not 6, not when a backup exists', () {
    final i = CivilDate(2026, 11, 1);
    expect(
      nextSetupSuggestion(ctx(installed: i, today: i.plusDays(6))),
      isNull,
    );
    expect(
      nextSetupSuggestion(ctx(installed: i, today: i.plusDays(7)))?.kind,
      SetupSuggestionKind.backup,
    );
    expect(
      nextSetupSuggestion(
        ctx(installed: i, today: i.plusDays(30), backup: true),
      ),
      isNull,
    );
  });

  test('payday takes priority over backup; one at a time', () {
    final c = ctx(
      installed: CivilDate(2026, 10, 1),
      today: CivilDate(2026, 11, 1),
      salary: CivilDate(2026, 10, 25),
    );
    expect(nextSetupSuggestion(c)?.kind, SetupSuggestionKind.payday);
    expect(
      nextSetupSuggestion(c, handled: {'payday'})?.kind,
      SetupSuggestionKind.backup,
    );
  });

  group('store', () {
    late EncryptedDb edb;
    setUp(() async => edb = await EncryptedDb.open());
    tearDown(() => edb.close());

    test('handled persists and hides the suggestion forever', () async {
      final repo = SettingsRepository(SettingsDao(edb.db));
      final store = SetupSuggestionStore(repo);
      final c = ctx(salary: CivilDate(2026, 10, 25));
      expect((await store.next(c))?.kind, SetupSuggestionKind.payday);
      await store.markHandled(SetupSuggestionKind.payday);
      expect(await store.next(c), isNull);
      final again = SetupSuggestionStore(
        SettingsRepository(SettingsDao(edb.db)),
      );
      expect(await again.next(c), isNull);
    });
  });
}
