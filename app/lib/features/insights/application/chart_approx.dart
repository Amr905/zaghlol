// T-105: the labelled "≈" view for charts (FR-CHT-05). A chart is always in
// one currency; this is the only way to show one combined figure over
// several, and it is display-only (T-115 owns the rule: off by default, one
// rounding per converted currency, "not included" for a currency without a
// rate). The result is an [ApproxView], never a `Money` that could be
// mistaken for a real total.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../wealth/domain/approx_view.dart';
import '../../wealth/domain/price_feed.dart';

/// Combines one chart total per currency into the approximate view.
ApproxView approxChartTotal({
  required bool enabled,
  required Iterable<Money> perCurrency,
  required Currency target,
  required FxTable rates,
  required int nowMs,
}) => buildApproxView(
  enabled: enabled,
  totals: MultiCurrencyTotal.of(perCurrency),
  target: target,
  rates: rates,
  nowMs: nowMs,
);
