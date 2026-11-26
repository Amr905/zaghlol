/// Saving suggestions S1-S4 for the Ask helper (T-326, SRS ask-llm §3.3).
///
/// Pure and per currency. Every threshold test is done on integers in minor
/// units, with no division before the comparison.
library;

import '../mascot_rules/mascot_rules.dart'
    show categoryCode, defaultEssentialCategoryIds;
import '../money/currency.dart';
import '../money/money.dart';
import '../money/rounding.dart';

enum SuggestionKind { s1AboveAverage, s2Subscription, s3Creep, s4CashLeak }

/// Thresholds (remote config `ask.s1_pct`, `ask.s4_share_pct`,
/// `ask.s4_saving_pct`); defaults 15 / 20 / 25.
final class SuggestThresholds {
  const SuggestThresholds({
    this.s1Pct = 15,
    this.s4SharePct = 20,
    this.s4SavingPct = 25,
  });
  final int s1Pct;
  final int s4SharePct;
  final int s4SavingPct;
}

/// One category's spend per full period, oldest first (last 3 periods).
final class CategorySpend {
  const CategorySpend({
    required this.id,
    required this.name,
    required this.periods,
    this.parentId,
  });

  /// Category id; a `sys:` prefix is accepted.
  final String id;
  final String name;
  final String? parentId;
  final List<Money> periods;
}

final class SuggestSubscriptionCost {
  const SuggestSubscriptionCost({required this.name, required this.monthly});
  final String name;
  final Money monthly;
}

final class SuggestInputs {
  const SuggestInputs({
    required this.currency,
    this.categories = const [],
    this.subscriptions = const [],
    this.cashWithdrawn,
    this.cashUnattributed,
  });
  final Currency currency;
  final List<CategorySpend> categories;
  final List<SuggestSubscriptionCost> subscriptions;

  /// Cash withdrawn in the last full period and the part not attributed to
  /// any category (CAT-CASH pool).
  final Money? cashWithdrawn;
  final Money? cashUnattributed;
}

final class Suggestion {
  const Suggestion({
    required this.kind,
    required this.category,
    required this.monthlySaving,
    required this.basisPeriods,
  });
  final SuggestionKind kind;

  /// Category name, subscription name, or `CAT-CASH` for S4.
  final String category;
  final Money monthlySaving;
  final int basisPeriods;
}

final class CurrencySuggestions {
  const CurrencySuggestions(this.currency, this.suggestions);
  final Currency currency;
  final List<Suggestion> suggestions;
}

const int maxSuggestions = 3;
const String cashPoolLabel = 'CAT-CASH';
const int _basis = 3;

bool _essential(CategorySpend c, Set<String> essential) {
  bool hit(String id) =>
      essential.contains(id) || essential.contains(categoryCode(id));
  return hit(c.id) || (c.parentId != null && hit(c.parentId!));
}

Money _money(Currency c, BigInt minor) => Money(c, minor.toInt());

/// Runs S1-S4 for each input (one result per currency) and returns the top
/// [maxSuggestions] by monthly saving, ties by category name.
List<CurrencySuggestions> suggestSavings({
  required List<SuggestInputs> inputs,
  SuggestThresholds thresholds = const SuggestThresholds(),
  Set<String> essentialCategories = defaultEssentialCategoryIds,
}) {
  if (thresholds.s1Pct < 0 ||
      thresholds.s4SharePct < 0 ||
      thresholds.s4SharePct > 100 ||
      thresholds.s4SavingPct < 0 ||
      thresholds.s4SavingPct > 100) {
    throw ArgumentError('threshold out of range');
  }
  final seen = <Currency>{};
  final out = <CurrencySuggestions>[];
  for (final input in inputs) {
    if (!seen.add(input.currency)) {
      throw ArgumentError('duplicate currency input');
    }
    out.add(
      CurrencySuggestions(
        input.currency,
        _forCurrency(input, thresholds, essentialCategories),
      ),
    );
  }
  return out;
}

