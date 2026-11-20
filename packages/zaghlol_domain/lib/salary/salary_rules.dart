// T-195 (D-71): pure rules for a salary that may be entered by hand and may
// also arrive as a bank message, so it is counted exactly once. No Flutter,
// no database. Amounts are Money (integer minor units, one currency per
// comparison, never converted); dates are local civil dates.
//
// The expected salary is only a plan plus a state. It is never a
// transaction, so it is in no total until a real transaction is tied to it.

import 'dart:convert';

import '../budget/civil_date.dart';
import '../money/currency.dart';
import '../money/money.dart';

/// A captured credit counts as the salary of payday P when it lands from
/// P - 3 to P + 5 days.
const int salaryWindowBeforeDays = 3;
const int salaryWindowAfterDays = 5;

/// Amount tolerance: within this many percent of the expected amount.
const int salaryAmountTolerancePercent = 15;

/// The nudge comes once the window is over (P + 6) and stops being sent
/// after this many days past P.
const int salaryNudgeLastDay = 20;

/// Largest state kept (entries, then declined ids).
const int salaryMaxEntries = 8;
const int salaryMaxDeclined = 16;
const int salaryMaxSkipped = 8;

final RegExp _id = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// "My salary": what the user expects and when (settings `salary.plan`).
final class SalaryPlan {
  const SalaryPlan._(this.amount, this.day, this.accountId);

  /// Null when [amount] is not positive, [day] is outside 1..28 or
  /// [accountId] is not a plain id.
  static SalaryPlan? tryCreate({
    required Money amount,
    required int day,
    String? accountId,
  }) {
    if (!amount.isPositive || day < 1 || day > 28) return null;
    if (accountId != null && !_id.hasMatch(accountId)) return null;
    return SalaryPlan._(amount, day, accountId);
  }

  final Money amount;

  /// Day of month, 1..28 (BR-BUD-01 range, so every month has it).
  final int day;

  /// The account the salary lands on; null means the default account.
  final String? accountId;

  Currency get currency => amount.currency;

  String toJson() => jsonEncode({
    'v': 1,
    'm': amount.minor,
    'c': amount.currency.code,
    'd': day,
    if (accountId != null) 'a': accountId,
  });

  static SalaryPlan? tryFromJson(String text) {
    final Object? j;
    try {
      j = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (j is! Map<String, Object?> || j['v'] != 1) return null;
    final m = j['m'];
    final c = j['c'];
    final d = j['d'];
    final a = j['a'];
    if (m is! int || c is! String || d is! int) return null;
    if (a != null && a is! String) return null;
    final money = Money.tryFromStorage(m, c);
    if (money == null) return null;
    return tryCreate(amount: money, day: d, accountId: a as String?);
  }

  @override
  bool operator ==(Object other) =>
      other is SalaryPlan &&
      other.amount == amount &&
      other.day == day &&
      other.accountId == accountId;

  @override
  int get hashCode => Object.hash(amount, day, accountId);
}

/// The payday `P` of [day] whose window holds [date], or null.
CivilDate? salaryPaydayFor(CivilDate date, int day) {
  for (final shift in const [0, 1, -1]) {
    var y = date.year;
    var m = date.month + shift;
    if (m < 1) {
      m += 12;
      y -= 1;
    } else if (m > 12) {
      m -= 12;
      y += 1;
    }
    if (y < 1 || y > 9999) continue;
    final p = CivilDate(y, m, day);
    if (salaryInWindow(p, date)) return p;
  }
  return null;
}

/// The latest payday of [day] on or before [today].
CivilDate salaryLatestPayday(CivilDate today, int day) {
  final thisMonth = CivilDate(today.year, today.month, day);
  if (thisMonth.compareTo(today) <= 0) return thisMonth;
  final y = today.month == 1 ? today.year - 1 : today.year;
  final m = today.month == 1 ? 12 : today.month - 1;
  return CivilDate(y, m, day);
}

/// The payday of [day] one month after [payday].
CivilDate salaryNextPayday(CivilDate payday, int day) {
  final y = payday.month == 12 ? payday.year + 1 : payday.year;
  final m = payday.month == 12 ? 1 : payday.month + 1;
  return CivilDate(y, m, day);
}

/// Whether [date] is in the window of [anchor].
bool salaryInWindow(CivilDate anchor, CivilDate date) {
  final d = date.difference(anchor);
  return d >= -salaryWindowBeforeDays && d <= salaryWindowAfterDays;
}

/// Same currency and within [salaryAmountTolerancePercent] of [expected].
bool salaryAmountClose(Money expected, Money actual) {
  if (expected.currency != actual.currency) return false;
  final e = expected.minor;
  final a = actual.minor;
  if (e <= 0 || a <= 0) return false;
  // Integer test, no floating point: |a - e| * 100 <= 15 * e. Amounts are
  // below 2^53, so the products stay below 2^63 only if scaled down first.
  final diff = (a - e).abs();
  return BigInt.from(diff) * BigInt.from(100) <=
      BigInt.from(salaryAmountTolerancePercent) * BigInt.from(e);
}

/// Whether free text (merchant, counterparty or note, never the raw
/// message) says salary.
bool salaryLooksLikeSalary(Iterable<String?> texts) {
  for (final t in texts) {
    if (t == null || t.isEmpty) continue;
    final s = t.toLowerCase();
    if (s.contains('salary') ||
        s.contains('payroll') ||
        s.contains('مرتب') ||
        s.contains('راتب') ||
        s.contains('رواتب')) {
      return true;
    }
  }
  return false;
}

/// A captured credit as the matcher sees it.
final class SalaryCredit {
  const SalaryCredit({
    required this.amount,
    required this.localDate,
    required this.keyword,
  });

