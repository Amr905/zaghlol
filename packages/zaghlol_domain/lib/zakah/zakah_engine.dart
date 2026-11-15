// T-167: Zakah engine (FR-ZAK-01..04, BR-ZAK-01..04, spec §11,
// domain-algorithms §12). Pure Dart. Flag `zakah` is OFF at launch; every
// fiqh choice below is a field of [ZakahRules] with the SRS default, and is
// listed for the scholar in docs/04-tasks/tasks/T-167.md (OQ-10, BR-ZAK-05).
//
// Design note (C4):
// - Amounts are NATIVE integers: minor units for a currency (per its own
//   exponent), milligrams for gold (milli-coins for the 8 g coin). Dues are
//   computed and returned in that native unit. Nothing is summed across units
//   except the nisab eligibility test, which needs one common measure: every
//   zakatable lot is valued in the currency of the 24K gold price, via the
//   caller's converter, and only the yes/no result and the two totals are
//   reported. A lot that can't be valued makes the result `needsPrices`: no
//   dues are stated, never a guess (EC-35).
// - Hawl is counted in days from the lot's [ZakahLot.hawlStart] (a Gregorian
//   civil date; the Hijri date is for display, hijri.dart). Due when
//   `elapsed >= rules.hawlDays` (354). Continuation: after a cycle is paid
//   the caller moves the lot's start to [nextHawlStart]. A lot is never reset
//   by this engine when wealth dips below nisab (SRS has no such rule).
// - Dues = amount x 25/1000 (2.5%), rounded ONCE per lot to its native unit
//   with [ZakahRules.rounding]. The EGP cost is the due valued at the gold
//   price (gold) or converted (other currencies), shown beside it, or null.
// - Short-term debts (BR-ZAK-04) are deducted from CASH lots of the same
//   currency only, oldest hawl first; a debt larger than that cash is not
//   carried to other assets or currencies.
// - Gold purity toward nisab: karat/24 (21K = 87.5%). The 8 g coin counts as
//   8 g of 21K. The due is still in the lot's own gold unit.

import '../budget/civil_date.dart';
import '../core/safe_exception.dart';
import '../money/currency.dart';
import '../money/money.dart';
import '../money/money_errors.dart';
import '../money/rounding.dart';
import '../wealth/net_worth.dart';

final class ZakahOverflow extends SafeException {
  ZakahOverflow() : super('ZAKAH_OVERFLOW');
}

enum ZakahLotKind { cash, gold, stock, certificate }

/// Fiqh parameters. Defaults are the SRS values.
final class ZakahRules {
  const ZakahRules({
    this.hawlDays = 354,
    this.rateNumerator = 25,
    this.rateDenominator = 1000,
    this.nisabGoldMilligrams = 85000,
    this.rounding = MoneyRounding.halfEven,
    this.coinGramsMilli = 8000,
    this.coinKarat = 21,
  });

  /// BR-ZAK-02.
  final int hawlDays;

  /// BR-ZAK-03: 2.5%.
  final int rateNumerator;
  final int rateDenominator;

  /// BR-ZAK-01: 85 g of 24K, in milligrams. A scholar may pick the silver
  /// nisab (595 g) by passing its value through [nisabValue] with a silver
  /// price instead; this engine takes the 24K price only.
  final int nisabGoldMilligrams;

  /// Rounding of the due to the unit's smallest step (not in the SRS).
  final MoneyRounding rounding;

  /// The 8 g coin: weight (milligrams) and karat (not in the SRS).
  final int coinGramsMilli;
  final int coinKarat;
}

/// One asset lot. [amount] is native: minor units (currency lots) or
/// milligrams / milli-coins (gold lots).
final class ZakahLot {
  ZakahLot({
    required this.id,
    required this.kind,
    required this.unit,
    required this.amount,
    required this.hawlStart,
    this.zakatable = true,
    this.paid = 0,
  }) {
    final gold = GoldSymbols.isGold(unit);
    if ((kind == ZakahLotKind.gold) != gold ||
        (!gold && Currency.tryOf(unit) == null) ||
        (gold && _karatOf(unit, const ZakahRules()) == null) ||
        amount < 0 ||
        amount > Money.maxMinor ||
        paid < 0 ||
        paid > Money.maxMinor) {
      throw ArgumentError('invalid zakah lot');
    }
  }

  final String id;
  final ZakahLotKind kind;

  /// Currency code or gold symbol.
  final String unit;
  final int amount;
  final CivilDate hawlStart;

  /// `is_zakatable_intent`; false lots are listed as excluded.
  final bool zakatable;

  /// Native amount already paid toward the current cycle (ledger).
  final int paid;

  bool get isGold => kind == ZakahLotKind.gold;
}

/// Prices the engine reads. Both return null when unknown.
final class ZakahMarket {
  const ZakahMarket({required this.goldPrice, required this.convert});

