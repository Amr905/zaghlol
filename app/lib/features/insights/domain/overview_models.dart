// T-209 (CHARTS-V2): small models of the Overview tab: the ranked category
// rows and the upcoming dues. Pure Dart, integer minor units.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'chart_models.dart';
import 'chart_summary.dart';

/// One ranked category with the previous period's same-days amount.
final class CategoryRowData {
  const CategoryRowData({
    required this.categoryId,
    required this.amount,
    required this.previousMinor,
    required this.change,
    required this.shareBp,
    required this.count,
  });

  /// Null: uncategorized.
  final String? categoryId;
  final Money amount;

  /// The same category in the previous period (the same elapsed days).
  final int previousMinor;
  final ChartChange change;
  final int shareBp;
  final int count;
}

/// The [limit] largest categories of [donut], largest first (ties keep the
/// donut's order), each against [previous]. [limit] null keeps all.
List<CategoryRowData> rankedCategories(
  CategoryDonut donut, {
  CategoryDonut? previous,
  int? limit,
}) {
  final indexed = [for (var i = 0; i < donut.slices.length; i++) i]
    ..sort((a, b) {
      final c = donut.slices[b].amount.compareTo(donut.slices[a].amount);
      return c != 0 ? c : a.compareTo(b);
    });
  int prevOf(String? id) {
    if (previous == null) return 0;
    for (final s in previous.slices) {
      if (s.categoryId == id) return s.amount.minor;
    }
    return 0;
  }

  return [
    for (final i in (limit == null ? indexed : indexed.take(limit)))
      CategoryRowData(
        categoryId: donut.slices[i].categoryId,
        amount: donut.slices[i].amount,
        previousMinor: prevOf(donut.slices[i].categoryId),
        change: previous == null
            ? ChartChange.none
            : percentChange(
                donut.slices[i].amount.minor,
                prevOf(donut.slices[i].categoryId),
              ),
        shareBp: donut.slices[i].shareBp,
        count: donut.slices[i].count,
      ),
  ];
}

/// A subscription, bill or instalment charge still to come.
final class UpcomingDue {
  const UpcomingDue({
    required this.itemId,
    required this.name,
    required this.kind,
    required this.date,
    required this.amount,
  });

  final String itemId;
  final String name;

  /// `recurring_items.kind`.
  final String kind;
  final CivilDate date;
  final Money amount;
}

/// The next [limit] dues on or after [today], soonest first.
List<UpcomingDue> nextDues(
  List<UpcomingDue> all,
  CivilDate today, {
  int limit = 3,
}) {
  final list =
      [
        for (final d in all)
          if (d.date >= today) d,
      ]..sort((a, b) {
        final c = a.date.compareTo(b.date);
        return c != 0 ? c : a.itemId.compareTo(b.itemId);
      });
  return list.take(limit).toList();
}

/// The dues from [today] to [end] (both inclusive), summed in [currency].
Money duesUntil(
  List<UpcomingDue> all,
  CivilDate today,
  CivilDate end,
  Currency currency,
) => Money(
  currency,
  all
      .where((d) => d.date >= today && d.date <= end)
      .fold<int>(0, (a, d) => a + d.amount.minor),
);