List<Suggestion> _forCurrency(
  SuggestInputs input,
  SuggestThresholds t,
  Set<String> essential,
) {
  final cur = input.currency;
  void same(Money m) {
    if (m.currency != cur) throw ArgumentError('currency mismatch');
  }

  // Per category: keep the best of S1 / S3 so a category appears once.
  final byCategory = <String, Suggestion>{};
  void offer(Suggestion s) {
    if (s.monthlySaving.minor <= 0) return;
    final prev = byCategory[s.category];
    if (prev == null || s.monthlySaving > prev.monthlySaving) {
      byCategory[s.category] = s;
    }
  }

  for (final c in input.categories) {
    for (final p in c.periods) {
      same(p);
    }
    if (_essential(c, essential) || c.periods.length < _basis) continue;
    final last3 = c.periods.sublist(c.periods.length - _basis);
    final p0 = BigInt.from(last3[0].minor);
    final p1 = BigInt.from(last3[1].minor);
    final p2 = BigInt.from(last3[2].minor);
    final sum = p0 + p1 + p2;
    // S1: last >= avg * (100 + pct) / 100  <=>  last*300 >= sum*(100+pct)
    if (p2 * BigInt.from(300) >= sum * BigInt.from(100 + t.s1Pct)) {
      // saving = last - sum/3, rounded half-even once.
      final saving = roundDiv(
        p2 * BigInt.from(3) - sum,
        BigInt.from(3),
        MoneyRounding.halfEven,
      );
      offer(
        Suggestion(
          kind: SuggestionKind.s1AboveAverage,
          category: c.name,
          monthlySaving: _money(cur, saving),
          basisPeriods: _basis,
        ),
      );
    }
    // S3: strictly rising in each of the last 3 periods.
    if (p0 < p1 && p1 < p2) {
      offer(
        Suggestion(
          kind: SuggestionKind.s3Creep,
          category: c.name,
          monthlySaving: _money(cur, p2 - p0),
          basisPeriods: _basis,
        ),
      );
    }
  }

  final all = <Suggestion>[...byCategory.values];

  // S2: largest active subscription (ties by name).
  SuggestSubscriptionCost? top;
  for (final s in input.subscriptions) {
    same(s.monthly);
    if (s.monthly.minor <= 0) continue;
    if (top == null ||
        s.monthly > top.monthly ||
        (s.monthly == top.monthly && s.name.compareTo(top.name) < 0)) {
      top = s;
    }
  }
  if (top != null) {
    all.add(
      Suggestion(
        kind: SuggestionKind.s2Subscription,
        category: top.name,
        monthlySaving: top.monthly,
        basisPeriods: 1,
      ),
    );
  }

  // S4: unattributed >= share% of withdrawals.
  final w = input.cashWithdrawn;
  final u = input.cashUnattributed;
  if (w != null && u != null) {
    same(w);
    same(u);
    if (w.minor > 0 &&
        u.minor > 0 &&
        BigInt.from(u.minor) * BigInt.from(100) >=
            BigInt.from(w.minor) * BigInt.from(t.s4SharePct)) {
      all.add(
        Suggestion(
          kind: SuggestionKind.s4CashLeak,
          category: cashPoolLabel,
          monthlySaving: u.mulDiv(t.s4SavingPct, 100, MoneyRounding.halfEven),
          basisPeriods: 1,
        ),
      );
    }
  }

  final positive = all.where((s) => s.monthlySaving.minor > 0).toList()
    ..sort((a, b) {
      final bySaving = b.monthlySaving.compareTo(a.monthlySaving);
      if (bySaving != 0) return bySaving;
      final byName = a.category.compareTo(b.category);
      return byName != 0 ? byName : a.kind.index.compareTo(b.kind.index);
    });
  return positive.take(maxSuggestions).toList();
}
