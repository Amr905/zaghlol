// T-096: pure rules for recurring money (domain-algorithms §6, BR-SUB-01..03,
// FR-SUB-05). No Flutter, no database. Amounts are Money (integer minor
// units, one currency per comparison); dates are local civil dates
// (CivilDate), so no zone arithmetic happens here. Detection only suggests:
// the app layer turns a suggestion into a review item and never activates it
// by itself.

import '../budget/civil_date.dart';
import '../money/money.dart';

/// Chain rule (BR-SUB-01): consecutive charges 25..35 days apart.
const int subscriptionMinGapDays = 25;
const int subscriptionMaxGapDays = 35;

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
}

/// A suggestion for the review queue (never an active item).
final class SubscriptionSuggestion {
  const SubscriptionSuggestion({
    required this.merchantNorm,
    required this.accountId,
    required this.name,
    required this.amount,
    required this.annualCost,
    required this.dueDay,
    required this.nextDue,
    required this.chargeIds,
  });

  final String merchantNorm;
  final String accountId;
  final String name;

  /// The latest charge: the expected monthly amount.
  final Money amount;

  /// amount × 12 (BR-SUB-02).
  final Money annualCost;
  final int dueDay;

  /// The latest charge's date plus one month (day clamped to month end).
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

/// Finds subscription candidates (BR-SUB-01). Charges are grouped by
/// (merchant, account, currency) and sorted by date; the suggestion is the
/// chain of ≥ 2 charges that ends at the group's latest charge. A longer old
/// chain that has since stopped (the latest charge breaks the pattern) yields
/// nothing. Groups whose key is in [exclude] (`merchant|account|currency`,
/// see [recurringKey]) are skipped: that is how an existing, confirmed or
/// dismissed item stays quiet. Zero amounts and unstorable merchant keys are
/// ignored. Output order is by merchant, account, currency.
List<SubscriptionSuggestion> detectSubscriptions(
  Iterable<RecurringCharge> charges, {
  Set<String> exclude = const {},
}) {
  final groups = <String, List<RecurringCharge>>{};
  for (final c in charges) {
    if (!c.amount.isPositive || !isStorableMerchantNorm(c.merchantNorm)) {
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
  final out = <SubscriptionSuggestion>[];
  for (final key in keys) {
    if (exclude.contains(key)) continue;
    final list = groups[key]!
      ..sort((a, b) {
        final d = a.date.compareTo(b.date);
        return d != 0 ? d : a.id.compareTo(b.id);
      });
    // Walk backwards from the latest charge while the chain holds.
    var start = list.length - 1;
    while (start > 0) {
      final prev = list[start - 1];
      final cur = list[start];
      final gap = cur.date.difference(prev.date);
      if (gap < subscriptionMinGapDays ||
          gap > subscriptionMaxGapDays ||
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
    if (chain.length < 2) continue;
    final last = chain.last;
    final name = _name(last.displayName, last.merchantNorm);
    out.add(
      SubscriptionSuggestion(
        merchantNorm: last.merchantNorm,
        accountId: last.accountId,
        name: name,
        amount: last.amount,
        annualCost: last.amount.times(12),
        dueDay: last.date.day,
        nextDue: advanceDue(
          last.date,
          cadence: RecurrenceCadence.monthly,
          dueDay: last.date.day,
        ),
        chargeIds: [for (final c in chain) c.id],
      ),
    );
  }
  return out;
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

enum RecurrenceCadence { monthly, yearly, weekly, customDays }

/// The due date after [from] (the date just paid or charged). Monthly and
/// yearly keep the anchor day [dueDay] and clamp it to short months
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
      final y = from.month == 12 ? from.year + 1 : from.year;
      final m = from.month == 12 ? 1 : from.month + 1;
      return _clamped(y, m, dueDay ?? from.day);
    case RecurrenceCadence.yearly:
      return _clamped(from.year + 1, from.month, dueDay ?? from.day);
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
