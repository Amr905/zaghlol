// FU-155a: a save whose insert throws leaves the old rows untouched.

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/daos/budgets_dao.dart';
import 'package:zaghlol/features/budget/presentation/budget_edit_draft.dart';
import 'package:zaghlol/features/budget/presentation/budget_saver.dart';
import 'package:zaghlol/features/transactions/data/transactions_providers.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

void main() {
  test('insert that throws rolls back the update and delete', () async {
    final db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
    addTearDown(db.close);
    final egp = Currency.of('EGP');
    final dao = BudgetsDao(db);
    await dao.insert(
      id: 'tot',
      limit: Money(egp, 1000),
      period: BudgetPeriod.cycle,
      createdAt: 0,
    );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => db),
        // Collides with the surviving 'tot' row: the insert must throw.
        idGeneratorProvider.overrideWithValue(() => 'tot'),
      ],
    );
    addTearDown(container.dispose);
    final save = await container.read(budgetSaverProvider.future);
    await expectLater(
      save(
        egp,
        BudgetValidated(
          total: Money(egp, 2000),
          limits: {'any-cat': Money(egp, 500)},
          thresholds: const [80, 100],
        ),
        false,
      ),
      throwsA(anything),
    );
    final rows = await dao.inCurrency(egp);
    expect(rows.map((r) => r.id), ['tot']);
    expect(rows.single.limitMinor, 1000);
  });
}
