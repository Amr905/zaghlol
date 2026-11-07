import 'currency.dart';
import 'money.dart';
import 'money_errors.dart';

/// An immutable set of per-currency totals (FR-CUR-03). Amounts in different
/// currencies are never combined here; the approximate (≈) view lives
/// elsewhere (T-115).
final class MultiCurrencyTotal {
  const MultiCurrencyTotal.empty() : _totals = const {};

  const MultiCurrencyTotal._(this._totals);

  /// Sums [items] per currency.
  ///
  /// Each per-currency sum is computed exactly and range-checked once at the
  /// end, so the result does not depend on the order of [items]. Throws
  /// [MoneyOverflow] if a final per-currency total is out of range.
  factory MultiCurrencyTotal.of(Iterable<Money> items) {
    return MultiCurrencyTotal._(_sum(items));
  }

  final Map<Currency, Money> _totals;

  /// A new total with [money] added to its currency.
  MultiCurrencyTotal add(Money money) {
    return MultiCurrencyTotal._(_sum([..._totals.values, money]));
  }

  /// Per-currency sum of two totals, range-checked once per currency.
  MultiCurrencyTotal operator +(MultiCurrencyTotal other) {
    final items = [..._totals.values, ...other._totals.values];
    return MultiCurrencyTotal._(_sum(items));
  }

  /// The total in [currency]; zero when there is none.
  Money operator [](Currency currency) {
    return _totals[currency] ?? Money.zero(currency);
  }

  /// Currencies present (including ones whose total is zero), sorted by
  /// code so the order is deterministic.
  List<Currency> get currencies {
    final codes = _totals.keys.toList();
    codes.sort((a, b) => a.code.compareTo(b.code));
    return codes;
  }

  /// Currencies present, ordered for display: [primary] first (when
  /// present), then the featured currencies in A-59 order, then by code.
  List<Currency> orderedFor(Currency primary) {
    int rank(Currency c) {
      if (c == primary) {
        return -1;
      }
      final featured = Currency.featuredCodes.indexOf(c.code);
      return featured >= 0 ? featured : Currency.featuredCodes.length;
    }

    final ordered = currencies;
    ordered.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.code.compareTo(b.code);
    });
    return ordered;
  }

  /// True when two or more currencies are present; the UI shows the
  /// currency switcher only then (EC-55).
  bool get isMultiCurrency => _totals.length >= 2;

  bool get isEmpty => _totals.isEmpty;

  /// The same totals without currencies whose total is zero.
  MultiCurrencyTotal nonZero() {
    final totals = Map<Currency, Money>.of(_totals);
    totals.removeWhere((currency, money) => money.isZero);
    return MultiCurrencyTotal._(Map<Currency, Money>.unmodifiable(totals));
  }

  @override
  bool operator ==(Object other) {
    if (other is! MultiCurrencyTotal ||
        other._totals.length != _totals.length) {
      return false;
    }
    for (final entry in _totals.entries) {
      if (other._totals[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(_totals.values);

  /// Currency codes only, never amounts (NFR-SEC-03).
  @override
  String toString() {
    final codes = currencies.map((c) => c.code).join(', ');
    return 'MultiCurrencyTotal($codes)';
  }

  static final BigInt _max = BigInt.from(Money.maxMinor);

  static Map<Currency, Money> _sum(Iterable<Money> items) {
    final sums = <Currency, BigInt>{};
    for (final item in items) {
      final previous = sums[item.currency] ?? BigInt.zero;
      sums[item.currency] = previous + BigInt.from(item.minor);
    }
    final totals = <Currency, Money>{};
    for (final MapEntry(key: currency, value: sum) in sums.entries) {
      if (sum.abs() > _max) {
        throw MoneyOverflow(currency, MoneyOp.sum);
      }
      totals[currency] = Money(currency, sum.toInt());
    }
    return Map<Currency, Money>.unmodifiable(totals);
  }
}
