// T-209: the repository queries behind the Overview tab, on an encrypted
// database with synthetic rows. Local zone is +02:00.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/features/insights/data/chart_repository.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

final egp = Currency.of('EGP');

int at(int y, int m, int d) => DateTime.utc(y, m, d, 10).millisecondsSinceEpoch;

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late ChartRepository repo;
  final f = ChartFilter(currency: egp);

  Future<void> spend(String id, int d, int amount, {String cur = 'EGP'}) => db
      .into(db.transactions)
      .insert(
        txn(
          id,
          accountId: 'acc1',
          direction: 'expense',
          amountMinor: amount,
          currency: cur,
          occurredAt: at(2026, 11, d),
        ).copyWith(occurredTzOffsetMin: const Value(120)),
      );

  Future<void> item(
    String id, {
    String kind = 'bill',
    String status = 'active',
    String currency = 'EGP',
    int amount = 10000,
    String cadence = 'monthly',
    String? next,
    int? total,
  }) => db
      .into(db.recurringItems)
      .insert(
        RecurringItemsCompanion.insert(
          id: id,
          kind: kind,
          status: status,
          name: 'Item $id',
          amountMinor: amount,
          currency: currency,
          cadence: cadence,
          nextDueDate: Value(next),
          totalCount: Value(total),
          createdAt: t0,
        ),
      );

  setUp(() async {
    edb = await EncryptedDb.open(background: false);
    db = edb.db;
    await db.into(db.accounts).insert(account('acc1', kind: 'debit'));
    repo = ChartRepository(db);
  });
  tearDown(() => edb.close());

  test('dailySpend: one entry per day, quiet days are zero', () async {
    await spend('a', 2, 500);
    await spend('b', 2, 250);
    await spend('c', 4, 100);
    await spend('usd', 3, 9999, cur: 'USD');
    final p = ChartPeriod(CivilDate(2026, 11, 1), CivilDate(2026, 11, 5));
    expect(await repo.dailySpend(p, f), [0, 750, 0, 100, 0]);
  });

  test('dailySpend of a period with no rows is all zeros', () async {
    final p = ChartPeriod(CivilDate(2026, 11, 1), CivilDate(2026, 11, 3));
    expect(await repo.dailySpend(p, f), [0, 0, 0]);
  });

  test('overallBudget is null without a budget', () async {
    expect(await repo.overallBudget(egp), isNull);
  });

  test(
    'upcomingDues: subscriptions, bills and instalments, one currency',
    () async {
      final today = CivilDate(2026, 11, 10);
      await item('bill', next: '2026-11-15');
      await item(
        'sub',
        kind: 'subscription',
        next: '2026-11-12',
        amount: 45000,
      );
      await item('inst', kind: 'installment', next: '2026-11-20', total: 2);
      await item('late', next: '2026-11-01'); // overdue: not listed this month
      await item('gbp', currency: 'GBP', next: '2026-11-11');
      await item('off', status: 'completed', next: '2026-11-11');
      await item('gameya', kind: 'gameya', next: '2026-11-11');
      final dues = await repo.upcomingDues(today, f);
      final firstOfEach = {
        for (final d in dues..sort((a, b) => a.date.compareTo(b.date)))
          d.itemId: d.date.toIso(),
      };
      expect(firstOfEach.keys.toSet(), {'bill', 'sub', 'inst', 'late'});
      expect(dues.every((d) => d.amount.currency == egp), isTrue);
      expect(dues.every((d) => d.date >= today), isTrue);
      // the instalment has 2 payments left: this month and next
      expect(dues.where((d) => d.itemId == 'inst').length, 2);
      // a monthly bill repeats; the overdue one is not reported as due
      expect(
        dues.where((d) => d.itemId == 'late').every((d) => d.date >= today),
        isTrue,
      );
    },
  );
}
