// T-113: net worth per currency / unit (FR-WLT-01/02/05, BR-WLT-01/02,
// domain-algorithms §11). Pure Dart.
//
// Design note (C3):
// - A UNIT is a currency code (`EGP`) or a gold symbol (`XAU21_G`,
//   `XAU_COIN8G`). Net worth is computed per unit and never summed across
//   units (CLAUDE.md §2.4). The only cross-currency sum stays in the ≈ view
//   (T-115); [NetWorth.currencyTotalsWithGoldValued] only feeds it.
// - Currency lines are exact [Money]. Gold lines are kept natively: grams
//   x 1000 (or coins x 1000) under their gold symbol, like
//   `networth_snapshots` rows for a gold unit (milligrams).
// - Valuation (BR-WLT-02): gold value = quantity x price of that karat, in
//   the currency of the price, rounded half-even ONCE to the minor unit
//   (`price x quantityMilli / 1000`, exact on BigInt). 24 g of 21K at
//   4217.50 EGP/g = 101,220.00 EGP. A certificate is worth its principal
//   (accrued interest is not added until paid, A-37). Gold without a price
//   stays listed in its native unit (EC-35); it is never guessed or zeroed.
// - Valued gold is reported separately ([NetWorth.valuedGold]); it is not
//   merged into the currency buckets, so a snapshot or a chart never shows
//   the same gold twice under two units by accident.
// - Liabilities are positive amounts that reduce net worth. A card whose
//   outstanding balance is negative (overpaid) is a negative liability.
// - Overflow throws [NetWorthOverflow] (a code, no amounts).

import '../budget/civil_date.dart';
import '../core/safe_exception.dart';
import '../money/currency.dart';
import '../money/money.dart';
import '../money/money_errors.dart';
import '../money/multi_currency_total.dart';
import '../money/rounding.dart';

/// A sum left the supported range (|minor| <= 2^53 - 1). Code only.
final class NetWorthOverflow extends SafeException {
  NetWorthOverflow() : super('NET_WORTH_OVERFLOW');
}

/// Gold unit symbols (the price feed's symbols, database-schema §2.6).
abstract final class GoldSymbols {
  static const String coin = 'XAU_COIN8G';

  /// `XAU<karat>_G` for 24, 22, 21 or 18; null for any other karat.
  static String? forKarat(int karat) =>
      const {24, 22, 21, 18}.contains(karat) ? 'XAU${karat}_G' : null;

  static bool isGold(String unit) => unit.startsWith('XAU');
}

/// The price of one gram (or one coin) of a gold symbol, in one currency.
final class GoldPrice {
  const GoldPrice({required this.price, this.stale = false});
  final Money price;

  /// EC-34: the price is older than 24 h; the value is labelled.
  final bool stale;
}

/// A money line: cash, balance, certificate principal, manual value, card
/// balance, remaining installments, any liability.
final class MoneyLine {
  const MoneyLine(this.amount, {this.isLiability = false});
  final Money amount;
  final bool isLiability;
}

/// A gold line in its native unit. [quantityMilli] is grams x 1000 (coins x
/// 1000 for [GoldSymbols.coin]).
final class GoldLine {
  GoldLine(this.symbol, this.quantityMilli) {
    if (!GoldSymbols.isGold(symbol) || quantityMilli < 1) {
      throw ArgumentError('invalid gold line');
    }
  }
  final String symbol;
  final int quantityMilli;
}

/// Gold valued at a price (BR-WLT-02).
final class ValuedGold {
  const ValuedGold({
    required this.symbol,
    required this.quantityMilli,
    required this.value,
    required this.stale,
  });
  final String symbol;
  final int quantityMilli;
  final Money value;
  final bool stale;
}

/// One unit's totals. For a currency unit the amounts are minor units; for a
/// gold unit they are milli-grams (milli-coins).
final class UnitNetWorth {
  const UnitNetWorth({
    required this.unit,
    required this.assetsMinor,
    required this.liabilitiesMinor,
  });
  final String unit;
  final int assetsMinor;
  final int liabilitiesMinor;
  int get netMinor => assetsMinor - liabilitiesMinor;
  bool get isGold => GoldSymbols.isGold(unit);
}

