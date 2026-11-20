// T-096: pure rules for recurring money (domain-algorithms §6, BR-SUB-01..03,
// FR-SUB-05). No Flutter, no database. Amounts are Money (integer minor
// units, one currency per comparison); dates are local civil dates
// (CivilDate), so no zone arithmetic happens here. T-196 (D-72): a chain that
// repeats every 1, 3, 6 or 12 months is returned as a detection and the app
// layer adds it as an active bill (with an undo); BR-SUB-01's confirm-first
// rule no longer applies to these cadences.

import '../budget/civil_date.dart';
import '../mascot_rules/mascot_rules.dart' show categoryCode;
import '../money/money.dart';

/// Chain rule (BR-SUB-01): consecutive monthly charges 25..35 days apart.
const int subscriptionMinGapDays = 25;
const int subscriptionMaxGapDays = 35;

/// T-196: a chain whose next due date is more than this many days in the
/// past has stopped (cancelled plan) and is not added.
const int staleChainGraceDays = 10;

/// Chain rule: each charge within 10% of the one before it.
const int subscriptionAmountToleranceBp = 1000;

/// Auto-mark rule (FR-SUB-05): amount within 2%, date within 5 days.
const int autoMarkAmountToleranceBp = 200;
const int autoMarkWindowDays = 5;

/// Default reminder lead (BR-SUB-03) and the local time reminders fire.
const int defaultReminderDays = 3;
const int reminderMinuteOfDay = 10 * 60;

/// A posted expense, reduced to what detection needs.
final class RecurringCharge {
  const RecurringCharge({
    required this.id,
    required this.merchantNorm,
    required this.accountId,
    required this.amount,
    required this.date,
    this.displayName,
    this.categoryId,
  });

  final String id;

  /// Normalized merchant key (`[a-z0-9 ]`, see `merchant_norm`).
  final String merchantNorm;
  final String accountId;

  /// Positive, in the charge's own currency.
  final Money amount;

  /// Local civil date of the charge.
  final CivilDate date;
  final String? displayName;

  /// The charge's category id (`sys:rent` or `rent`), when it has one.
  final String? categoryId;
}

/// A detected chain (T-196): the app layer adds it as an active bill.
final class RecurringChain {
  const RecurringChain({
    required this.merchantNorm,
    required this.accountId,
    required this.name,
    required this.cadence,
    required this.amount,
    required this.annualCost,
    required this.dueDay,
    required this.nextDue,
    required this.chargeIds,
  });

  /// monthly, quarterly, semiAnnual or yearly.
  final RecurrenceCadence cadence;

  final String merchantNorm;
  final String accountId;
  final String name;

  /// The latest charge: the expected amount of one cycle.
  final Money amount;

  /// amount × cycles per year (BR-SUB-02: 12, 4, 2 or 1).
  final Money annualCost;
  final int dueDay;

  /// The latest charge's date plus one cycle (day clamped to month end).
  final CivilDate nextDue;

  /// The chain, oldest first.
  final List<String> chargeIds;
}

final RegExp _normShape = RegExp(r'^[a-z0-9]+( [a-z0-9]+)*$');

/// True when [norm] is storable in `recurring_items.merchant_norm`.
bool isStorableMerchantNorm(String norm) =>
    norm.length <= 64 && _normShape.hasMatch(norm);

/// |a − b| ≤ [bp]/10000 × [reference], integers only.
bool withinBp(int a, int b, int reference, int bp) {
  if (reference < 0) return false;
  final diff = (a - b).abs();
  return BigInt.from(diff) * BigInt.from(10000) <=
      BigInt.from(reference) * BigInt.from(bp);
}

/// One detectable cadence: the gap window between consecutive charges and
/// the shortest chain that counts (T-196). The windows do not overlap, so the
/// latest gap decides the cadence.
final class _Window {
  const _Window(this.cadence, this.minGap, this.maxGap, this.minChain);
  final RecurrenceCadence cadence;
  final int minGap;
  final int maxGap;
  final int minChain;
}

const List<_Window> _windows = [
  _Window(
    RecurrenceCadence.monthly,
    subscriptionMinGapDays,
    subscriptionMaxGapDays,
    3,
  ),
  _Window(RecurrenceCadence.quarterly, 84, 97, 3),
  _Window(RecurrenceCadence.semiAnnual, 176, 189, 2),
  _Window(RecurrenceCadence.yearly, 360, 371, 2),
];

