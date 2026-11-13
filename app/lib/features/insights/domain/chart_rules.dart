// T-105: the pure arithmetic behind the charts. Integer minor units only,
// no double anywhere (CLAUDE.md §2.4). Products go through BigInt so a large
// amount times 10000 cannot overflow a 64-bit integer. Nothing here logs.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'chart_models.dart';

/// `a * b / c`, rounded half away from zero, exact (BigInt). [c] > 0.
int mulDivRound(int a, int b, int c) {
  if (c <= 0) throw ArgumentError('divisor must be positive');
  final neg = (a < 0) != (b < 0);
  final num =
      (BigInt.from(a).abs() * BigInt.from(b).abs()) +
      BigInt.from(c) ~/ BigInt.two;
  final q = (num ~/ BigInt.from(c)).toInt();
  return neg ? -q : q;
}

/// (current - base) / base in basis points, rounded half away from zero;
/// null when [base] is zero.
int? deltaBp(int current, int base) =>
    base == 0 ? null : mulDivRound(current - base, 10000, base.abs());

/// Basis-point shares of [amounts] that add up to exactly 10000 (largest
/// remainder; ties go to the earlier entry). All zero when the total is
/// zero. Amounts must not be negative.
List<int> sharesBp(List<int> amounts) {
  final total = amounts.fold<int>(0, (a, b) => a + b);
  if (total <= 0) return List.filled(amounts.length, 0);
  final big = BigInt.from(total);
  final floors = <int>[];
  final rems = <BigInt>[];
  for (final a in amounts) {
    final p = BigInt.from(a) * BigInt.from(10000);
    floors.add((p ~/ big).toInt());
    rems.add(p % big);
  }
  var left = 10000 - floors.fold<int>(0, (a, b) => a + b);
  final order = List.generate(amounts.length, (i) => i)
    ..sort((x, y) {
      final c = rems[y].compareTo(rems[x]);
      return c != 0 ? c : x.compareTo(y);
    });
  for (final i in order) {
    if (left <= 0) break;
    floors[i]++;
    left--;
  }
  return floors;
}

/// The middle value; for an even count the integer mean of the two middle
/// values (rounded down). [values] must not be empty.
int medianMinor(List<int> values) {
  if (values.isEmpty) throw ArgumentError('no values');
  final s = [...values]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) ~/ 2;
}

/// ISO weekday 1 (Monday) .. 7 (Sunday) of a local epoch day. 1970-01-01
/// was a Thursday.
int isoWeekday(int epochDay) => ((epochDay + 3) % 7 + 7) % 7 + 1;

/// The cost over twelve months of one charge every [cadence] (BR-SUB-02:
/// monthly x12). Weekly x52; a custom cycle of N days is amount x 365 / N,
/// rounded half up.
Money annualCost(Money amount, RecurrenceCadence cadence, {int? days}) {
  switch (cadence) {
    case RecurrenceCadence.monthly:
      return amount.times(12);
    case RecurrenceCadence.yearly:
      return amount;
    case RecurrenceCadence.weekly:
      return amount.times(52);
    case RecurrenceCadence.customDays:
      if (days == null || days < 1) throw ArgumentError('invalid cadence');
      return Money(amount.currency, mulDivRound(amount.minor, 365, days));
  }
}

/// Straight-line projection of [soFar] after [elapsed] of [length] days.
Money projectLinear(Money soFar, int elapsed, int length) {
  if (elapsed < 1) throw ArgumentError('elapsed must be at least 1');
  return Money(soFar.currency, mulDivRound(soFar.minor, length, elapsed));
}

/// One purchase of a merchant, for [personalInflation].
final class PricePoint {
  const PricePoint(this.merchant, this.monthIndex, this.amountMinor);
  final String merchant;

  /// `year * 12 + month - 1`.
  final int monthIndex;
  final int amountMinor;
}

/// The personal inflation index (chart 12): per repeated merchant (seen in
/// at least two months), the median purchase of each month against the
/// median of its first month; per month the median of those ratios, in basis
/// points (10000 = base). A month is reported when at least [minMerchants]
/// merchants have a price in it and in their base month. Returns an empty
/// list when fewer than [minMerchants] merchants repeat.
List<InflationPoint> personalInflation(
  Iterable<PricePoint> points, {
  int minMerchants = ChartThresholds.inflationMinMerchants,
}) {
  final byMerchant = <String, Map<int, List<int>>>{};
  for (final p in points) {
    if (p.amountMinor <= 0) continue;
    ((byMerchant[p.merchant] ??= {})[p.monthIndex] ??= []).add(p.amountMinor);
  }
  final prices = <String, Map<int, int>>{};
  byMerchant.forEach((m, months) {
    if (months.length < 2) return;
    prices[m] = {for (final e in months.entries) e.key: medianMinor(e.value)};
  });
  if (prices.length < minMerchants) return const [];
  final ratiosByMonth = <int, List<int>>{};
  for (final months in prices.values) {
    final keys = months.keys.toList()..sort();
    final base = months[keys.first]!;
    for (final k in keys) {
      (ratiosByMonth[k] ??= []).add(mulDivRound(months[k]!, 10000, base));
    }
  }
  final out = <InflationPoint>[];
  final keys = ratiosByMonth.keys.toList()..sort();
  for (final k in keys) {
    final r = ratiosByMonth[k]!;
    if (r.length < minMerchants) continue;
    out.add(
      InflationPoint(
        year: k ~/ 12,
        month: k % 12 + 1,
        indexBp: medianMinor(r),
        merchants: r.length,
      ),
    );
  }
  return out;
}

/// The due dates of an installment (or any recurring item) that fall in
/// the months from [first] (year, month) for [months] months, stepping
/// from [next] by [cadence]. At most [remaining] charges (null: no limit).
/// A due date before the first month's start is still owed: it is reported
/// flagged overdue (the caller shows it in the first month).
List<({CivilDate date, bool overdue})> dueDatesInWindow({
  required CivilDate next,
  required RecurrenceCadence cadence,
  required int? dueDay,
  required int? days,
  required int? remaining,
  required int firstYear,
  required int firstMonth,
  required int months,
}) {
  final start = CivilDate(firstYear, firstMonth, 1);
  final endMonth = firstMonth - 1 + months;
  final ey = firstYear + endMonth ~/ 12;
  final em = endMonth % 12 + 1;
  final end = CivilDate(ey, em, 1); // exclusive
  final out = <({CivilDate date, bool overdue})>[];
  var d = next;
  var left = remaining;
  var guard = 0;
  while (d < end && (left == null || left > 0) && guard++ < 2000) {
    if (d < start) {
      out.add((date: d, overdue: true));
    } else {
      out.add((date: d, overdue: false));
    }
    if (left != null) left--;
    d = advanceDue(d, cadence: cadence, dueDay: dueDay, days: days);
  }
  return out;
}