  /// Price of one gram (one coin) of a gold symbol.
  final Money? Function(String symbol) goldPrice;

  /// [amount] in [to], or null without a rate. Same currency: the caller
  /// returns it unchanged.
  final Money? Function(Money amount, Currency to) convert;
}

enum ZakahNisabState { belowNisab, eligible, needsPrices }

enum ZakahLotStatus { excluded, needsPrices, belowNisab, notDue, due }

enum ZakahPayment { pending, partial, paid }

final class ZakahLotResult {
  const ZakahLotResult({
    required this.lotId,
    required this.unit,
    required this.status,
    required this.hawlDaysElapsed,
    required this.daysRemaining,
    required this.dueOn,
    required this.netBase,
    required this.dueNative,
    required this.remainingNative,
    required this.costOfDue,
    required this.projectedDueNative,
    required this.projectedCost,
    required this.payment,
  });
  final String lotId;
  final String unit;
  final ZakahLotStatus status;
  final int hawlDaysElapsed;
  final int daysRemaining;

  /// Gregorian date the hawl completes (start + hawlDays).
  final CivilDate dueOn;

  /// Native amount after the debt deduction.
  final int netBase;

  /// Due now in native units; 0 unless [status] is `due`.
  final int dueNative;

  /// [dueNative] minus what was paid, never below 0.
  final int remainingNative;
  final Money? costOfDue;

  /// 2.5% if the lot stays as it is, for a lot still in its hawl.
  final int projectedDueNative;
  final Money? projectedCost;
  final ZakahPayment? payment;
}

final class ZakahResult {
  const ZakahResult({
    required this.state,
    required this.nisab,
    required this.wealth,
    required this.lots,
    required this.dueByUnit,
  });
  final ZakahNisabState state;

  /// 85 g of 24K, in the price's currency; null without a 24K price.
  final Money? nisab;

  /// Net zakatable wealth in the same currency (the one cross-unit sum, for
  /// the nisab test only; null when [state] is `needsPrices`).
  final Money? wealth;
  final List<ZakahLotResult> lots;

  /// Remaining due per native unit (gold in milligrams). Units never merge.
  final Map<String, int> dueByUnit;
}

int? _karatOf(String symbol, ZakahRules rules) {
  if (symbol == GoldSymbols.coin) return rules.coinKarat;
  for (final k in const [24, 22, 21, 18]) {
    if (symbol == GoldSymbols.forKarat(k)) return k;
  }
  return null;
}

/// Value of 85 g (rules) of 24K at [price24] per gram.
Money nisabValue(Money price24, ZakahRules rules) =>
    price24.mulDiv(rules.nisabGoldMilligrams, 1000, MoneyRounding.halfEven);

/// The date a lot's next hawl starts after the cycle that ends on
/// `hawlStart + hawlDays` is settled.
CivilDate nextHawlStart(CivilDate hawlStart, ZakahRules rules) =>
    hawlStart.plusDays(rules.hawlDays);

ZakahPayment? paymentStatus(int due, int paid) {
  if (due <= 0) return null;
  if (paid <= 0) return ZakahPayment.pending;
  return paid >= due ? ZakahPayment.paid : ZakahPayment.partial;
}

int _rate(int amount, ZakahRules r) => _roundMul(amount, r);

int _roundMul(int amount, ZakahRules r) => roundDiv(
  BigInt.from(amount) * BigInt.from(r.rateNumerator),
  BigInt.from(r.rateDenominator),
  r.rounding,
).toInt();

Money? _costOf(
  ZakahLot lot,
  int native,
  Money? price,
  Currency costCurrency,
  ZakahMarket market,
) {
  if (native == 0) return Money.zero(costCurrency);
  if (lot.isGold) {
    if (price == null || !price.isPositive) return null;
    return market.convert(valueGold(price, native), costCurrency);
  }
  return market.convert(Money(Currency.of(lot.unit), native), costCurrency);
}

/// Computes Zakah for [lots] on [today]. [debts] are short-term debts due now
/// (positive amounts). [costCurrency] is the currency of the "cost" column
/// (EGP). Throws [ZakahOverflow] when a sum leaves the supported range.
ZakahResult computeZakah({
  required Iterable<ZakahLot> lots,
  Iterable<Money> debts = const [],
  required CivilDate today,
  required ZakahMarket market,
  required Currency costCurrency,
  ZakahRules rules = const ZakahRules(),
}) {
  try {
    return _compute(lots.toList(), debts, today, market, costCurrency, rules);
  } on MoneyOverflow {
    throw ZakahOverflow();
  }
}