_Window? _windowFor(int gap) {
  for (final w in _windows) {
    if (gap >= w.minGap && gap <= w.maxGap) return w;
  }
  return null;
}

/// Categories where the same merchant repeating is coincidence, not a bill
/// (D-72, PO 2026-11-20): shopping trips, eating out, rides, fuel, cash
/// withdrawals, transfers and income. Rent, utilities, bills, installments,
/// education, insurance and subscriptions are NOT here: they must auto-add.
const Set<String> nonRecurringCategoryIds = {
  'groceries',
  'dining',
  'delivery',
  'food_delivery',
  'transport',
  'ride_hailing',
  'fuel',
  'cash',
  'cash_withdrawal',
  'instapay',
  'income',
};

bool _isExcluded(String? categoryId, Set<String> excluded) =>
    categoryId != null &&
    (excluded.contains(categoryId) ||
        excluded.contains(categoryCode(categoryId)));

/// Finds charges that repeat every 1, 3, 6 or 12 months (BR-SUB-01 widened
/// by D-72). Charges are grouped by (merchant, account, currency), so a chain
/// never mixes currencies or accounts, and sorted by date; the result is the
/// chain that ends at the group's latest charge: gaps inside the window of
/// the latest gap and amounts within 10% of the previous charge. A chain
/// needs 3 charges for monthly and 3-month, 2 for 6- and 12-month. A longer
/// old chain that has since stopped, or one whose next due date is more than
/// [staleChainGraceDays] before [today], yields nothing. Charges in a
/// [nonRecurringCategoryIds] category are ignored.
///
/// Groups whose key is in [exclude] (`merchant|account|currency`, see
/// [recurringKey]) are skipped: that is how an existing, dismissed or undone
/// item stays quiet; an entry with an empty account (`merchant||currency`)
/// blocks that merchant and currency on every account. Zero amounts and
/// unstorable merchant keys are ignored. Output order is by merchant,
/// account, currency.
List<RecurringChain> detectRecurring(
  Iterable<RecurringCharge> charges, {
  required CivilDate today,
  Set<String> exclude = const {},
  Set<String> excludedCategoryIds = nonRecurringCategoryIds,
}) {
  final groups = <String, List<RecurringCharge>>{};
  for (final c in charges) {
    if (!c.amount.isPositive ||
        !isStorableMerchantNorm(c.merchantNorm) ||
        _isExcluded(c.categoryId, excludedCategoryIds)) {
      continue;
    }
    groups
        .putIfAbsent(
          recurringKey(c.merchantNorm, c.accountId, c.amount.currency.code),
          () => [],
        )
        .add(c);
  }
  final keys = groups.keys.toList()..sort();
  final out = <RecurringChain>[];
  for (final key in keys) {
    final list = groups[key]!
      ..sort((a, b) {
        final d = a.date.compareTo(b.date);
        return d != 0 ? d : a.id.compareTo(b.id);
      });
    final head = list.last;
    if (exclude.contains(key) ||
        exclude.contains(
          recurringKey(head.merchantNorm, '', head.amount.currency.code),
        )) {
      continue;
    }
    if (list.length < 2) continue;
    final w = _windowFor(
      list[list.length - 1].date.difference(list[list.length - 2].date),
    );
    if (w == null) continue;
    // Walk backwards from the latest charge while the chain holds.
    var start = list.length - 1;
    while (start > 0) {
      final prev = list[start - 1];
      final cur = list[start];
      final gap = cur.date.difference(prev.date);
      if (gap < w.minGap ||
          gap > w.maxGap ||
          !withinBp(
            cur.amount.minor,
            prev.amount.minor,
            prev.amount.minor,
            subscriptionAmountToleranceBp,
          )) {
        break;
      }
      start--;
    }
    final chain = list.sublist(start);
    if (chain.length < w.minChain) continue;
    final last = chain.last;
    final anchor = _anchorDay(chain);
    final next = advanceDue(last.date, cadence: w.cadence, dueDay: anchor);
    if (next.difference(today) < -staleChainGraceDays) continue;
    out.add(
      RecurringChain(
        merchantNorm: last.merchantNorm,
        accountId: last.accountId,
        name: _name(last.displayName, last.merchantNorm),
        cadence: w.cadence,
        amount: last.amount,
        annualCost: last.amount.times(12 ~/ w.cadence.monthsPerCycle!),
        dueDay: anchor,
        nextDue: next,
        chargeIds: [for (final c in chain) c.id],
      ),
    );
  }
  return out;
}

