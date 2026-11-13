// T-110: Ask Zaghlol end to end on an encrypted database: question text ->
// grammar -> query plan -> answer. Synthetic data only. Today is Tue
// 2026-11-10, payday 25, every row at +02:00.

import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/features/accounts/domain/account.dart';
import 'package:zaghlol/features/ask/application/ask_engine.dart';
import 'package:zaghlol/features/ask/data/ask_entities_source.dart';
import 'package:zaghlol/features/ask/domain/ask_models.dart';
import 'package:zaghlol/features/insights/data/chart_repository.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/db/financial_fixtures.dart';

final egp = Currency.of('EGP');
final gbp = Currency.of('GBP');

int at(int y, int m, int d, [int h = 10]) =>
    DateTime.utc(y, m, d, h).millisecondsSinceEpoch;

const entities = AskEntities(
  categories: [
    AskEntity('cw', ['اكل', 'food', 'مطاعم']),
    AskEntity('cn', ['مواصلات', 'transport']),
  ],
  merchants: [
    AskEntity('carrefour', ['Carrefour', 'كارفور'], partial: true),
    AskEntity('uber', ['Uber', 'اوبر'], partial: true),
  ],
  accounts: [
    AskEntity('acc1', ['CIB'], partial: true),
    AskEntity('acc2', ['Banque Misr', 'بنك مصر'], partial: true),
  ],
);