  final Money amount;
  final CivilDate localDate;

  /// [salaryLooksLikeSalary] of its description fields.
  final bool keyword;
}

/// Window, currency and (amount close or keyword) against one anchor.
bool salaryMatches({
  required CivilDate anchor,
  required Money expected,
  required SalaryCredit credit,
}) {
  if (credit.amount.currency != expected.currency) return false;
  if (!salaryInWindow(anchor, credit.localDate)) return false;
  return credit.keyword || salaryAmountClose(expected, credit.amount);
}

/// A transaction tied to a salary anchor.
final class SalaryEntry {
  const SalaryEntry({
    required this.txnId,
    required this.captured,
    required this.anchor,
    this.mergedTxnId,
    this.mergedAmount,
  });

  final String txnId;

  /// True: a bank message (or notification); false: entered by hand.
  final bool captured;

  /// The payday this transaction stands for, or the date of a one-off
  /// manual entry.
  final CivilDate anchor;

  /// A manual row this captured one replaced (restorable until purged).
  final String? mergedTxnId;
  final Money? mergedAmount;

  SalaryEntry withMerged(String txn, Money amount) => SalaryEntry(
    txnId: txnId,
    captured: captured,
    anchor: anchor,
    mergedTxnId: txn,
    mergedAmount: amount,
  );

  SalaryEntry withoutMerged() =>
      SalaryEntry(txnId: txnId, captured: captured, anchor: anchor);

  Map<String, Object?> toJson() => {
    't': txnId,
    'k': captured ? 'c' : 'm',
    'a': anchor.toIso(),
    if (mergedTxnId != null) 'mt': mergedTxnId,
    if (mergedAmount != null) 'mm': mergedAmount!.minor,
    if (mergedAmount != null) 'mc': mergedAmount!.currency.code,
  };

  static SalaryEntry? _from(Object? j) {
    if (j is! Map<String, Object?>) return null;
    final t = j['t'];
    final k = j['k'];
    final a = j['a'];
    if (t is! String || !_id.hasMatch(t)) return null;
    if (k != 'c' && k != 'm') return null;
    if (a is! String) return null;
    final anchor = CivilDate.tryParse(a);
    if (anchor == null) return null;
    final mt = j['mt'];
    Money? mm;
    if (mt != null) {
      if (mt is! String || !_id.hasMatch(mt)) return null;
      final minor = j['mm'];
      final code = j['mc'];
      if (minor is! int || code is! String) return null;
      mm = Money.tryFromStorage(minor, code);
      if (mm == null) return null;
    }
    return SalaryEntry(
      txnId: t,
      captured: k == 'c',
      anchor: anchor,
      mergedTxnId: mt as String?,
      mergedAmount: mm,
    );
  }
}

/// What the matcher remembers (settings `salary.state`). Immutable.
final class SalaryState {
  const SalaryState({
    this.entries = const [],
    this.skipped = const [],
    this.declined = const [],
  });

  static const SalaryState empty = SalaryState();

  final List<SalaryEntry> entries;

  /// Paydays the user skipped.
  final List<CivilDate> skipped;

  /// Captured transactions that must never be merged or tied again (the
  /// user undid it).
  final List<String> declined;

  SalaryEntry? entryOf(String txnId) {
    for (final e in entries) {
      if (e.txnId == txnId) return e;
    }
    return null;
  }

  bool isSkipped(CivilDate payday) => skipped.contains(payday);

  SalaryState withEntry(SalaryEntry e) => _pruned(
    entries: [
      for (final x in entries)
        if (x.txnId != e.txnId) x,
      e,
    ],
  );

  SalaryState withoutEntry(String txnId) => _pruned(
    entries: [
      for (final x in entries)
        if (x.txnId != txnId) x,
    ],
  );

  SalaryState withSkipped(CivilDate payday) =>
      skipped.contains(payday) ? this : _pruned(skipped: [...skipped, payday]);

  SalaryState withDeclined(String txnId) => _pruned(
    declined: [
      for (final x in declined)
        if (x != txnId) x,
      txnId,
    ],
  );