/// FU-143: the anchor day of a chain is its most common day of month (ties
/// go to the later day), so a charge on the 31st that landed on the 28th in
/// February does not anchor the item to 28 for good.
int _anchorDay(List<RecurringCharge> chain) {
  final counts = <int, int>{};
  for (final c in chain) {
    counts.update(c.date.day, (n) => n + 1, ifAbsent: () => 1);
  }
  var best = chain.last.date.day;
  for (final e in counts.entries) {
    final b = counts[best]!;
    if (e.value > b || (e.value == b && e.key > best)) best = e.key;
  }
  return best;
}

String recurringKey(String merchantNorm, String accountId, String currency) =>
    '$merchantNorm|$accountId|$currency';

String _name(String? display, String norm) {
  final raw = (display ?? '').trim();
  final base = raw.isEmpty ? norm : raw;
  final runes = base.runes.toList();
  final cut = runes.length > 60 ? String.fromCharCodes(runes.take(60)) : base;
  // The column refuses NUL.
  return cut.replaceAll('\u0000', '');
}

enum RecurrenceCadence {
  monthly,
  quarterly,
  semiAnnual,
  yearly,
  weekly,
  customDays;

  /// Calendar months between two charges; null for weekly and custom days.
  int? get monthsPerCycle => switch (this) {
    monthly => 1,
    quarterly => 3,
    semiAnnual => 6,
    yearly => 12,
    weekly || customDays => null,
  };

  /// The stored value of `recurring_items.cadence`.
  String get code => switch (this) {
    monthly => 'monthly',
    quarterly => 'quarterly',
    semiAnnual => 'semi_annual',
    yearly => 'yearly',
    weekly => 'weekly',
    customDays => 'custom_days',
  };

  /// The cadence stored as [code]; null for an unknown value.
  static RecurrenceCadence? fromCode(String code) {
    for (final c in values) {
      if (c.code == code) return c;
    }
    return null;
  }
}

/// The due date after [from] (the date just paid or charged). Monthly,
/// quarterly, semi-annual and yearly keep the anchor day [dueDay] and clamp it to short months
/// (due day 29..31 → Feb 28/29, Apr 30). [customDays] needs [days] ≥ 1.
CivilDate advanceDue(
  CivilDate from, {
  required RecurrenceCadence cadence,
  int? dueDay,
  int? days,
}) {
  switch (cadence) {
    case RecurrenceCadence.weekly:
      return from.plusDays(7);
    case RecurrenceCadence.customDays:
      if (days == null || days < 1) throw ArgumentError('invalid cadence');
      return from.plusDays(days);
    case RecurrenceCadence.monthly:
    case RecurrenceCadence.quarterly:
    case RecurrenceCadence.semiAnnual:
    case RecurrenceCadence.yearly:
      final months = cadence.monthsPerCycle!;
      final index = from.year * 12 + (from.month - 1) + months;
      return _clamped(index ~/ 12, index % 12 + 1, dueDay ?? from.day);
  }
}

CivilDate _clamped(int y, int m, int day) {
  final dim = CivilDate.daysInMonth(y, m);
  return CivilDate(y, m, day > dim ? dim : day);
}

/// The first date on or after [today] whose day-of-month is [dueDay]
/// (clamped to the month's length). Used for a card's statement due day.
CivilDate nextDueOnOrAfter(CivilDate today, int dueDay) {
  if (dueDay < 1 || dueDay > 31) throw ArgumentError('invalid due day');
  final thisMonth = _clamped(today.year, today.month, dueDay);
  if (thisMonth >= today) return thisMonth;
  return advanceDue(
    thisMonth,
    cadence: RecurrenceCadence.monthly,
    dueDay: dueDay,
  );
}

/// An active item, reduced to what matching needs.
final class DueItem {
  const DueItem({
    required this.id,
    required this.amount,
    required this.dueDate,
    this.merchantNorm,
    this.accountId,
    this.cardDue = false,
  });

  final String id;

  /// A card due: only money coming into the card account pays it.
  final bool cardDue;