final class NetWorth {
  const NetWorth({
    required this.units,
    required this.valuedGold,
    required this.currencyTotalsWithGoldValued,
  });

  /// Currency units by code, then gold units by symbol. Units whose assets
  /// and liabilities are both zero are left out.
  final List<UnitNetWorth> units;

  /// Gold that had a price, with its value.
  final List<ValuedGold> valuedGold;

  /// Net per currency PLUS valued gold, for the ≈ view only (T-115). Gold
  /// without a price is not in it.
  final MultiCurrencyTotal currencyTotalsWithGoldValued;

  UnitNetWorth? unit(String code) {
    for (final u in units) {
      if (u.unit == code) return u;
    }
    return null;
  }
}

/// Value of [quantityMilli] (grams x 1000) at [price] per gram (per coin).
Money valueGold(Money price, int quantityMilli) =>
    price.mulDiv(quantityMilli, 1000, MoneyRounding.halfEven);

/// Net worth per unit. [goldPrice] returns the price of one gram (coin) of a
/// symbol, or null when there is none.
NetWorth computeNetWorth({
  required Iterable<MoneyLine> money,
  Iterable<GoldLine> gold = const [],
  GoldPrice? Function(String symbol)? goldPrice,
}) {
  final assets = <String, int>{};
  final liabilities = <String, int>{};
  void add(Map<String, int> m, String unit, int v) {
    final sum = (m[unit] ?? 0) + v;
    if (sum > Money.maxMinor || sum < -Money.maxMinor) {
      throw NetWorthOverflow();
    }
    m[unit] = sum;
  }

  for (final line in money) {
    add(
      line.isLiability ? liabilities : assets,
      line.amount.currency.code,
      line.amount.minor,
    );
  }
  final quantity = <String, int>{};
  for (final g in gold) {
    add(quantity, g.symbol, g.quantityMilli);
  }

  final valued = <ValuedGold>[];
  final withGold = <Money>[];
  for (final entry in quantity.entries) {
    final price = goldPrice?.call(entry.key);
    if (price != null && price.price.isPositive) {
      try {
        valued.add(
          ValuedGold(
            symbol: entry.key,
            quantityMilli: entry.value,
            value: valueGold(price.price, entry.value),
            stale: price.stale,
          ),
        );
      } on MoneyOverflow {
        throw NetWorthOverflow();
      }
    }
  }
  valued.sort((a, b) => a.symbol.compareTo(b.symbol));
  for (final entry in quantity.entries) {
    add(assets, entry.key, entry.value);
  }

  final codes = {...assets.keys, ...liabilities.keys}.toList()
    ..sort((a, b) {
      final ga = GoldSymbols.isGold(a);
      final gb = GoldSymbols.isGold(b);
      if (ga != gb) return ga ? 1 : -1;
      return a.compareTo(b);
    });
  final units = <UnitNetWorth>[
    for (final c in codes)
      if ((assets[c] ?? 0) != 0 || (liabilities[c] ?? 0) != 0)
        UnitNetWorth(
          unit: c,
          assetsMinor: assets[c] ?? 0,
          liabilitiesMinor: liabilities[c] ?? 0,
        ),
  ];

  for (final u in units) {
    if (u.isGold) continue;
    withGold.add(Money(Currency.of(u.unit), u.netMinor));
  }
  for (final v in valued) {
    withGold.add(v.value);
  }
  try {
    return NetWorth(
      units: units,
      valuedGold: valued,
      currencyTotalsWithGoldValued: MultiCurrencyTotal.of(withGold),
    );
  } on MoneyOverflow {
    throw NetWorthOverflow();
  }
}

/// A row for `networth_snapshots`.
typedef SnapshotRow = ({String unit, int assetsMinor, int liabilitiesMinor});

/// The rows to store for a snapshot: one per unit, native (gold in
/// milligrams, never valued).
List<SnapshotRow> snapshotRows(NetWorth worth) => [
  for (final u in worth.units)
    (
      unit: u.unit,
      assetsMinor: u.assetsMinor,
      liabilitiesMinor: u.liabilitiesMinor,
    ),
];