  SalaryState _pruned({
    List<SalaryEntry>? entries,
    List<CivilDate>? skipped,
    List<String>? declined,
  }) {
    List<T> last<T>(List<T> l, int n) =>
        l.length <= n ? l : l.sublist(l.length - n);
    return SalaryState(
      entries: last(entries ?? this.entries, salaryMaxEntries),
      skipped: last(skipped ?? this.skipped, salaryMaxSkipped),
      declined: last(declined ?? this.declined, salaryMaxDeclined),
    );
  }

  String toJson() => jsonEncode({
    'v': 1,
    'e': [for (final e in entries) e.toJson()],
    's': [for (final s in skipped) s.toIso()],
    'd': declined,
  });

  /// Unreadable text reads as empty (nothing is thrown or echoed).
  static SalaryState fromJson(String? text) {
    if (text == null || text.isEmpty) return empty;
    final Object? j;
    try {
      j = jsonDecode(text);
    } on FormatException {
      return empty;
    }
    if (j is! Map<String, Object?> || j['v'] != 1) return empty;
    final e = j['e'];
    final s = j['s'];
    final d = j['d'];
    final entries = <SalaryEntry>[];
    if (e is List<Object?>) {
      for (final x in e) {
        final parsed = SalaryEntry._from(x);
        if (parsed != null) entries.add(parsed);
      }
    }
    final skipped = <CivilDate>[];
    if (s is List<Object?>) {
      for (final x in s) {
        final p = x is String ? CivilDate.tryParse(x) : null;
        if (p != null) skipped.add(p);
      }
    }
    final declined = <String>[];
    if (d is List<Object?>) {
      for (final x in d) {
        if (x is String && _id.hasMatch(x)) declined.add(x);
      }
    }
    return const SalaryState()._pruned(
      entries: entries,
      skipped: skipped,
      declined: declined,
    );
  }
}

/// A salary transaction the caller knows to be live, for the decision.
final class LiveSalaryTxn {
  const LiveSalaryTxn(this.txnId, this.amount);
  final String txnId;
  final Money amount;
}

/// What to do with a newly captured credit.
sealed class SalaryDecision {
  const SalaryDecision();
}

/// Not a salary (or nothing to tie it to, or doubt).
final class SalaryNone extends SalaryDecision {
  const SalaryNone();
}

/// Tag the credit as the salary of [payday] and close the expected item.
final class SalaryTagExpected extends SalaryDecision {
  const SalaryTagExpected(this.payday);
  final CivilDate payday;
}

/// The credit replaces the manual salary [entry].
final class SalaryMergeManual extends SalaryDecision {
  const SalaryMergeManual(this.entry);
  final SalaryEntry entry;
}

/// Decides for one captured credit. [liveManual] are the manual entries
/// whose transaction is still live (the caller checks the database).
/// [paydayClosed] says whether the payday already has a live tied
/// transaction.
SalaryDecision decideSalaryCredit({
  required String creditTxnId,
  required SalaryCredit credit,
  required SalaryPlan? plan,
  required SalaryState state,
  required List<SalaryEntry> liveManual,
  required List<LiveSalaryTxn> liveManualTxns,
  required bool Function(CivilDate payday) paydayClosed,
}) {
  if (state.declined.contains(creditTxnId)) return const SalaryNone();
  if (state.entryOf(creditTxnId) != null) return const SalaryNone();
  final amountOf = {for (final t in liveManualTxns) t.txnId: t.amount};
  final hits = <SalaryEntry>[];
  for (final e in liveManual) {
    final amount = amountOf[e.txnId];
    if (e.captured || amount == null) continue;
    if (salaryMatches(anchor: e.anchor, expected: amount, credit: credit)) {
      hits.add(e);
    }
  }
  if (hits.length > 1) return const SalaryNone(); // doubt: never guess
  if (hits.length == 1) return SalaryMergeManual(hits.single);
  if (plan == null) return const SalaryNone();
  final p = salaryPaydayFor(credit.localDate, plan.day);
  if (p == null || state.isSkipped(p) || paydayClosed(p)) {
    return const SalaryNone();
  }
  if (!salaryMatches(anchor: p, expected: plan.amount, credit: credit)) {
    return const SalaryNone();
  }
  return SalaryTagExpected(p);
}

/// The expected item the user sees, or null.
///
/// Open from the latest payday P (P <= [today]) until the next window
/// starts, while nothing live is tied to P and the user did not skip it.
CivilDate? salaryOpenPayday({
  required SalaryPlan plan,
  required SalaryState state,
  required CivilDate today,
  required bool Function(CivilDate payday) paydayClosed,
}) {
  final p = salaryLatestPayday(today, plan.day);
  final next = salaryNextPayday(p, plan.day);
  if (today.difference(next) >= -salaryWindowBeforeDays) return null;
  if (state.isSkipped(p) || paydayClosed(p)) return null;
  return p;
}

/// Whether the one nudge of payday [p] is due on [today]: the window is over
/// and the nudge is not stale.
bool salaryNudgeDue(CivilDate p, CivilDate today) {
  final d = today.difference(p);
  return d > salaryWindowAfterDays && d <= salaryNudgeLastDay;
}
