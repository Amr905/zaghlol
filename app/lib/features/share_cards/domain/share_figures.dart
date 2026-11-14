// T-117 (FR-SHR-01..03): the figures behind each share template. Pure
// integer maths; a figure always carries its percentage, and the amount only
// feeds the card when the user turns "Show amounts" on.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../insights/domain/chart_models.dart';

enum ShareTemplate { savings, delivery, budget }

/// The category id the delivery template reads from the month-vs-average chart.
const String shareDeliveryCategoryId = 'delivery';

final class ShareFigure {
  const ShareFigure({
    required this.template,
    required this.percentBp,
    required this.amount,
  });

  final ShareTemplate template;

  /// Basis points (1/100 of a percent); always > 0.
  final int percentBp;

  /// The same win in money, in one currency. Hidden unless opted in.
  final Money amount;

  /// Whole percent, half up (2750 -> 28).
  int get percent => (percentBp + 50) ~/ 100;
}

/// Builds the templates that have data; the rest are left out (S-73).
List<ShareFigure> buildShareFigures({
  ChartResult<FiftyThirtyTwenty>? rule,
  ChartResult<BurnCurve>? burn,
  ChartResult<MonthVsAverage>? vsAverage,
}) {
  final out = <ShareFigure>[];
  if (rule is ChartReady<FiftyThirtyTwenty>) {
    final r = rule.data;
    if (r.income.isPositive && r.savings.isPositive) {
      out.add(
        ShareFigure(
          template: ShareTemplate.savings,
          percentBp: (r.savings.minor * 10000) ~/ r.income.minor,
          amount: r.savings,
        ),
      );
    }
  }
  if (vsAverage is ChartReady<MonthVsAverage>) {
    for (final c in vsAverage.data.byCategory) {
      if (c.categoryId == shareDeliveryCategoryId &&
          c.average.isPositive &&
          c.current < c.average) {
        final cut = c.average - c.current;
        out.add(
          ShareFigure(
            template: ShareTemplate.delivery,
            percentBp: (cut.minor * 10000) ~/ c.average.minor,
            amount: cut,
          ),
        );
      }
    }
  }
  if (burn is ChartReady<BurnCurve>) {
    final b = burn.data;
    final budget = b.budget;
    if (budget != null &&
        budget.isPositive &&
        b.cumulative.isNotEmpty &&
        b.cumulative.last < budget) {
      final under = budget - b.cumulative.last;
      out.add(
        ShareFigure(
          template: ShareTemplate.budget,
          percentBp: (under.minor * 10000) ~/ budget.minor,
          amount: under,
        ),
      );
    }
  }
  return out.where((f) => f.percentBp >= 100).toList();
}