/// Whether a snapshot is due (A-20: at each cycle end, at least monthly).
/// A snapshot is due when none exists, when the last one is older than the
/// start of the current cycle (so the first call of a new cycle takes it), or
/// when it is more than 31 days old. Taking one on demand ignores this.
bool snapshotDue({
  required CivilDate? last,
  required CivilDate today,
  required CivilDate currentCycleStart,
}) {
  if (last == null) return true;
  if (last < currentCycleStart) return true;
  return today.difference(last) > 31;
}

/// How a certificate pays interest.
enum PayoutFrequency {
  monthly(12),
  quarterly(4),
  semiAnnual(2),
  annual(1),
  atMaturity(0);

  const PayoutFrequency(this.perYear);
  final int perYear;

  static PayoutFrequency? fromSlug(String? slug) => switch (slug) {
    'monthly' => monthly,
    'quarterly' => quarterly,
    'semi_annual' => semiAnnual,
    'annual' => annual,
    'at_maturity' => atMaturity,
    _ => null,
  };
}

/// One upcoming interest payment (FR-WLT-04). [amount] is null only when it
/// cannot be known (an at-maturity certificate without a start date).
final class CertificatePayoutEvent {
  const CertificatePayoutEvent({
    required this.assetId,
    required this.date,
    required this.amount,
    required this.isMaturity,
  });
  final String assetId;

  /// Gregorian local date (PO decision T-019 Q2).
  final CivilDate date;
  final Money? amount;
  final bool isMaturity;
}

/// Interest dates and amounts of one certificate in `[from, to]`.
///
/// Periodic payouts fall on the maturity day-of-month stepped back by whole
/// periods (clamped to short months), each worth
/// `principal x rate / periodsPerYear`, rounded half-even. At maturity only
/// the interest is listed (principal is not a payout). An at-maturity
/// certificate pays `principal x rate x months / 12` for the whole months
/// between [startDate] and [maturity]; without [startDate] the amount is null.
/// Payments before [startDate] are not listed. Limited to 1200 periods.
List<CertificatePayoutEvent> certificatePayouts({
  required String assetId,
  required Money principal,
  required int rateBp,
  required PayoutFrequency payout,
  required CivilDate maturity,
  CivilDate? startDate,
  required CivilDate from,
  required CivilDate to,
}) {
  if (rateBp < 0 || rateBp > 100000) {
    throw ArgumentError('rate out of range');
  }
  Money interest(int months) =>
      principal.mulDiv(rateBp * months, 10000 * 12, MoneyRounding.halfEven);
  bool inRange(CivilDate d) => d >= from && d <= to;

  if (payout == PayoutFrequency.atMaturity) {
    if (!inRange(maturity)) return const [];
    final months = startDate == null ? null : _wholeMonths(startDate, maturity);
    return [
      CertificatePayoutEvent(
        assetId: assetId,
        date: maturity,
        amount: months == null ? null : interest(months),
        isMaturity: true,
      ),
    ];
  }
  final step = 12 ~/ payout.perYear;
  final each = interest(step);
  final events = <CertificatePayoutEvent>[];
  for (var k = 0; k < 1200; k++) {
    final date = _minusMonths(maturity, k * step);
    if (date < from) break;
    if (startDate != null && date <= startDate) break;
    if (date <= to) {
      events.add(
        CertificatePayoutEvent(
          assetId: assetId,
          date: date,
          amount: each,
          isMaturity: k == 0,
        ),
      );
    }
  }
  return events.reversed.toList();
}

/// Whole months from [a] to [b] (b later); 0 when b is not after a.
int _wholeMonths(CivilDate a, CivilDate b) {
  var m = (b.year - a.year) * 12 + (b.month - a.month);
  if (b.day < a.day) m--;
  return m < 0 ? 0 : m;
}

CivilDate _minusMonths(CivilDate d, int months) {
  final total = d.year * 12 + (d.month - 1) - months;
  final y = total ~/ 12;
  final m = total % 12 + 1;
  if (y < 1) return CivilDate(1, 1, 1);
  final dim = CivilDate.daysInMonth(y, m);
  return CivilDate(y, m, d.day > dim ? dim : d.day);
}