Account acct(String id, AccountKind kind, String label) => Account(
  id: id,
  kind: kind,
  label: label,
  defaultCurrency: egp,
  isHidden: false,
  isDefaultCash: false,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

AccountBalance bal(String id, Money m, int day) => AccountBalance(
  accountId: id,
  currency: m.currency,
  balance: m,
  asOf: DateTime.utc(2026, 11, day),
);

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late ChartRepository charts;
  var budgets = <Currency, Money>{};
  var accounts = <AccountWithBalances>[];
  var ents = entities;

  Future<void> add(
    String id, {
    int amount = 1000,
    String direction = 'expense',
    String currency = 'EGP',
    int? when,
    String account = 'acc1',
    String? category,
    String? merchant,
    String? merchantRaw,
  }) => db
      .into(db.transactions)
      .insert(
        txn(
          id,
          accountId: account,
          direction: direction,
          amountMinor: amount,
          currency: currency,
          occurredAt: when ?? at(2026, 11, 3),
          merchantNorm: merchant,
          merchant: merchantRaw ?? merchant,
        ).copyWith(categoryId: Value(category)),
      );

  AskEngine engine() => AskEngine(
    charts: charts,
    accounts: () async => accounts,
    cycleBudgets: () async => budgets,
    schedule: () async => PaydaySchedule.single(25),
    entities: () async => ents,
    today: () => CivilDate(2026, 11, 10),
  );

  Future<void> category(String id, String bucket) => db
      .into(db.categories)
      .insert(
        CategoriesCompanion.insert(
          id: id,
          nameAr: id,
          nameEn: id,
          icon: 'x',
          color: '#000000',
          bucket: bucket,
          sort: 0,
          isCustom: const Value(1),
        ),
      );

  setUp(() async {
    edb = await EncryptedDb.open(background: false);
    db = edb.db;
    budgets = {};
    accounts = [];
    ents = entities;
    await db.into(db.accounts).insert(account('acc1', kind: 'debit'));
    await db
        .into(db.accounts)
        .insert(account('acc2', kind: 'credit', last4: '5678'));
    await category('cw', 'wants');
    await category('cn', 'needs');
    charts = ChartRepository(db);
    // November (this month).
    await add('e1', amount: 100000, category: 'cw', merchant: 'carrefour');
    await add(
      'e2',
      amount: 50000,
      category: 'cn',
      merchant: 'uber',
      merchantRaw: 'Uber',
    );
    await add('e3', amount: 2500, currency: 'GBP');
    await add(
      'e4',
      amount: 30000,
      account: 'acc2',
      category: 'cw',
      merchant: 'carrefour',
    );
    // October (last month).
    await add(
      'o1',
      amount: 40000,
      when: at(2026, 10, 10),
      merchant: 'carrefour',
    );
  });
  tearDown(() => edb.close());

  Future<T> ask<T extends AskAnswer>(String q) async {
    final a = await engine().ask(q);
    expect(a, isA<T>(), reason: 'answer type');
    return a as T;
  }

  group('spend (FR-CHAT-01)', () {
    test(
      'AC: "how much on my CIB card this month" answers per currency',
      () async {
        final a = await ask<AskSpendAnswer>('صرفت كام بكارت CIB الشهر ده؟');
        expect(a.target, AskTarget.card);
        expect(a.targetLabel, 'CIB');
        expect(a.period.key, '2026-11-01..2026-11-30');
        // acc1 only: 100000 + 50000 EGP and 2500 GBP; never summed together.
        expect(a.figures, [Money(egp, 150000), Money(gbp, 2500)]);
      },
    );

    test('everything: one figure per currency, accounts all', () async {
      final a = await ask<AskSpendAnswer>('how much did I spend this month');
      expect(a.target, AskTarget.everything);
      expect(a.figures, [Money(egp, 180000), Money(gbp, 2500)]);
      expect(a.periodDefaulted, isFalse);
      final d = await ask<AskSpendAnswer>('صرفت كام');
      expect(d.periodDefaulted, isTrue);
    });

    test('category, merchant and last month', () async {
      final c = await ask<AskSpendAnswer>('صرفت كام على الاكل الشهر ده');
      expect(c.target, AskTarget.category);
      expect(c.categoryId, 'cw');
      expect(c.figures, [Money(egp, 130000)]);
      final m = await ask<AskSpendAnswer>('spent at Carrefour this month');
      expect(m.figures, [Money(egp, 130000)]);
      final lm = await ask<AskSpendAnswer>(
        'صرفت كام على كارفور الشهر اللي فات',
      );
      expect(lm.figures, [Money(egp, 40000)]);
      expect(lm.targetLabel, 'Carrefour');
    });

    test('a currency the user asked for restricts the answer', () async {
      final g = await ask<AskSpendAnswer>(
        'how much did I spend in GBP this month',
      );
      expect(g.figures, [Money(gbp, 2500)]);
      final e = await ask<AskSpendAnswer>('صرفت كام بالجنيه الشهر ده');
      expect(e.figures, [Money(egp, 180000)]);
      final none = await ask<AskNoDataAnswer>('صرفت كام بالدولار الشهر ده');
      expect(none.reason, AskNoDataReason.noTransactions);
    });

    test('no data is an answer, not a zero', () async {
      final a = await ask<AskNoDataAnswer>('صرفت كام على الاكل امبارح');
      expect(a.intent, AskIntent.spend);
    });

    test('refunds and links reduce the figure (chart rules)', () async {
      await add('rf', amount: 5000, direction: 'refund', category: 'cw');
      final a = await ask<AskSpendAnswer>('صرفت كام على الاكل الشهر ده');
      expect(a.figures, [Money(egp, 130000)]);
    });
  });

  group('fallback (FR-CHAT-03/05)', () {
    test('AC: an unknown question is a fallback, never a number', () async {
      for (final q in [
        'سعر الدهب كام النهارده',
        'what is the weather',
        'صرفت كام على بلانتو',
        'how much did I spend with my Unknown card',
        '',
      ]) {
        final a = await engine().ask(q);
        expect(a, isA<AskFallbackAnswer>(), reason: 'fallback');
        expect((a as AskFallbackAnswer).chips, askFallbackChips);
      }
    });

    test(
      'random garbage never answers with a figure and never throws',
      () async {
        final rnd = Random(110);
        const pool = 'ظذضxqzjvwk ?!٠١٢٣9 ‏';
        for (var i = 0; i < 200; i++) {
          final s = String.fromCharCodes([
            for (var k = 0; k < 1 + rnd.nextInt(80); k++)
              pool.codeUnitAt(rnd.nextInt(pool.length)),
          ]);
          expect(await engine().ask(s), isA<AskFallbackAnswer>());
        }
      },
    );

    test('a failing read is "unavailable", without detail', () async {
      final e = AskEngine(
        charts: charts,
        accounts: () async => accounts,
        cycleBudgets: () async => budgets,
        schedule: () async => PaydaySchedule.single(25),
        entities: () async => throw const FormatException('secret detail'),
        today: () => CivilDate(2026, 11, 10),
      );
      final a = await e.ask('صرفت كام');
      expect(a, isA<AskUnavailableAnswer>());
      expect(a.toString(), isNot(contains('secret')));
    });

    test('answers print redacted', () async {
      final a = await ask<AskSpendAnswer>('صرفت كام بكارت CIB');
      expect(a.toString(), isNot(contains('150000')));
      expect(a.toString(), isNot(contains('CIB')));
    });

    test('chips answer without parsing text', () async {
      expect(
        await engine().askChip(AskChip.spendThisMonth),
        isA<AskSpendAnswer>(),
      );
      expect(await engine().askChip(AskChip.roast), isA<AskRoastAnswer>());
      expect(
        await engine().askChip(AskChip.compareMonths),
        isA<AskCompareAnswer>(),
      );
      expect(followUpChips(AskIntent.spend), isNotEmpty);
      for (final i in AskIntent.values) {
        expect(followUpChips(i), isNotEmpty);
      }
    });
  });

  group('compare', () {
    test('this month against last, per currency, with the change', () async {
      final a = await ask<AskCompareAnswer>('قارن الشهر ده بالشهر اللي فات');
      expect(a.current.key, '2026-11-01..2026-11-30');
      expect(a.previous.key, '2026-10-01..2026-10-31');
      expect(a.figures.length, 2);
      final e = a.figures[0];
      expect(e.current, Money(egp, 180000));
      expect(e.previous, Money(egp, 40000));
      expect(e.deltaBp, 35000);
      final g = a.figures[1];
      expect(g.current, Money(gbp, 2500));
      expect(g.previous, Money(gbp, 0));
      expect(g.deltaBp, isNull);
    });

    test('"more than last month?" compares', () async {
      final a = await ask<AskCompareAnswer>(
        'did I spend more than last month?',
      );
      expect(a.figures.first.current, Money(egp, 180000));
    });
  });

  group('top merchants', () {
    test('limit and one list per currency with merchants', () async {
      final a = await ask<AskTopMerchantsAnswer>('اكتر 2 محلات صرفت فيها');
      expect(a.byCurrency.length, 1);
      expect(
        [for (final m in a.byCurrency.single) m.merchantNorm],
        ['carrefour', 'uber'],
      );
      final one = await ask<AskTopMerchantsAnswer>('top 1 merchants');
      expect(one.byCurrency.single.length, 1);
      final dflt = await ask<AskTopMerchantsAnswer>('top merchants last month');
      expect(dflt.byCurrency.single.single.amount, Money(egp, 40000));
    });
  });

  group('balance', () {
    setUp(() {
      accounts = [
        AccountWithBalances(acct('acc1', AccountKind.debit, 'CIB Debit'), [
          bal('acc1', Money(egp, 1000000), 9),
          bal('acc1', Money(gbp, 20000), 8),
        ]),
        AccountWithBalances(acct('acc3', AccountKind.cash, 'Wallet'), [
          bal('acc3', Money(egp, 50000), 7),
        ]),
        AccountWithBalances(acct('acc2', AccountKind.credit, 'Banque Misr'), [
          bal('acc2', Money(egp, 30000), 9),
        ]),
      ];
    });

    test('all asset accounts: one figure per currency, no cards', () async {
      final a = await ask<AskBalanceAnswer>('رصيدي كام');
      expect(
        [for (final f in a.figures) f.amount],
        [Money(egp, 1050000), Money(gbp, 20000)],
      );
      expect(a.figures.first.asOf, DateTime.utc(2026, 11, 9));
      expect(a.liability, isFalse);
      expect(a.accountLabel, isNull);
    });

    test('a named card is shown as a liability', () async {
      final a = await ask<AskBalanceAnswer>('رصيد كارت بنك مصر');
      expect(a.figures.single.amount, Money(egp, 30000));
      expect(a.liability, isTrue);
      expect(a.accountLabel, 'Banque Misr');
    });

    test('a currency filter keeps only that currency', () async {
      final g = await ask<AskBalanceAnswer>('what is my balance in GBP');
      expect(g.figures.single.amount, Money(gbp, 20000));
      final none = await ask<AskNoDataAnswer>('رصيدي بالدولار');
      expect(none.reason, AskNoDataReason.noAccounts);
    });

    test('no accounts at all is no data', () async {
      accounts = [];
      final a = await ask<AskNoDataAnswer>('what is my balance');
      expect(a.reason, AskNoDataReason.noAccounts);
    });
  });

  group('budget', () {
    test('what is left of this cycle, per currency', () async {
      budgets = {egp: Money(egp, 400000)};
      final a = await ask<AskBudgetAnswer>('فاضل كام في الميزانية');
      expect(a.cycle.key, '2026-10-25..2026-11-24');
      final f = a.figures.single;
      expect(f.spent, Money(egp, 180000));
      expect(f.remaining, Money(egp, 220000));
      expect(f.isOver, isFalse);
    });

    test('over budget is negative, not clamped', () async {
      budgets = {egp: Money(egp, 100000)};
      final a = await ask<AskBudgetAnswer>('budget remaining');
      expect(a.figures.single.remaining, Money(egp, -80000));
      expect(a.figures.single.isOver, isTrue);
    });

    test('no budget set is no data', () async {
      final a = await ask<AskNoDataAnswer>('can I spend more this month');
      expect(a.reason, AskNoDataReason.noBudget);
    });
  });

  group('upcoming dues', () {
    Future<void> item(String id, String next, {int amount = 100000}) => db
        .into(db.recurringItems)
        .insert(
          RecurringItemsCompanion.insert(
            id: id,
            kind: 'installment',
            status: 'active',
            name: 'Item $id',
            amountMinor: amount,
            currency: 'EGP',
            cadence: 'monthly',
            nextDueDate: Value(next),
            totalCount: const Value(6),
            createdAt: t0,
          ),
        );

    test('within 30 days, soonest first, with a total', () async {
      await item('soon', '2026-11-28');
      await item('overdue', '2026-11-05', amount: 20000);
      final a = await ask<AskDuesAnswer>('ايه الاقساط الجاية');
      final f = a.figures.single;
      // The overdue one (5 Nov) and its next charge (5 Dec) both fall in the
      // 30-day window; the 28 Dec charge of `soon` does not.
      expect(f.dues.map((d) => d.itemId), ['overdue', 'soon', 'overdue']);
      expect(f.dues.first.date, CivilDate(2026, 11, 5)); // unpaid, before today
      expect(f.total, Money(egp, 140000));
    });

    test('nothing due is no data', () async {
      final a = await ask<AskNoDataAnswer>('what bills are due');
      expect(a.reason, AskNoDataReason.noDues);
    });
  });

  group('biggest expense', () {
    test('one per currency, by net amount', () async {
      final a = await ask<AskBiggestAnswer>('اكبر مصروف الشهر ده');
      expect(a.figures.map((f) => f.amount), [
        Money(egp, 100000),
        Money(gbp, 2500),
      ]);
      expect(a.figures.first.merchant, 'carrefour');
      expect(a.figures.first.date, CivilDate(2026, 11, 3));
    });

    test('inside a category, and none', () async {
      final a = await ask<AskBiggestAnswer>('اكبر مصروف على المواصلات');
      expect(a.figures.single.amount, Money(egp, 50000));
      final n = await ask<AskNoDataAnswer>('biggest expense yesterday');
      expect(n.intent, AskIntent.biggestExpense);
    });
  });

  group('savings', () {
    test('income minus spend, per currency with income', () async {
      await add('inc', amount: 500000, direction: 'income');
      final a = await ask<AskSavingsAnswer>('وفرت كام الشهر ده');
      final f = a.figures.single;
      expect(f.income, Money(egp, 500000));
      expect(f.spend, Money(egp, 180000));
      expect(f.net, Money(egp, 320000));
    });

    test(
      'spend without income is "no income", not a negative saving',
      () async {
        final a = await ask<AskNoDataAnswer>('how much did I save this month');
        expect(a.reason, AskNoDataReason.noIncome);
      },
    );
  });

  group('roast (FR-CHAT-04)', () {
    test('picks a real fact about the spending, in one currency', () async {
      final a = await ask<AskRoastAnswer>('اقصف جبهتي يا زغلول');
      expect({
        RoastKind.topCategory,
        RoastKind.biggestExpense,
      }, contains(a.fact.kind));
      expect(a.fact.amount!.currency, egp);
    });

    test(
      'seed and recent change the pick; nothing to roast is no data',
      () async {
        final e = engine();
        final first = await e.ask('roast me', roastSeed: 0) as AskRoastAnswer;
        final second = await e.ask(
          'roast me',
          roastSeed: 0,
          recentRoasts: {first.fact.kind},
        ) as AskRoastAnswer;
        expect(second.fact.kind, isNot(first.fact.kind));
        await db.delete(db.transactions).go();
        charts.invalidate();
        final empty = await ask<AskNoDataAnswer>('roast me');
        expect(empty.intent, AskIntent.roast);
      },
    );
  });

  group('entities from the database', () {
    test('categories get the seeded aliases; capped merchants', () async {
      final e = await loadAskEntities(
        db,
        () async => [acct('acc1', AccountKind.debit, 'CIB Debit')],
      );
      expect(e.categories.map((c) => c.id), containsAll(['cw', 'cn']));
      expect(e.merchants.map((m) => m.id), contains('carrefour'));
      expect(e.accounts.single.names, contains('CIB Debit'));
      expect(e.merchants.length, lessThanOrEqualTo(askMaxMerchants));
    });
  });
}
