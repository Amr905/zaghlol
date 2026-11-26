// T-280 (D-86): the Home "≈ money in this month" figure. Pure Dart, integer
// math only; the second place (after approx_view.dart) where currencies are
// added, and only ever as a display-only, always-approximate figure.
//
// Rules (multi-currency-hybrid-plan §2 step 5, §3):
// - total = target money in (it already holds what was exchanged INTO the
//   target, at the bank's real rate) + for each other currency the part still
//   held, `max(0, moneyIn - exchangedOut)`, converted once at the daily rate.
// - The exchanged part of a foreign currency is NOT converted and added
//   again: its target amount is already in the target money in.
// - A currency whose held part needs a rate that is missing, or whose
//   conversion overflows, gives [IncomeApproxNone]: never a partial total.
// - The bank's implied rate is carried per row for the explanation sheet
//   only; the math needs no rate for the exchanged part.
// Nothing here logs or carries amounts in errors.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'price_feed.dart';

/// One currency's month figures (all cards, current cycle).
final class IncomeApproxInput {
  const IncomeApproxInput({
    required this.moneyIn,
    required this.exchangedOut,
    this.bankRateE9,
  });

  /// Income plus exchanged in, in its own currency.
  final Money moneyIn;

  /// Given away in exchanges, same currency.
  final Money exchangedOut;

  /// The bank's implied rate (target per 1 unit, 1e-9) for what this
  /// currency exchanged into the target. Display only.
  final int? bankRateE9;

  Currency get currency => moneyIn.currency;
}

sealed class IncomeApprox {
  const IncomeApprox();
}

/// No line: not applicable (nothing foreign), or a rate is missing.
final class IncomeApproxNone extends IncomeApprox {
  const IncomeApproxNone();
}

/// One foreign currency's part of the figure.
final class IncomeApproxRow {
  const IncomeApproxRow({
    required this.currency,
    required this.held,
    required this.exchanged,
    required this.heldInTarget,
    required this.dailyRatePerUnit,
    required this.dailyRateAsOfMs,
    required this.stale,
    required this.bankRateE9,
  });

  final Currency currency;

  /// Still held this month (money in minus exchanged out, at least 0).
  final Money held;

  /// Exchanged away this month. Not converted here (already in the target).
  final Money exchanged;

  /// [held] at the daily rate, in the target; null when [held] is zero.
  final Money? heldInTarget;

  /// What one whole unit of [currency] is worth in the target at the daily
  /// rate (display); null when no rate was needed.
  final Money? dailyRatePerUnit;
  final int? dailyRateAsOfMs;
  final bool stale;
  final int? bankRateE9;
}

final class IncomeApproxLine extends IncomeApprox {
  const IncomeApproxLine({
    required this.target,
    required this.targetMoneyIn,
    required this.total,
    required this.rows,
    required this.rateAsOfMs,
    required this.stale,
    required this.usesBankRate,
  });

  final Currency target;

  /// The target's own money in (includes what was exchanged into it).
  final Money targetMoneyIn;

  /// The approximate figure, in [target]. Display only: never persist it.
  final Money total;
  final List<IncomeApproxRow> rows;

  /// Oldest daily rate used; null when no daily rate was needed.
  final int? rateAsOfMs;

  /// Any daily rate used is older than 24 h (or unverifiable).
  final bool stale;

  /// At least one row has exchanged money explained by the bank's rate.
  final bool usesBankRate;

  bool get usesDailyRate => rateAsOfMs != null;
}

/// Builds the figure. [inputs] holds one entry per currency with any
/// activity (the target's entry may be missing: it counts as zero).
IncomeApprox buildIncomeApprox({
  required Currency target,
  required Iterable<IncomeApproxInput> inputs,
  required FxTable rates,
  required int nowMs,
}) {
  Money targetIn = Money.zero(target);
  final foreign = <IncomeApproxInput>[];
  for (final i in inputs) {
    if (i.currency == target) {
      targetIn = i.moneyIn;
    } else if (i.moneyIn.minor != 0 || i.exchangedOut.minor != 0) {
      foreign.add(i);
    }
  }
  if (foreign.isEmpty) return const IncomeApproxNone();
  foreign.sort((a, b) => a.currency.code.compareTo(b.currency.code));

  try {
    var total = targetIn;
    final rows = <IncomeApproxRow>[];
    int? oldest;
    var stale = false;
    var bank = false;
    for (final i in foreign) {
      final left = i.moneyIn - i.exchangedOut;
      final held = left.isPositive ? left : Money.zero(i.currency);
      Money? inTarget;
      Money? perUnit;
      int? asOf;
      var rowStale = false;
      if (held.isPositive) {
        final r = rates.convertApprox(held, target, nowMs: nowMs);
        if (r is! Approx) return const IncomeApproxNone();
        inTarget = r.amount;
        total = total + r.amount;
        asOf = r.asOfMs;
        rowStale = r.stale;
        final unit = Money(i.currency, _pow10(i.currency.exponent));
        final u = rates.convertApprox(unit, target, nowMs: nowMs);
        perUnit = u is Approx ? u.amount : null;
        stale = stale || r.stale;
        if (asOf != null && (oldest == null || asOf < oldest)) oldest = asOf;
      }
      final hasBank = i.exchangedOut.isPositive && i.bankRateE9 != null;
      bank = bank || hasBank;
      rows.add(
        IncomeApproxRow(
          currency: i.currency,
          held: held,
          exchanged: i.exchangedOut,
          heldInTarget: inTarget,
          dailyRatePerUnit: perUnit,
          dailyRateAsOfMs: asOf,
          stale: rowStale,
          bankRateE9: hasBank ? i.bankRateE9 : null,
        ),
      );
    }
    return IncomeApproxLine(
      target: target,
      targetMoneyIn: targetIn,
      total: total,
      rows: List.unmodifiable(rows),
      rateAsOfMs: oldest,
      stale: stale,
      usesBankRate: bank,
    );
  } on MoneyOverflow {
    return const IncomeApproxNone();
  }
}

int _pow10(int n) {
  var v = 1;
  for (var k = 0; k < n; k++) {
    v *= 10;
  }
  return v;
}

/// Q2: the ≈ view turns on by itself once, when two or more currencies have
/// activity and it has not done so before.
bool shouldAutoEnableApprox({
  required int activeCurrencies,
  required bool alreadyDone,
}) => !alreadyDone && activeCurrencies >= 2;