  /// Expected amount. Zero means "unknown" (a card statement before its
  /// amount is known): any positive same-currency payment then matches, on
  /// the account rule only.
  final Money amount;
  final CivilDate dueDate;
  final String? merchantNorm;
  final String? accountId;
}

/// A payment candidate not yet linked to an occurrence: an `expense` or
/// `transfer_out` (or, for card dues, a `transfer_in`).
final class PaymentCandidate {
  const PaymentCandidate({
    required this.id,
    required this.amount,
    required this.date,
    this.merchantNorm,
    this.accountId,
    this.inbound = false,
  });

  final String id;

  /// True for a `transfer_in` (money into the account).
  final bool inbound;
  final Money amount;
  final CivilDate date;
  final String? merchantNorm;
  final String? accountId;
}

/// FR-SUB-05: the candidate that pays [item], or null. A candidate matches
/// when the merchant keys are equal (or, for an item without a merchant key,
/// the accounts are equal), the currency is the same, the amount is within
/// 2% and the date within 5 days of the due date. Closest date wins, then
/// closest amount, then the smaller id, so the result never depends on input
/// order. Never matches across currencies.
PaymentCandidate? matchPayment(
  DueItem item,
  Iterable<PaymentCandidate> candidates,
) {
  PaymentCandidate? best;
  (int, int, String)? bestKey;
  for (final c in candidates) {
    if (c.amount.currency != item.amount.currency || !c.amount.isPositive) {
      continue;
    }
    // A card due is paid only by inbound money; others only by outbound.
    if (item.cardDue != c.inbound) continue;
    final byMerchant = item.merchantNorm != null;
    final identity = byMerchant
        ? c.merchantNorm == item.merchantNorm
        : (item.accountId != null && c.accountId == item.accountId);
    if (!identity) continue;
    final days = c.date.difference(item.dueDate).abs();
    if (days > autoMarkWindowDays) continue;
    final unknownAmount = item.amount.isZero;
    if (!unknownAmount &&
        !withinBp(
          c.amount.minor,
          item.amount.minor,
          item.amount.minor,
          autoMarkAmountToleranceBp,
        )) {
      continue;
    }
    if (unknownAmount && byMerchant) continue;
    final key = (days, (c.amount.minor - item.amount.minor).abs(), c.id);
    if (bestKey == null || _less(key, bestKey)) {
      best = c;
      bestKey = key;
    }
  }
  return best;
}

bool _less((int, int, String) a, (int, int, String) b) {
  if (a.$1 != b.$1) return a.$1 < b.$1;
  if (a.$2 != b.$2) return a.$2 < b.$2;
  return a.$3.compareTo(b.$3) < 0;
}

/// The result of paying one occurrence.
final class PaidProgress {
  const PaidProgress({
    required this.paidCount,
    required this.completed,
    required this.nextDue,
  });

  final int paidCount;

  /// True when a counted item (installment, gameya) has reached its total.
  final bool completed;

  /// The next due date; null when [completed].
  final CivilDate? nextDue;
}

/// Counts one payment and moves the due date on (installments with counts,
/// gameya). [totalCount] null means open-ended.
PaidProgress progressAfterPayment({
  required int paidCount,
  required int? totalCount,
  required CivilDate dueDate,
  required RecurrenceCadence cadence,
  int? dueDay,
  int? cadenceDays,
}) {
  final paid = paidCount + 1;
  if (totalCount != null && paid >= totalCount) {
    return PaidProgress(paidCount: totalCount, completed: true, nextDue: null);
  }
  return PaidProgress(
    paidCount: paid,
    completed: false,
    nextDue: advanceDue(
      dueDate,
      cadence: cadence,
      dueDay: dueDay,
      days: cadenceDays,
    ),
  );
}

/// BR-SUB-03: should the due reminder fire now? From the reminder day at
/// 10:00 local until the due date itself, for an unpaid occurrence. The
/// notifications service dedupes per (item, due date), so asking again is
/// safe. [localMinuteOfDay] is minutes since local midnight.
bool reminderIsDue({
  required CivilDate dueDate,
  required int reminderDays,
  required CivilDate localToday,
  required int localMinuteOfDay,
}) {
  final from = dueDate.plusDays(-reminderDays);
  if (localToday < from || localToday > dueDate) return false;
  if (localToday == from && localMinuteOfDay < reminderMinuteOfDay) {
    return false;
  }
  return true;
}
