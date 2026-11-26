// T-287 (FU-385): a currency whose only activity this month is an exchange out
// (USD salary last month, USD 600 exchanged this month) is in Ask savings, with
// the same "left" as Home. Synthetic data only.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/features/ask/application/ask_engine.dart';
import 'package:zaghlol/features/ask/domain/ask_models.dart';
import 'package:zaghlol/features/insights/data/chart_repository.dart';
import 'package:zaghlol/features/transactions/application/transfer_pairing.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/db/financial_fixtures.dart';

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  final egp = Currency.of('EGP');
  final usd = Currency.of('USD');

  setUp(() async {
    edb = await EncryptedDb.open(background: false);
    db = edb.db;
    await db.into(db.accounts).insert(account('egp'));
    await db
        .into(db.accounts)
        .insert(account('usd', last4: '9945', currency: 'USD'));
    await db
        .into(db.transactions)
        .insert(
          txn(
            'salary',
            accountId: 'usd',
            direction: 'income',
            amountMinor: 100000,
            currency: 'USD',
            occurredAt: DateTime.utc(2026, 10, 3, 10).millisecondsSinceEpoch,
          ).copyWith(occurredTzOffsetMin: const Value(120)),
        );
    await TransferPairingUseCase(
      db,
      loadSchedule: () async => PaydaySchedule.single(1),
    ).recordExchange(
      fromAccountId: 'usd',
      sent: Money(usd, 60000),
      toAccountId: 'egp',
      received: Money(egp, 2970000),
      occurredAt: DateTime.utc(2026, 11, 5, 10),
      tzOffsetMin: 120,
    );
  });
  tearDown(() => edb.close());

  test('USD left is -600 in Ask, like Home', () async {
    final a = await AskEngine(
      charts: ChartRepository(db),
      accounts: () async => const [],
      cycleBudgets: () async => const {},
      schedule: () async => PaydaySchedule.single(1),
      entities: () async => AskEntities.none,
      today: () => CivilDate(2026, 11, 10),
    ).ask('وفرت كام الشهر ده');
    final byCur = {
      for (final f in (a as AskSavingsAnswer).figures) f.income.currency: f.net,
    };
    expect(byCur[usd], Money(usd, -60000));
    expect(byCur[egp], Money(egp, 2970000));
  });
}
