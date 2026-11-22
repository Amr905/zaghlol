// T-210 (CHARTS-V2): pure models of the Categories tab: the sort orders and
// the stacked share strip. Integer minor units and basis points only.

import 'chart_models.dart';
import 'overview_models.dart';

enum CategorySort { amount, change }

/// [rows] ordered by [sort]; ties are broken by name, then id, so the order
/// is stable. [nameOf] gives the display name of a category id (null =
/// uncategorized).
///
/// amount: largest first. change: the largest absolute move against the
/// previous period first (a category with no previous amount moves by its
/// whole amount).
List<CategoryRowData> sortCategoryRows(
  List<CategoryRowData> rows,
  CategorySort sort,
  String Function(String? id) nameOf,
) {
  int move(CategoryRowData r) => (r.amount.minor - r.previousMinor).abs();
  final out = [...rows];
  out.sort((a, b) {
    final primary = switch (sort) {
      CategorySort.amount => b.amount.minor.compareTo(a.amount.minor),
      CategorySort.change => move(b).compareTo(move(a)),
    };
    if (primary != 0) return primary;
    final byName = nameOf(a.categoryId)
        .toLowerCase()
        .compareTo(nameOf(b.categoryId).toLowerCase());
    if (byName != 0) return byName;
    return (a.categoryId ?? '').compareTo(b.categoryId ?? '');
  });
  return out;
}

/// One segment of the share strip. [categoryId] is null for uncategorized
/// and for [isOther] (the merged tail).
final class ShareSegment {
  const ShareSegment({
    required this.categoryId,
    required this.shareBp,
    this.isOther = false,
  });
  final String? categoryId;
  final int shareBp;
  final bool isOther;
}

/// The strip of [rows] (largest first): at most [maxNamed] named segments and
/// one "Other" for the rest. Shares are basis points that add up to exactly
/// 10000 (largest remainder; ties go to the earlier segment). Empty when the
/// total is zero.
List<ShareSegment> shareStrip(List<CategoryRowData> rows, {int maxNamed = 6}) {
  final pos = rows.where((r) => r.amount.minor > 0).toList();
  final total = pos.fold<int>(0, (a, r) => a + r.amount.minor);
  if (total <= 0) return const [];
  final byAmount = [...pos]
    ..sort((a, b) => b.amount.minor.compareTo(a.amount.minor));
  final named = byAmount.length > maxNamed
      ? byAmount.take(maxNamed).toList()
      : byAmount;
  final restMinor = byAmount
      .skip(named.length)
      .fold<int>(0, (a, r) => a + r.amount.minor);
  final amounts = [
    for (final r in named) r.amount.minor,
    ?(restMinor > 0 ? restMinor : null),
  ];
  final floors = [for (final a in amounts) a * 10000 ~/ total];
  final rem = [for (final a in amounts) a * 10000 % total];
  var left = 10000 - floors.fold<int>(0, (a, b) => a + b);
  final order = [for (var i = 0; i < amounts.length; i++) i]
    ..sort((a, b) {
      final c = rem[b].compareTo(rem[a]);
      return c != 0 ? c : a.compareTo(b);
    });
  for (final i in order) {
    if (left <= 0) break;
    floors[i]++;
    left--;
  }
  return [
    for (var i = 0; i < amounts.length; i++)
      ShareSegment(
        categoryId: i < named.length ? named[i].categoryId : null,
        shareBp: floors[i],
        isOther: i >= named.length,
      ),
  ];
}

/// One bar of the selected category's trend.
final class CategoryTrendBar {
  const CategoryTrendBar({
    required this.period,
    required this.minor,
    required this.inProgress,
  });
  final ChartPeriod period;
  final int minor;

  /// The period is still open (it holds today).
  final bool inProgress;
}
