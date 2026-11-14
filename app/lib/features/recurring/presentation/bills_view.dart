// T-102: pure view model for S-24 (Bills & installments). Built from the
// stored items and local today; no I/O. Money stays per currency: nothing is
// summed across currencies.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/money_columns.dart';
import '../data/recurring_repository.dart';

enum BillTiming { overdue, today, upcoming }

class BillRowView {
  const BillRowView({
    required this.id,
    required this.name,
    required this.kind,
    required this.amount,
    required this.due,
    required this.daysUntil,
    required this.timing,
    this.paidCount = 0,
    this.totalCount,
  });

  final String id;
  final String name;
  final String kind;
  final Money amount;
  final CivilDate due;

  /// Negative when overdue.
  final int daysUntil;
  final BillTiming timing;
  final int paidCount;
  final int? totalCount;

  bool get hasPlan => totalCount != null;
  int get index => paidCount + 1;
  bool get isLast => totalCount != null && paidCount + 1 >= totalCount!;

  /// A card due is paid only by money arriving on the card.
  bool get canMarkPaid => kind != RecurringKind.cardDue;
}

class SuggestionView {
  const SuggestionView({
    required this.id,
    required this.name,
    required this.amount,
  });
  final String id;
  final String name;
  final Money amount;
}

class SubscriptionRowView {
  const SubscriptionRowView({
    required this.id,
    required this.name,
    required this.monthly,
    required this.yearly,
  });
  final String id;
  final String name;
  final Money monthly;
  final Money yearly;
}

class CurrencyTotal {
  const CurrencyTotal({required this.monthly, required this.yearly});
  final Money monthly;
  final Money yearly;
}

class BillsViewData {
  const BillsViewData({
    required this.suggestions,
    required this.upcoming,
    required this.subscriptions,
    required this.subTotals,
    required this.dueThisMonth,
  });

  final List<SuggestionView> suggestions;
  final List<BillRowView> upcoming;
  final List<SubscriptionRowView> subscriptions;
  final List<CurrencyTotal> subTotals;

  /// Per currency, in first-seen order.
  final List<Money> dueThisMonth;

  bool get isEmpty =>
      suggestions.isEmpty && upcoming.isEmpty && subscriptions.isEmpty;
}

int _roundDiv(int a, int b) => (a * 2 + b) ~/ (b * 2);

/// Yearly cost of one charge of [m] at [cadence].
Money yearlyOf(Money m, String cadence, int? cadenceDays) {
  final minor = switch (cadence) {
    'monthly' => m.minor * 12,
    'weekly' => m.minor * 52,
    'custom_days' => _roundDiv(m.minor * 365, cadenceDays ?? 30),
    _ => m.minor,
  };
  return Money(m.currency, minor);
}

Money monthlyOf(Money m, String cadence, int? cadenceDays) {
  if (cadence == 'monthly') return m;
  final y = yearlyOf(m, cadence, cadenceDays);
  return Money(y.currency, _roundDiv(y.minor, 12));
}

BillsViewData buildBillsView(List<RecurringItemRow> items, CivilDate today) {
  final suggestions = <SuggestionView>[];
  final upcoming = <BillRowView>[];
  final subs = <SubscriptionRowView>[];
  final totals = <Currency, (int, int)>{};
  final due = <Currency, int>{};
  for (final r in items) {
    if (r.status == RecurringStatus.suggested) {
      suggestions.add(SuggestionView(id: r.id, name: r.name, amount: r.amount));
      continue;
    }
    if (r.status != RecurringStatus.active) continue;
    final next = CivilDate.tryParse(r.nextDueDate ?? '');
    if (next != null) {
      final days = next.epochDay - today.epochDay;
      upcoming.add(
        BillRowView(
          id: r.id,
          name: r.name,
          kind: r.kind,
          amount: r.amount,
          due: next,
          daysUntil: days,
          timing: days < 0
              ? BillTiming.overdue
              : days == 0
              ? BillTiming.today
              : BillTiming.upcoming,
          paidCount: r.paidCount,
          totalCount: r.totalCount,
        ),
      );
      final thisMonth =
          (next.year == today.year && next.month == today.month) || days < 0;
      if (thisMonth) {
        final cur = r.amount.currency;
        due[cur] = (due[cur] ?? 0) + r.amount.minor;
      }
    }
    if (r.kind == RecurringKind.subscription) {
      final m = monthlyOf(r.amount, r.cadence, r.cadenceDays);
      final y = yearlyOf(r.amount, r.cadence, r.cadenceDays);
      subs.add(
        SubscriptionRowView(id: r.id, name: r.name, monthly: m, yearly: y),
      );
      final t = totals[m.currency] ?? (0, 0);
      totals[m.currency] = (t.$1 + m.minor, t.$2 + y.minor);
    }
  }
  upcoming.sort((a, b) {
    final c = a.due.epochDay.compareTo(b.due.epochDay);
    return c != 0 ? c : a.id.compareTo(b.id);
  });
  return BillsViewData(
    suggestions: suggestions,
    upcoming: upcoming,
    subscriptions: subs,
    subTotals: [
      for (final e in totals.entries)
        CurrencyTotal(
          monthly: Money(e.key, e.value.$1),
          yearly: Money(e.key, e.value.$2),
        ),
    ],
    dueThisMonth: [for (final e in due.entries) Money(e.key, e.value)],
  );
}
