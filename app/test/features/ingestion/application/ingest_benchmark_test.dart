// T-046 §13 host benchmark: 500 messages in 25 batches of 20 into an
// encrypted database already holding 20k transactions, in ≤ 10 s. Tagged
// `benchmark` (excluded from app-ci's default run, like the T-007/T-050
// benchmarks). Device numbers: T-173. Synthetic data; output is numbers only.
@Tags(['benchmark'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';

import '../../../core/db/financial_fixtures.dart' as fx;
import '../support/ingest_harness.dart';

void main() {
  test('500 messages over 20k transactions in ≤ 10 s', () async {
    final w = await IngestWorld.open();
    addTearDown(w.close);
    await AccountsDao(w.db).insert(fx.account('seed', institution: 'zbank'));
    await w.db.transaction(() async {
      for (var i = 0; i < 20000; i++) {
        await w.db
            .into(w.db.transactions)
            .insert(
              fx
                  .txn(
                    'seed$i',
                    accountId: 'seed',
                    amountMinor: 100 + i,
                    merchant: 'Seed shop',
                    occurredAt: t0 - 365 * 86400000 + i * 60000,
                  )
                  .copyWith(),
            );
      }
    });
    final useCase = w.useCase();
    final watch = Stopwatch()..start();
    for (var b = 0; b < 25; b++) {
      await useCase([
        for (var i = 0; i < 20; i++)
          (i.isEven
              ? sms(
                  'm$b-$i',
                  'ZBANK: Purchase EGP ${b * 20 + i + 1}.00 at Synth Shop '
                      'card *4321',
                  rx: t0 + (b * 20 + i) * 600000,
                )
              : notif(
                  'm$b-$i',
                  'Purchase EGP ${b * 20 + i}.00 at Synth Shop',
                  rx: t0 + (b * 20 + i - 1) * 600000 + 1000,
                )),
      ]);
    }
    watch.stop();
    // ignore: avoid_print
    print('ingest 500 msgs: ${watch.elapsedMilliseconds} ms');
    expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
    expect(await w.count('raw_messages'), 500);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
