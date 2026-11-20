// T-195: the salary hook is wired into the real ingest, so a salary SMS read
// by the pipeline is tied to the expected or hand-entered salary and the
// income is counted once. Synthetic messages only.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/features/ingestion/data/device_local_zone.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_types.dart';
import 'package:zaghlol/features/salary/application/salary_service.dart';
import 'package:zaghlol/features/transactions/data/drift_transaction_repository.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart' show account;
import '../../ingestion/support/ingest_harness.dart';

void main() {
  late IngestWorld w;
  late SalaryService service;
  late SettingsRepository settings;
  final today = CivilDate.fromLocalMs(t0 + 1000, zoneOffsetMin);

  Future<List<int>> liveIncome() async => [
    for (final r in await w.rows(
      'SELECT amount_minor FROM transactions WHERE deleted_at IS NULL AND '
      "direction = 'income' AND currency = 'EGP'",
    ))
      r['amount_minor']! as int,
  ];

  setUp(() async {
    w = await IngestWorld.open();
    await AccountsDao(w.db).insert(account('own', last4: '9999'));
    service = SalaryService(
      w.db,
      DriftTransactionRepository(TransactionsDao(w.db), newId: w.newId),
      zone: const FixedLocalZone(zoneOffsetMin),
    );
    settings = SettingsRepository(SettingsDao(w.db));
  });
  tearDown(() => w.close());

  NewTransaction manualSalary() => NewTransaction(
    accountId: 'own',
    direction: TxnDirection.income,
    amount: Money(Currency.of('EGP'), 1500000),
    occurredAt: DateTime.fromMillisecondsSinceEpoch(t0, isUtc: true),
    occurredTzOffsetMin: zoneOffsetMin,
  );

  test(
    'manual salary first, then the salary SMS: one income, the SMS one',
    () async {
      final r = await service.recordManual(manualSalary());
      final manualId = (r as SalaryRecorded).txnId;
      expect(await liveIncome(), [1500000]);
      final out = await w.run([
        sms('m', 'ZBANK: Salary EGP 15000.00 acct *5555'),
      ]);
      expect(out.outcomes['m'], isA<IngestInserted>());
      expect(await liveIncome(), [1500000]);
      final rows = await w.rows(
        'SELECT id, source, deleted_at FROM transactions ORDER BY source',
      );
      expect(rows.length, 2);
      final manual = rows.singleWhere((r) => r['id'] == manualId);
      expect(manual['deleted_at'], isNotNull);
      final received = rows.singleWhere((r) => r['id'] != manualId);
      expect(received['source'], 'sms');
      expect(received['deleted_at'], isNull);
      final state = await settings.get(Settings.salaryState);
      expect(state.entryOf(received['id']! as String)?.mergedTxnId, manualId);
    },
  );

  test('expected salary (plan only), then the SMS: tied, expected item is '
      'closed, nothing added', () async {
    await service.setPlan(
      SalaryPlan.tryCreate(
        amount: Money(Currency.of('EGP'), 1500000),
        day: today.day > 28 ? 28 : today.day,
      ),
    );
    expect((await service.expected(today))?.amount.minor, 1500000);
    await w.run([sms('m', 'ZBANK: Salary EGP 15000.00 acct *5555')]);
    expect(await liveIncome(), [1500000]);
    expect(await service.expected(today), isNull);
    final state = await settings.get(Settings.salaryState);
    expect(state.entries.single.captured, isTrue);
  });

  test(
    'salary SMS first, then a manual entry: asks instead of adding',
    () async {
      await service.setPlan(
        SalaryPlan.tryCreate(
          amount: Money(Currency.of('EGP'), 1500000),
          day: today.day > 28 ? 28 : today.day,
        ),
      );
      await w.run([sms('m', 'ZBANK: Salary EGP 15000.00 acct *5555')]);
      final r = await service.recordManual(manualSalary());
      expect(r, isA<SalaryFoundExisting>());
      expect(await liveIncome(), [1500000]);
    },
  );

  test('a salary SMS with no plan and no manual entry is a plain income, '
      'untouched', () async {
    await w.run([sms('m', 'ZBANK: Salary EGP 15000.00 acct *5555')]);
    expect(await liveIncome(), [1500000]);
    expect((await settings.get(Settings.salaryState)).entries, isEmpty);
  });
}
