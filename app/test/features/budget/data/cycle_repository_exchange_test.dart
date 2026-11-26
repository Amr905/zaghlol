// T-272: exchange figures of a cycle, live and from the cache (the cache has
// no column for them; they are overlaid from the exchange legs). Synthetic.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/features/budget/data/cycle_repository.dart';
import 'package:zaghlol/features/ingestion/data/device_local_zone.dart';
import 'package:zaghlol/features/transactions/application/transfer_pairing.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  final egp = Currency.of('EGP');
  final usd = Currency.of('USD');
  final october = Cycle(
    start: CivilDate(2026, 10, 1),
    end: CivilDate(2026, 10, 31),
  );

  setUp(() async {
    edb = await EncryptedDb.open(background: false);
    db = edb.db;
    await db.into(db.accounts).insert(account('egp'));
    await db
        .into(db.accounts)
        .insert(account('usd', last4: '9945', currency: 'USD'));
    await TransferPairingUseCase(
      db,
      loadSchedule: () async => PaydaySchedule.single(1),
    ).recordExchange(
      fromAccountId: 'usd',
      sent: Money(usd, 60000),
      toAccountId: 'egp',
      received: Money(egp, 2970000),
      occurredAt: DateTime.utc(2026, 10, 26, 10),
      tzOffsetMin: 120,
    );
  });
  tearDown(() => edb.close());

  test(
    'a closed cycle read from the cache still carries the exchange',
    () async {
      final repo = CycleRepository(
        db,
        nowUtcMs: () => DateTime.utc(2026, 11, 26).millisecondsSinceEpoch,
        zone: const FixedLocalZone(120),
      );
      for (var run = 0; run < 2; run++) {
        // run 0 computes and caches; run 1 reads the cache.
        final t = await repo.totals(october);
        expect(t[egp]!.exchangedIn, Money(egp, 2970000), reason: 'run $run');
        expect(t[egp]!.income, Money.zero(egp));
        expect(t[usd]!.exchangedOut, Money(usd, 60000), reason: 'run $run');
        expect(t[usd]!.spend, Money.zero(usd));
      }
      expect(
        (await repo.cachedTotals(october))![egp]!.exchangedIn,
        Money.zero(egp),
        reason: 'the cache itself has no exchange figures',
      );
    },
  );
}
