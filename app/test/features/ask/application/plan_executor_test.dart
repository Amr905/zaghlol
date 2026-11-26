// T-342: the plan executor on an encrypted fixture database (Ahmed, SRS
// ask-llm section 10, synthetic). Today is Thu 2026-12-10, payday 25, so the
// last full cycle is 2026-10-25..2026-11-24 (31 days). Every row at +02:00.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/features/accounts/domain/account.dart';
import 'package:zaghlol/features/ask/application/plan_executor.dart';
import 'package:zaghlol/features/ask/domain/llm_answer_models.dart';
import 'package:zaghlol/features/insights/data/chart_repository.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/db/financial_fixtures.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');

int at(int y, int m, int d, [int h = 10]) =>
    DateTime.utc(y, m, d, h).millisecondsSinceEpoch;

const entities = AskEntities(
  categories: [
    AskEntity('sys:dining', ['مطاعم', 'dining']),
    AskEntity('sys:groceries', ['سوبر ماركت', 'groceries']),
    AskEntity('sys:health', ['صحة', 'health']),
  ],
  merchants: [
    AskEntity('carrefour', ['Carrefour', 'كارفور'], partial: true),
  ],
  accounts: [
    AskEntity('acc1', ['CIB'], partial: true),
  ],
);

const noPeriod = PlanPeriod(kind: PeriodKind.month, offset: 0);
const last = PlanPeriod(kind: PeriodKind.month, offset: -1);
const before = PlanPeriod(kind: PeriodKind.month, offset: -2);

MaskMap masks([Map<String, MaskTarget> m = const {}]) => MaskMap(m);

