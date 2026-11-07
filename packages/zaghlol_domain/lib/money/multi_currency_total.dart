import 'currency.dart';
import 'money.dart';

/// An immutable set of per-currency totals (FR-CUR-03). Amounts in different
/// currencies are never combined here; the approximate (≈) view lives
/// elsewhere (T-115).
final class MultiCurrencyTotal {
  const MultiCurrencyTotal.empty() : _totals = const {};

  const MultiCurrencyTotal._(this._totals);

  /// Sums [items] per currency. Throws [MoneyOverflow] if a per-currency
  /// running total leaves the supported range.
  factory MultiCurrencyTotal.of(Iterable<Money> items) {
    final totals = <Currency, Money>{};
    for (final item in items) {
      totals[item.currency] = _plus(totals[item.currency], item);
    }
    return MultiCurrencyTotal._(Map<Currency, Money>.unmodifiable(totals));
  }

  final Map<Currency, Money> _totals;

  /// A new total with [money] added to its currency.
  MultiCurrencyTotal add(Money money) {
    final totals = Map<Currency, Money>.of(_totals);
    totals[money.currency] = _plus(totals[money.currency], money);
    return MultiCurrencyTotal._(Map<Currency, Money>.unmodifiable(totals));
  }

  /// Per-currency sum of two totals.
  MultiCurrencyTotal operator +(MultiCurrencyTotal other) {
    final totals = Map<Currency, Money>.of(_totals);
    for (final money in other._totals.values) {
      totals[money.currency] = _plus(totals[money.currency], money);
    }
    return MultiCurrencyTotal._(Map<Currency, Money>.unmodifiable(totals));
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
  /// present), then the featured currencies in D-22 order, then by code.
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

  static Money _plus(Money? total, Money money) {
    return total == null ? money : total + money;
  }
}