ZakahResult _compute(
  List<ZakahLot> lots,
  Iterable<Money> debts,
  CivilDate today,
  ZakahMarket market,
  Currency costCurrency,
  ZakahRules rules,
) {
  // Debt deduction: cash lots of the same currency, oldest hawl first.
  final remainingDebt = <String, int>{};
  for (final d in debts) {
    if (d.isNegative) throw ArgumentError('debt must not be negative');
    final c = d.currency.code;
    final sum = (remainingDebt[c] ?? 0) + d.minor;
    if (sum > Money.maxMinor) throw ZakahOverflow();
    remainingDebt[c] = sum;
  }
  final netBase = <String, int>{for (final l in lots) l.id: l.amount};
  final cash =
      lots.where((l) => l.zakatable && l.kind == ZakahLotKind.cash).toList()
        ..sort((a, b) {
          final c = a.hawlStart.compareTo(b.hawlStart);
          return c != 0 ? c : a.id.compareTo(b.id);
        });
  for (final l in cash) {
    final debt = remainingDebt[l.unit] ?? 0;
    if (debt <= 0) continue;
    final take = debt < l.amount ? debt : l.amount;
    netBase[l.id] = l.amount - take;
    remainingDebt[l.unit] = debt - take;
  }

  // Nisab: value everything in the 24K price's currency.
  final price24 = market.goldPrice(GoldSymbols.forKarat(24)!);
  final nisab = (price24 != null && price24.isPositive)
      ? nisabValue(price24, rules)
      : null;
  var priced = nisab != null;
  Money? wealth = nisab == null ? null : Money.zero(nisab.currency);
  if (nisab != null) {
    for (final l in lots) {
      if (!l.zakatable || netBase[l.id] == 0) continue;
      final Money? v;
      if (l.isGold) {
        final karat = _karatOf(l.unit, rules)!;
        final isCoin = l.unit == GoldSymbols.coin;
        // fine 24K milligrams x price24 / 1000, exact then rounded once.
        final num = isCoin
            ? BigInt.from(netBase[l.id]!) *
                  BigInt.from(rules.coinGramsMilli) *
                  BigInt.from(karat)
            : BigInt.from(netBase[l.id]!) * BigInt.from(karat);
        final den = BigInt.from(24) * BigInt.from(isCoin ? 1000 : 1);
        final fine = roundDiv(num, den, MoneyRounding.halfEven);
        if (fine > BigInt.from(Money.maxMinor)) throw ZakahOverflow();
        v = price24!.mulDiv(fine.toInt(), 1000, MoneyRounding.halfEven);
      } else {
        v = market.convert(
          Money(Currency.of(l.unit), netBase[l.id]!),
          nisab.currency,
        );
      }
      if (v == null) {
        priced = false;
        wealth = null;
        break;
      }
      wealth = wealth! + v;
    }
  }
  final state = !priced
      ? ZakahNisabState.needsPrices
      : (wealth! >= nisab!
            ? ZakahNisabState.eligible
            : ZakahNisabState.belowNisab);

  final results = <ZakahLotResult>[];
  final dueByUnit = <String, int>{};
  for (final l in lots) {
    final elapsedRaw = today.difference(l.hawlStart);
    final elapsed = elapsedRaw < 0 ? 0 : elapsedRaw;
    final remaining = rules.hawlDays - elapsed;
    final hawlDone = elapsed >= rules.hawlDays;
    final base = netBase[l.id]!;
    final price = l.isGold ? market.goldPrice(l.unit) : null;
    final status = !l.zakatable
        ? ZakahLotStatus.excluded
        : state == ZakahNisabState.needsPrices
        ? ZakahLotStatus.needsPrices
        : state == ZakahNisabState.belowNisab
        ? ZakahLotStatus.belowNisab
        : hawlDone
        ? ZakahLotStatus.due
        : ZakahLotStatus.notDue;
    final due = status == ZakahLotStatus.due ? _rate(base, rules) : 0;
    final projected = status == ZakahLotStatus.notDue ? _rate(base, rules) : 0;
    final left = due - l.paid < 0 ? 0 : due - l.paid;
    if (left > 0) dueByUnit[l.unit] = (dueByUnit[l.unit] ?? 0) + left;
    results.add(
      ZakahLotResult(
        lotId: l.id,
        unit: l.unit,
        status: status,
        hawlDaysElapsed: elapsed,
        daysRemaining: remaining < 0 ? 0 : remaining,
        dueOn: l.hawlStart.plusDays(rules.hawlDays),
        netBase: base,
        dueNative: due,
        remainingNative: left,
        costOfDue: due == 0
            ? null
            : _costOf(l, due, price, costCurrency, market),
        projectedDueNative: projected,
        projectedCost: projected == 0
            ? null
            : _costOf(l, projected, price, costCurrency, market),
        payment: paymentStatus(due, l.paid),
      ),
    );
  }
  return ZakahResult(
    state: state,
    nisab: nisab,
    wealth: wealth,
    lots: results,
    dueByUnit: dueByUnit,
  );
}