Money e(String s) => Money.parse(s, egp);
Money u(String s) => Money.parse(s, usd);

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  var budgets = <Currency, Money>{};
  var accounts = <AccountWithBalances>[];

  Future<void> add(
    String id,
    int amount,
    int when, {
    String direction = 'expense',
    String currency = 'EGP',
    String account = 'acc1',
    String? category,
    String? merchant,
  }) => db
      .into(db.transactions)
      .insert(
        txn(
          id,
          accountId: account,
          direction: direction,
          amountMinor: amount,
          currency: currency,
          occurredAt: when,
          merchantNorm: merchant,
          merchant: merchant,
        ).copyWith(categoryId: Value(category)),
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

  PlanExecutor exec({
    InvestPrices? prices,
    DateTime? now,
    AskEntities ents = entities,
  }) => PlanExecutor(
    charts: ChartRepository(db),
    accounts: () async => accounts,
    cycleBudgets: () async => budgets,
    schedule: () async => PaydaySchedule.single(25),
    entities: () async => ents,
    today: () => CivilDate(2026, 12, 10),
    prices: () async => prices ?? InvestPrices(certificateRateBp: 2000),
    now: () => now ?? DateTime.utc(2026, 12, 10, 12),
  );

  Future<T> run<T extends LlmAnswer>(
    Plan p, [
    MaskMap? m,
    PlanExecutor? x,
  ]) async {
    final a = await (x ?? exec()).execute(p, m ?? masks());
    expect(a, isA<T>(), reason: 'answer type ${a.runtimeType}');
    return a as T;
  }

  setUp(() async {
    edb = await EncryptedDb.open(background: false);
    db = edb.db;
    budgets = {};
    accounts = [];
    await db.into(db.accounts).insert(account('acc1', kind: 'debit'));
    await db
        .into(db.accounts)
        .insert(account('acc2', kind: 'credit', last4: '4321'));
    await category('sys:dining', 'wants');
    await category('sys:groceries', 'needs');
    await category('sys:health', 'needs');
    // Dining: 3000 / 3200 / 3400 in the three full cycles (EGP).
    await add('d1', 300000, at(2026, 8, 25), category: 'sys:dining');
    await add('d2', 320000, at(2026, 9, 30), category: 'sys:dining');
    await add('d3', 340000, at(2026, 11, 1), category: 'sys:dining');
    // Last cycle: the rest of EGP 20,500.00 (groceries; 1,500 on acc2).
    await add(
      'g1',
      1560000,
      at(2026, 11, 5),
      category: 'sys:groceries',
      merchant: 'carrefour',
    );
    await add(
      'g2',
      150000,
      at(2026, 11, 6),
      category: 'sys:groceries',
      account: 'acc2',
    );
    // Income last cycle, EGP 25,000.00.
    await add('i1', 2500000, at(2026, 11, 1), direction: 'income');
    // USD (acc1): dining 50 / 40 and income 100.
    await add(
      'ud1',
      5000,
      at(2026, 11, 3),
      currency: 'USD',
      category: 'sys:dining',
    );
    await add(
      'ud0',
      4000,
      at(2026, 10, 3),
      currency: 'USD',
      category: 'sys:dining',
    );
    await add(
      'ui',
      10000,
      at(2026, 11, 2),
      currency: 'USD',
      direction: 'income',
    );
    // Current cycle (partial): EGP 300.00.
    await add('c1', 30000, at(2026, 12, 2), category: 'sys:groceries');
  });
  tearDown(() => edb.close());

  group('AC1 fixture figures', () {
    test('PL-COMPARE dining: +EGP 200.00 (+6 %), USD line separate', () async {
      final a = await run<LlmCompareAnswer>(
        const PlanCompare(last, before, PlanFilter(slug: 'dining')),
      );
      expect(a.figures.map((f) => f.current.currency), [egp, usd]);
      final f = a.figures.first;
      expect(f.current, e('3400'));
      expect(f.difference, e('200'));
      expect(f.deltaBp, 625);
      expect(a.figures.last.current, u('50'));
      expect(a.figures.last.difference, u('10'));
    });

    test('PL-AVERAGE per day, last cycle: EGP 661.29', () async {
      final a = await run<LlmAverageAnswer>(
        const PlanAverage(AveragePer.day, last, PlanFilter.none),
      );
      final f = a.figures.first;
      expect(f.total, e('20500'));
      expect(f.units, 31);
      expect(f.average.toCanonicalString(), '661.29');
      expect(a.partialExcluded, isFalse);
    });

    test('PL-SAVED: EGP 4,500.00', () async {
      final a = await run<LlmSavedAnswer>(const PlanSaved(last));
      expect(a.figures.first.saved, e('4500'));
      expect(a.figures.first.income, e('25000'));
    });

    test('PL-SPEND with the CARD placeholder: card 4321 only', () async {
      final m = masks({
        '⟦CARD_1⟧': const MaskTarget(kind: MaskKind.card, accountIds: ['acc2']),
      });
      final a = await run<LlmDataAnswer>(
        const PlanSpend(last, PlanFilter(ref: '⟦CARD_1⟧')),
        m,
      );
      expect(a.figures, [e('1500')]);
    });
  });

  group('AC2 names and placeholders', () {
    test('a mention not in the data: notFound with chips', () async {
      final a = await run<LlmNotFoundAnswer>(
        const PlanSpend(last, PlanFilter(mention: 'زيزو')),
      );
      expect(a.chips, isNotEmpty);
      expect(a.chips.length, lessThanOrEqualTo(llmMaxChips));
    });

    test('a mention that matches a merchant is resolved', () async {
      final a = await run<LlmDataAnswer>(
        const PlanSpend(last, PlanFilter(mention: 'كارفور')),
      );
      expect(a.target.kind, LlmTargetKind.merchant);
      expect(a.figures, [e('15600')]);
    });

    test('a placeholder missing from the map: fallback', () async {
      final a = await run<LlmFallbackAnswer>(
        const PlanSpend(last, PlanFilter(ref: '⟦CARD_2⟧')),
      );
      expect(a.reason, LlmFallbackReason.missingPlaceholder);
      final b = await run<LlmFallbackAnswer>(const PlanBalance('⟦BANK_1⟧'));
      expect(b.reason, LlmFallbackReason.missingPlaceholder);
    });

    test('a bank with none of the user accounts: notFound', () async {
      await run<LlmNotFoundAnswer>(
        const PlanSpend(last, PlanFilter(ref: '⟦BANK_1⟧')),
        masks({'⟦BANK_1⟧': const MaskTarget(kind: MaskKind.bank)}),
      );
    });

    test('fallback and refuse plans pass through', () async {
      final f = await run<LlmFallbackAnswer>(
        const PlanFallback(FallbackReason.zakah),
      );
      expect(f.reason, LlmFallbackReason.zakah);
      final r = await run<LlmRefuseAnswer>(
        const PlanRefuse(RefuseReason.unsafe, selfHarm: true),
      );
      expect(r.selfHarm, isTrue);
    });
  });

  group('AC3 EC-24 safe to spend', () {
    test('no budget: hint variant, no figure', () async {
      final a = await run<LlmSafeSpendAnswer>(const PlanSafeSpend());
      expect(a.hasBudget, isFalse);
      expect(a.figures, isEmpty);
    });

    test('with a budget: per remaining day, floored', () async {
      budgets = {egp: e('3000')};
      final a = await run<LlmSafeSpendAnswer>(const PlanSafeSpend());
      // Cycle 2026-11-25..2026-12-24, today 12-10: 15 days left, spent 300.
      expect(a.daysRemaining, 15);
      expect(a.figures, [e('180')]);
    });
  });

  group('AC4 no cross-currency sum', () {
    List<Money> moneys(LlmAnswer a) => switch (a) {
      LlmDataAnswer(:final figures) => figures,
      LlmCompareAnswer(:final figures) => [
        for (final f in figures) ...[f.current, f.previous],
      ],
      LlmBreakdownAnswer(:final lists) => [
        for (final l in lists)
          for (final r in l.rows) r.amount,
      ],
      LlmTopNAnswer(:final lists) => [
        for (final l in lists)
          for (final r in l.rows) r.amount,
      ],
      LlmAverageAnswer(:final figures) => [
        for (final f in figures) ...[f.total, f.average],
      ],
      LlmIncomeAnswer(:final figures) => figures,
      LlmSavedAnswer(:final figures) => [
        for (final f in figures) ...[f.income, f.spend, f.saved],
      ],
      _ => fail('not a data answer: ${a.runtimeType}'),
    };

    final plans = <String, Plan>{
      'spend': const PlanSpend(last, PlanFilter.none),
      'compare': const PlanCompare(last, before, PlanFilter(slug: 'dining')),
      'breakdown category': const PlanBreakdown(last, BreakdownBy.category, 5),
      'topN category': const PlanTopN(last, TopOf.category, 5),
      'topN expense': const PlanTopN(last, TopOf.expense, 5),
      'average': const PlanAverage(AveragePer.day, last, PlanFilter.none),
      'income': const PlanIncome(last, PlanFilter.none),
      'saved': const PlanSaved(last),
    };
    for (final e in plans.entries) {
      test('${e.key}: one list per currency, primary first', () async {
        final a = await exec().execute(e.value, masks());
        final cs = [for (final m in moneys(a)) m.currency.code];
        expect(cs.toSet(), {'EGP', 'USD'}, reason: e.key);
        expect(cs.first, 'EGP');
        // Rows of one currency come together: the code changes once.
        var changes = 0;
        for (var i = 1; i < cs.length; i++) {
          if (cs[i] != cs[i - 1]) changes++;
        }
        expect(changes, 1, reason: e.key);
      });
    }

    test('spend totals are the per-currency sums, never combined', () async {
      final a = await run<LlmDataAnswer>(
        const PlanSpend(last, PlanFilter.none),
      );
      expect(a.figures, [e('20500'), u('50')]);
    });
  });

  group('breakdown, top, average edges', () {
    test('category breakdown: top 1 + Other, shares', () async {
      final a = await run<LlmBreakdownAnswer>(
        const PlanBreakdown(last, BreakdownBy.category, 1),
      );
      final l = a.lists.first;
      expect(l.rows.single.id, 'sys:groceries');
      expect(l.rows.single.amount, e('17100'));
      expect(l.other, e('3400'));
    });

    test('average per day on the current cycle excludes today', () async {
      final a = await run<LlmAverageAnswer>(
        const PlanAverage(AveragePer.day, noPeriod, PlanFilter.none),
      );
      expect(a.partialExcluded, isTrue);
      expect(a.range.to, CivilDate(2026, 12, 9));
      expect(a.figures.first.units, 15);
    });

    test('average per month over a whole cycle: 1 unit', () async {
      final a = await run<LlmAverageAnswer>(
        const PlanAverage(AveragePer.month, last, PlanFilter.none),
      );
      expect(a.figures.first.units, 1);
      expect(a.figures.first.average, e('20500'));
    });

    test('no data in the period: fallback noData', () async {
      final a = await run<LlmFallbackAnswer>(
        const PlanSpend(
          PlanPeriod(kind: PeriodKind.month, offset: -30),
          PlanFilter.none,
        ),
      );
      expect(a.reason, LlmFallbackReason.noData);
    });
  });

  group('balance', () {
    Account acct(String id, AccountKind kind) => Account(
      id: id,
      kind: kind,
      label: id,
      defaultCurrency: egp,
      isHidden: false,
      isDefaultCash: false,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    AccountBalance bal(String id, Money m) => AccountBalance(
      accountId: id,
      currency: m.currency,
      balance: m,
      asOf: DateTime.utc(2026, 12, 9),
    );

    test('named accounts one by one; debit and credit never added', () async {
      accounts = [
        AccountWithBalances(acct('acc1', AccountKind.debit), [
          bal('acc1', e('1000')),
        ]),
        AccountWithBalances(acct('acc2', AccountKind.credit), [
          bal('acc2', e('-200')),
        ]),
      ];
      final a = await run<LlmBalanceAnswer>(
        const PlanBalance('⟦BANK_1⟧'),
        masks({
          '⟦BANK_1⟧': const MaskTarget(
            kind: MaskKind.bank,
            accountIds: ['acc1', 'acc2'],
          ),
        }),
      );
      expect(a.figures.map((f) => f.balance), [e('1000'), e('-200')]);
      expect(a.figures.last.liability, isTrue);
    });
  });

  group('what-if, suggest, invest', () {
    test('AC what-if dining 50 % x 12 = EGP 19,200.00 (basis 3)', () async {
      final a = await run<LlmWhatIfAnswer>(
        const PlanWhatIfCut(
          PlanFilter(slug: 'dining'),
          PlanMode(kind: WhatIfKind.percent, percent: 50),
          12,
        ),
      );
      final r = a.outcomes.first.result!;
      expect(a.outcomes.first.currency, egp);
      expect(r.base, e('3200'));
      expect(r.total.toCanonicalString(), '19200.00');
      expect(r.basisPeriods, 3);
      // USD has two full periods with spend (the third is empty): its own line.
      expect(a.outcomes.map((o) => o.currency), [egp, usd]);
    });

    test('EC-23: a target with no history gives no figure', () async {
      final a = await run<LlmWhatIfAnswer>(
        const PlanWhatIfCut(
          PlanFilter(slug: 'health'),
          PlanMode(kind: WhatIfKind.percent, percent: 50),
          12,
        ),
      );
      expect(a.outcomes.single.result, isNull);
    });

    test('amount mode only applies to its own currency', () async {
      final a = await run<LlmWhatIfAnswer>(
        const PlanWhatIfCut(
          PlanFilter(slug: 'dining'),
          PlanMode(kind: WhatIfKind.amount, amount: '500', currency: 'EGP'),
          6,
        ),
      );
      expect(a.outcomes.single.currency, egp);
      expect(a.outcomes.single.result!.monthlySaving, e('500'));
    });

    test('what-if save: amount x months', () async {
      final a = await run<LlmWhatIfSaveAnswer>(
        const PlanWhatIfSave(PlanAmount('250.5', null), 4),
      );
      expect(a.total, e('1002'));
    });

    test(
      'suggest: creeping dining (S3) is offered, groceries (essential) is not',
      () async {
        final a = await run<LlmSuggestAnswer>(const PlanSuggest(null));
        final s = a.perCurrency.single.suggestions;
        expect(
          s.any(
            (x) =>
                x.kind == SuggestionKind.s3Creep &&
                x.categoryId == 'sys:dining' &&
                x.monthlySaving == e('400'),
          ),
          isTrue,
        );
        expect(s.any((x) => x.categoryId == 'sys:groceries'), isFalse);
      },
    );

    test(
      'invest saved last period: EGP 4,500 buys 1.12 g of 21K gold',
      () async {
        final prices = InvestPrices(
          gold: [
            GoldQuote(
              karat: 21,
              pricePerGram: e('4000'),
              asOf: DateTime.utc(2026, 12, 10, 8),
            ),
          ],
          certificateRateBp: 2000,
        );
        final a = await run<LlmInvestAnswer>(
          const PlanInvest(PlanInvestSource(InvestSourceKind.savedLastPeriod), [
            Instrument.gold,
          ], 12),
          null,
          exec(prices: prices),
        );
        final f = a.figures.first;
        expect(f.saved, e('4500'));
        expect(f.illustration.band, InvestBand.gold);
        final g = f.illustration.rows.whereType<GoldRow>().first;
        expect(g.centigrams, 112);
        // USD saved last period is 100 - 50 = USD 50: its own figure.
        expect(a.figures.map((x) => x.saved.currency), [egp, usd]);
      },
    );

    test('invest: only `index` asked gives fallback unsupported', () async {
      final a = await run<LlmFallbackAnswer>(
        const PlanInvest(PlanInvestSource(InvestSourceKind.savedLastPeriod), [
          Instrument.indexFund,
        ], 12),
      );
      expect(a.reason, LlmFallbackReason.unsupported);
    });
  });

  test('bills: nothing due gives an empty answer, not an error', () async {
    final a = await run<LlmBillsAnswer>(const PlanBillsDue(30));
    expect(a.figures, isEmpty);
  });

  test('a database failure becomes fallback failed, never a throw', () async {
    await edb.close();
    final a = await exec().execute(
      const PlanSpend(last, PlanFilter.none),
      masks(),
    );
    expect(a, isA<LlmFallbackAnswer>());
    // Re-open so tearDown can close.
    edb = await EncryptedDb.open(background: false);
    db = edb.db;
  });

  test('AC5 no double / num in the feature files', () {
    final files = [
      'lib/features/ask/application/plan_executor.dart',
      'lib/features/ask/domain/llm_answer_models.dart',
    ];
    final bad = RegExp(r'\b(double|toDouble|num)\b|\.\d+e');
    for (final f in files) {
      final src = File(f)
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'));
      expect(src.where(bad.hasMatch), isEmpty, reason: f);
    }
  });
}
