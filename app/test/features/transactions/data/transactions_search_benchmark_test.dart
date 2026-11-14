// T-050 AC1: repository search < 200 ms on 50k rows (FR-TXN-01), through the
// repository on an encrypted database in drift's background isolate (the
// app's executor). Tagged `benchmark` like the T-007 benchmark: excluded
// from app-ci's non-benchmark run. Median of 3 passes after a warm-up;
// synthetic data; the output carries numbers only.
@Tags(['benchmark'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/features/transactions/data/drift_transaction_repository.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';

import '../../../core/db/financial_fixtures.dart';

void main() {
  test('AC1: search p95 < 200 ms on 50k rows', () async {
    final edb = await EncryptedDb.open();
    addTearDown(edb.close);
    await AccountsDao(edb.db).insert(account('acc1'));
    const names = [
      'كارفور المعادي',
      'Cafe Zamalek',
      'صيدلية العزبي',
      'Market Nile',
      'مطعم الشروق',
      'Pharmacy Dokki',
      'سوبر ماركت الهرم',
      'Bakery Giza',
    ];
    await edb.db.transaction(() async {
      for (var chunk = 0; chunk < 50; chunk++) {
        await edb.db.batch((b) {
          for (var i = chunk * 1000; i < (chunk + 1) * 1000; i++) {
            b.customStatement(
              'INSERT INTO transactions (id, account_id, source, direction, '
              'amount_minor, currency, occurred_at, occurred_tz_offset_min, '
              'merchant_raw, category_source, note, created_at, updated_at) '
              "VALUES (?, 'acc1', 'sms', 'expense', ?, 'EGP', ?, 120, ?, "
              "'none', ?, $t0, $t0)",
              [
                't$i',
                100 + (i * 7919) % 5000000,
                t0 - i * 60000,
                '${names[i % names.length]} $i',
                i % 5 == 0 ? 'dinner' : null,
              ],
            );
          }
        });
      }
    });
    final n = await edb.db
        .customSelect('SELECT count(*) AS c FROM transactions')
        .getSingle();
    expect(n.read<int>('c'), 50000);

    final repo = DriftTransactionRepository(TransactionsDao(edb.db));
    const terms = [
      'كارفور',
      'Zamalek',
      'صيدلية',
      'Market',
      'dinner',
      '1250',
      '٢٥٠',
      'ca',
      'كا',
      '50',
      'Nile 4',
      'Pharm',
    ];
    final micros = <int>[];
    for (var pass = 0; pass < 4; pass++) {
      for (final t in terms) {
        final sw = Stopwatch()..start();
        await repo.query(text: t, page: const PageRequest(limit: 50));
        sw.stop();
        if (pass > 0) micros.add(sw.elapsedMicroseconds);
      }
    }
    micros.sort();
    final p95 = micros[(micros.length * 0.95).ceil() - 1] / 1000;
    final max = micros.last / 1000;
    // ignore: avoid_print
    print('ZAGHLOL_TXN_SEARCH_BENCH rows=50000 p95_ms=$p95 max_ms=$max');
    // FU-214: ~2x the first perf run (58 ms); the FR-TXN-01 gate is 200 ms.
    expect(p95, lessThan(120));
    // Filtered list without text also stays fast.
    final sw = Stopwatch()..start();
    await repo.query(
      filter: const TransactionFilter(directions: {TxnDirection.expense}),
    );
    expect(sw.elapsedMilliseconds, lessThan(200));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
