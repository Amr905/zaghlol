// T-195: the salary plan and state are ordinary settings rows, so a backup
// carries them (FR-BAK-06) and a restore reads them back. Bad stored text
// reads as empty, never as a thrown error. Synthetic data only.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/features/backup/application/backup_contents.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

void main() {
  test('plan and state survive encode/decode of the backup settings and read '
      'back typed; garbage reads as the default', () async {
    final edb = await EncryptedDb.open();
    addTearDown(edb.close);
    final dao = SettingsDao(edb.db);
    final repo = SettingsRepository(dao);
    final plan = SalaryPlan.tryCreate(
      amount: Money(Currency.of('EGP'), 1250000),
      day: 25,
      accountId: 'acc-1',
    )!;
    final state = SalaryState.empty
        .withEntry(
          SalaryEntry(
            txnId: 's1',
            captured: true,
            anchor: CivilDate(2026, 11, 25),
          ).withMerged('m1', Money(Currency.of('EGP'), 1250000)),
        )
        .withSkipped(CivilDate(2026, 10, 25));
    await repo.set(Settings.salaryPlan, plan);
    await repo.set(Settings.salaryState, state);

    final restored = decodeSettings(encodeSettings(await dao.all()));
    final target = await EncryptedDb.open();
    addTearDown(target.close);
    final dao2 = SettingsDao(target.db);
    for (final e in restored.entries) {
      await dao2.write(e.key, e.value, at: 1);
    }
    final repo2 = SettingsRepository(dao2);
    expect(await repo2.get(Settings.salaryPlan), plan);
    final back = await repo2.get(Settings.salaryState);
    expect(back, state);
    expect(back.entryOf('s1')?.mergedTxnId, 'm1');

    await dao2.write('salary.plan', '{broken', at: 2);
    await dao2.write('salary.state', 'x' * 100, at: 2);
    expect(await repo2.get(Settings.salaryPlan), isNull);
    expect(await repo2.get(Settings.salaryState), SalaryState.empty);
  });
}
