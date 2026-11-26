// T-282 (D-86): Home "left", Insights "saved" and Ask "net" agree on the same
// month, per currency, when money was exchanged; the cash-flow chart keeps the
// exchange in its own series; Ask answers "how much did I exchange".
// PO story: USD salary 1,000, EGP food 500, USD 600 exchanged to EGP 29,700.
// Synthetic data only.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/features/ask/application/ask_engine.dart';
import 'package:zaghlol/features/ask/data/ask_entities_source.dart';
import 'package:zaghlol/features/ask/domain/ask_models.dart';
import 'package:zaghlol/features/budget/data/cycle_repository.dart';
import 'package:zaghlol/features/ingestion/data/device_local_zone.dart';
import 'package:zaghlol/features/insights/data/chart_repository.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/domain/chart_summary.dart';
import 'package:zaghlol/features/transactions/application/transfer_pairing.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/db/financial_fixtures.dart';

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late ChartRepository charts;
  final egp = Currency.of('EGP');
  final usd = Currency.of('USD');
  final november = Cycle(
    start: CivilDate(2026, 11, 1),
    end: CivilDate(2026, 11, 30),
  );
  int at(int d) => DateTime.utc(2026, 11, d, 10).millisecondsSinceEpoch;

  AskEngine engine() => AskEngine(
    charts: charts,
    accounts: () async => const [],
    cycleBudgets: () async => const {},
    schedule: () async => PaydaySchedule.single(1),
    entities: () async => AskEntities.none,
    today: () => CivilDate(2026, 11, 10),
  );

  setUp(() async {
    edb = await EncryptedDb.open(background: false);
    db = edb.db;
    charts = ChartRepository(db);
    await db.into(db.accounts).insert(account('egp'));
    await db
        .into(db.accounts)
        .insert(account('usd', last4: '9945', currency: 'USD'));
    Future<void> add(
      String id,
      String direction,
      int amount,
      String cur,
      String acc,
    ) => db
        .into(db.transactions)
        .insert(
          txn(
            id,
            accountId: acc,
            direction: direction,
            amountMinor: amount,
            currency: cur,
            occurredAt: at(3),
          ).copyWith(occurredTzOffsetMin: const Value(120)),
        );
    await add('salary', 'income', 100000, 'USD', 'usd');
    await add('food', 'expense', 50000, 'EGP', 'egp');
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

  test('Home left == Insights saved == Ask net, per currency', () async {
    final home = await CycleRepository(
      db,
      nowUtcMs: () => at(10),
      zone: const FixedLocalZone(120),
    ).totals(november);
    final period = ChartPeriod.cycle(november);
    final ask = await engine().ask('وفرت كام الشهر ده');
    expect(ask, isA<AskSavingsAnswer>());
    final askNet = {
      for (final f in (ask as AskSavingsAnswer).figures)
        f.income.currency: f.net,
    };
    for (final c in [egp, usd]) {
      final r = await charts.cashFlow([period], ChartFilter(currency: c));
      final saved = PeriodTotals.fromCashFlow(r, c).saved;
      expect(saved, home[c]!.left, reason: '${c.code} insights vs home');
      expect(askNet[c], home[c]!.left, reason: '${c.code} ask vs home');
    }
    expect(home[egp]!.left, Money(egp, 2920000));
    expect(home[usd]!.left, Money(usd, 40000));
  });

  test('cash flow: the exchange is only in its own series', () async {
    final period = ChartPeriod.cycle(november);
    final e = await charts.cashFlow([period], ChartFilter(currency: egp));
    final ep = (e as ChartReady<List<CashFlowPoint>>).data.single;
    expect(ep.income, Money.zero(egp));
    expect(ep.spend, Money(egp, 50000));
    expect(ep.exchangedIn, Money(egp, 2970000));
    expect(ep.exchangedOut, Money.zero(egp));
    final u = await charts.cashFlow([period], ChartFilter(currency: usd));
    final up = (u as ChartReady<List<CashFlowPoint>>).data.single;
    expect(up.income, Money(usd, 100000));
    expect(up.spend, Money.zero(usd));
    expect(up.exchangedOut, Money(usd, 60000));
    expect(up.exchangedIn, Money.zero(usd));
  });

  group('Ask: how much did I exchange', () {
    for (final q in [
      'غيّرت كام دولار الشهر ده؟',
      'How much did I exchange this month?',
    ]) {
      test(q, () async {
        final a = await engine().ask(q);
        expect(a, isA<AskExchangeAnswer>());
        final f = (a as AskExchangeAnswer).figures.single;
        expect(f.given, Money(usd, 60000));
        expect(f.received, Money(egp, 2970000));
        final r = f.rate!;
        expect(r.milli, 49500);
        expect(r.perUnitOf, usd);
        expect(r.quotedIn, egp);
      });
    }

    test('nothing exchanged: no-data answer, no numbers', () async {
      final a = await AskEngine(
        charts: charts,
        accounts: () async => const [],
        cycleBudgets: () async => const {},
        schedule: () async => PaydaySchedule.single(1),
        entities: () async => AskEntities.none,
        today: () => CivilDate(2026, 12, 10),
      ).ask('How much did I exchange this month?');
      expect(a, isA<AskNoDataAnswer>());
    });
  });
}
