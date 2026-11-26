import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');
Money e(String s) => Money.parse(s, egp);
List<Money> ps(List<String> v) => [for (final x in v) e(x)];

SuggestInputs fixture() => SuggestInputs(
  currency: egp,
  categories: [
    CategorySpend(
      id: 'sys:dining',
      name: 'Dining',
      periods: ps(['3400', '2800', '3400']),
    ),
    CategorySpend(
      id: 'sys:delivery',
      name: 'Delivery',
      periods: ps(['2000', '1100', '2300']),
    ),
    CategorySpend(
      id: 'sys:rent',
      name: 'Rent',
      periods: ps(['6000', '6500', '8000']),
    ),
  ],
  subscriptions: [
    SubscriptionCost(name: 'Streaming', monthly: e('300')),
    SubscriptionCost(name: 'Music', monthly: e('150')),
  ],
  cashWithdrawn: e('4000'),
  cashUnattributed: e('2400'),
);

List<Suggestion> run(
  SuggestInputs i, {
  SuggestThresholds t = const SuggestThresholds(),
}) => suggestSavings(inputs: [i], thresholds: t).single.suggestions;

void main() {
  test('AC2 SRS fixture: S4 600, S1 500, S2 300 in order', () {
    final r = run(fixture());
    expect(r.map((s) => s.kind), [
      SuggestionKind.s4CashLeak,
      SuggestionKind.s1AboveAverage,
      SuggestionKind.s2Subscription,
    ]);
    expect(r.map((s) => s.monthlySaving.toCanonicalString()), [
      '600.00',
      '500.00',
      '300.00',
    ]);
    expect(r[1].category, 'Delivery');
    expect(
      r.any((s) => s.category == 'Dining' || s.category == 'Rent'),
      isFalse,
    );
  });

  test('AC4 thresholds are parameters', () {
    // Dining 6% appears when s1Pct = 5.
    final f = fixture();
    final r = run(
      SuggestInputs(currency: egp, categories: f.categories),
      t: const SuggestThresholds(s1Pct: 5),
    );
    expect(r.any((s) => s.category == 'Dining'), isTrue);
    // S4 share 70% -> 60% share no longer qualifies.
    final r2 = run(fixture(), t: const SuggestThresholds(s4SharePct: 70));
    expect(r2.any((s) => s.kind == SuggestionKind.s4CashLeak), isFalse);
    // S4 saving pct 10 -> 240.
    final r3 = run(fixture(), t: const SuggestThresholds(s4SavingPct: 10));
    expect(
      r3.firstWhere((s) => s.kind == SuggestionKind.s4CashLeak).monthlySaving,
      e('240'),
    );
  });

  test('S1 boundary is exact at 15%', () {
    // avg 100, last 115 -> sum = 300 => periods 92.5, 92.5, 115 (minor ints)
    final at = SuggestInputs(
      currency: egp,
      categories: [
        CategorySpend(
          id: 'x',
          name: 'X',
          periods: ps(['92.50', '92.50', '115']),
        ),
      ],
    );
    expect(run(at), hasLength(1));
    final below = SuggestInputs(
      currency: egp,
      categories: [
        CategorySpend(
          id: 'x',
          name: 'X',
          periods: ps(['92.51', '92.50', '115']),
        ),
      ],
    );
    expect(run(below), isEmpty);
  });

  test('S3 creep: strictly rising, saving latest - earliest', () {
    final r = run(
      SuggestInputs(
        currency: egp,
        categories: [
          CategorySpend(
            id: 'fun',
            name: 'Fun',
            periods: ps(['100', '110', '120']),
          ),
          CategorySpend(
            id: 'flat',
            name: 'Flat',
            periods: ps(['100', '100', '120']),
          ),
        ],
      ),
    );
    expect(r, hasLength(1));
    expect(r.single.kind, SuggestionKind.s3Creep);
    expect(r.single.monthlySaving, e('20'));
  });

  test('fewer than 3 periods: no S1/S3', () {
    final r = run(
      SuggestInputs(
        currency: egp,
        categories: [
          CategorySpend(id: 'a', name: 'A', periods: ps(['10', '1000'])),
        ],
      ),
    );
    expect(r, isEmpty);
  });

  test('S4 threshold boundary 20% and zero withdrawals', () {
    SuggestInputs cash(String w, String u) => SuggestInputs(
      currency: egp,
      cashWithdrawn: e(w),
      cashUnattributed: e(u),
    );
    expect(run(cash('1000', '200')).single.monthlySaving, e('50'));
    expect(run(cash('1000', '199.99')), isEmpty);
    expect(run(cash('0', '0')), isEmpty);
  });

  test('top 3 only, ties ordered by category name', () {
    final r = run(
      SuggestInputs(
        currency: egp,
        categories: [
          for (final n in ['D', 'B', 'C', 'A'])
            CategorySpend(id: n, name: n, periods: ps(['100', '110', '120'])),
        ],
      ),
    );
    expect(r.map((s) => s.category), ['A', 'B', 'C']);
  });

  test('S1 and S3 on one category appear once, larger saving kept', () {
    final r = run(
      SuggestInputs(
        currency: egp,
        categories: [
          CategorySpend(id: 'k', name: 'K', periods: ps(['100', '110', '200'])),
        ],
      ),
    );
    expect(r, hasLength(1));
    expect(r.single.monthlySaving, e('100')); // S3 100 vs S1 ~63.33
  });

  test('essential: sys: prefix and essential parent are protected', () {
    final r = run(
      SuggestInputs(
        currency: egp,
        categories: [
          CategorySpend(
            id: 'sys:groceries',
            name: 'G',
            periods: ps(['1', '2', '9']),
          ),
          CategorySpend(
            id: 'custom-1',
            name: 'Child',
            parentId: 'sys:groceries',
            periods: ps(['1', '2', '9']),
          ),
        ],
      ),
    );
    expect(r, isEmpty);
  });

  test('AC3 one result per currency; mismatch and duplicates refused', () {
    final out = suggestSavings(
      inputs: [
        SuggestInputs(
          currency: egp,
          subscriptions: [SubscriptionCost(name: 'A', monthly: e('10'))],
        ),
        SuggestInputs(
          currency: usd,
          subscriptions: [
            SubscriptionCost(name: 'B', monthly: Money.parse('5', usd)),
          ],
        ),
      ],
    );
    expect(out.map((c) => c.currency), [egp, usd]);
    expect(out[1].suggestions.single.monthlySaving, Money.parse('5', usd));
    expect(
      () => suggestSavings(
        inputs: [
          SuggestInputs(
            currency: egp,
            subscriptions: [
              SubscriptionCost(name: 'B', monthly: Money.parse('5', usd)),
            ],
          ),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => suggestSavings(
        inputs: [
          SuggestInputs(currency: egp),
          SuggestInputs(currency: egp),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('negative proof 1: no double/num/toDouble under lib/ask', () {
    final banned = RegExp(r'\b(double|num)\b|toDouble|\.toInt\(\)\s*/');
    final files = Directory('lib/ask')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    expect(files, isNotEmpty);
    for (final f in files) {
      final code = f
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(banned.hasMatch(code), isFalse, reason: f.path);
    }
  });

  test(
    'negative proof 2: random inputs never suggest an essential category',
    () {
      final rng = Random(276);
      final essential = defaultEssentialCategoryIds.toList();
      for (var i = 0; i < 500; i++) {
        final cats = <CategorySpend>[];
        for (var j = 0; j < 6; j++) {
          final ess = rng.nextBool();
          final base = ess
              ? essential[rng.nextInt(essential.length)]
              : 'free$j';
          final id = ess && rng.nextBool() ? 'sys:$base' : base;
          cats.add(
            CategorySpend(
              id: ess ? id : 'free$j',
              name: ess ? 'ESS-$j' : 'Free$j',
              periods: [
                for (var k = 0; k < 3; k++) Money(egp, rng.nextInt(100000)),
              ],
            ),
          );
        }
        final r = run(SuggestInputs(currency: egp, categories: cats));
        expect(r.length, lessThanOrEqualTo(3));
        expect(r.any((s) => s.category.startsWith('ESS-')), isFalse);
      }
    },
  );
}
