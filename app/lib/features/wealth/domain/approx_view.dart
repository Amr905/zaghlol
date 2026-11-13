// T-115: the "≈" combined view (FR-CUR-04/05, A-54/60/62). The ONLY place
// where amounts of different currencies are added together.
//
// Design note (C3):
// - Input: per-currency totals ([MultiCurrencyTotal]), a target currency and
//   the stored [FxTable]. Output: [ApproxView], display-only. It is never
//   stored, never written back into a transaction or total, and its figure
//   is an [ApproxFigure], not a `Money` that could be mistaken for a real
//   amount.
// - Off (the default, A-54): [ApproxViewOff] has no figure at all, so a UI
//   cannot render a combined number by accident.
// - Rounding: each foreign currency's total is converted with
//   [FxTable.convertApprox] (exact integers on `rate_e9`, ONE half-even
//   rounding to the target's minor unit, T-112). The converted amounts and
//   the target-currency amount are then summed exactly. So there is one
//   rounding per converted currency, never a rounding of a rounding.
// - Rate date: the OLDEST rate used (the honest bound), plus the stale flag
//   of any rate used (EC-34).
// - A currency without a rate path is listed in [ApproxFigure.excluded] and
//   not counted; nothing is guessed (EC-35/56). Zero totals need no rate
//   and are neither converted nor listed.
// - Nothing here logs or carries amounts in errors.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'price_feed.dart';

sealed class ApproxView {
  const ApproxView();
}

/// The view is switched off: no combined figure exists.
final class ApproxViewOff extends ApproxView {
  const ApproxViewOff();
}

/// The view is on. [figure] is null when no currency could be included
/// (for example no rate for anything); the UI then shows only the
/// not-included note.
final class ApproxViewOn extends ApproxView {
  const ApproxViewOn({
    required this.target,
    required this.figure,
    required this.excluded,
    required this.rateAsOfMs,
    required this.stale,
    required this.approximate,
  });

  final Currency target;

  /// The combined amount in [target], or null when nothing was included.
  final ApproxFigure? figure;

  /// Currencies with a non-zero total but no rate: "not included" (sorted
  /// by code).
  final List<Currency> excluded;

  /// Oldest rate used; null when no rate was needed.
  final int? rateAsOfMs;

  /// Any rate used is stale (EC-34).
  final bool stale;

  /// True when at least one currency was converted, or when any currency is
  /// [excluded] (the figure is then partial). When false the figure is the
  /// exact target-currency total and needs no "≈" label.
  final bool approximate;
}

/// A combined amount. Deliberately not a `Money`.
final class ApproxFigure {
  const ApproxFigure(this.amount);

  /// In the target currency. Display only; never persist or add to real
  /// totals.
  final Money amount;
}

/// Builds the ≈ view for [totals]. When [enabled] is false it returns
/// [ApproxViewOff] without touching [rates].
///
/// Throws [MoneyOverflow] if a conversion or the final sum is out of range.
ApproxView buildApproxView({
  required bool enabled,
  required MultiCurrencyTotal totals,
  required Currency target,
  required FxTable rates,
  required int nowMs,
}) {
  if (!enabled) return const ApproxViewOff();
  final parts = <Money>[];
  final excluded = <Currency>[];
  int? oldest;
  var stale = false;
  var approximate = false;
  for (final currency in totals.nonZero().currencies) {
    final result = rates.convertApprox(totals[currency], target, nowMs: nowMs);
    switch (result) {
      case MissingRate():
        excluded.add(currency);
      case Approx():
        parts.add(result.amount);
        if (!result.identity) {
          approximate = true;
          stale = stale || result.stale;
          final at = result.asOfMs;
          if (at != null && (oldest == null || at < oldest)) oldest = at;
        }
    }
  }
  final figure = parts.isEmpty && excluded.isNotEmpty
      ? null
      : ApproxFigure(MultiCurrencyTotal.of(parts)[target]);
  return ApproxViewOn(
    target: target,
    figure: figure,
    excluded: excluded,
    rateAsOfMs: oldest,
    stale: stale,
    approximate: approximate || excluded.isNotEmpty,
  );
}
