// FU-171b: saving an edit of an item deleted meanwhile must fail, not claim
// success. Synthetic data.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/recurring/data/recurring_repository.dart';
import 'package:zaghlol/features/recurring/presentation/bills_providers.dart';
import 'package:zaghlol/features/transactions/data/transactions_providers.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

void main() {
  test('save of a missing item throws RECURRING_NOT_FOUND', () async {
    final edb = await EncryptedDb.open();
    addTearDown(edb.close);
    final repo = RecurringRepository(
      edb.db,
      clock: () => DateTime.utc(2026, 11, 13, 12),
      newId: () => 'x',
    );
    final c = ProviderContainer(
      overrides: [
        recurringRepositoryProvider.overrideWith((ref) async => repo),
      ],
    );
    addTearDown(c.dispose);
    final draft = BillDraft(
      kind: RecurringKind.bill,
      name: 'Water',
      amount: Money(Currency.of('EGP'), 5000),
      cadence: RecurrenceCadence.monthly,
      nextDue: CivilDate(2026, 12, 5),
    );
    await expectLater(
      c.read(billsActionsProvider).save(draft, id: 'gone'),
      throwsA(
        isA<RecurringException>().having(
          (e) => e.code,
          'code',
          RecurringException.notFound,
        ),
      ),
    );
  });
}
