// T-090: pure refund-matching rules (domain-algorithms §5, BR-XFR-03,
// EC-17). No Flutter, no database. The app layer reads the candidate
// expenses with their remaining (not yet offset) amounts, asks
// [decideRefund] and writes the result in one transaction.
//
// Money rules: integer minor units only; the refund and the expense must be
// in the same currency (nothing is converted); the linked amount never
// exceeds the expense's remaining amount nor the refund's amount, so a
// refund can never reduce spend by more than it is worth and the leftover
// of an oversized refund stays income.
//
// Doubt never links: two equally recent candidates go to review.

import '../budget/civil_date.dart';
import '../money/money.dart';

/// Days before the refund inside which an expense can be the original.
const int refundMatchWindowDays = 60;

/// A refund that was just stored.
final class RefundFact {
  const RefundFact({
    required this.id,
    required this.accountId,
    required this.merchantNorm,
    required this.amount,
    required this.occurredAtMs,
    required this.offsetMin,
  });

  final String id;
  final String accountId;

  /// Normalised merchant; null or empty never matches.
  final String? merchantNorm;

  /// The refund's absolute amount.
  final Money amount;

  /// UTC instant and the local offset in force (minutes).
  final int occurredAtMs;
  final int offsetMin;
}

/// An expense that may still be offset.
final class OffsetCandidate {
  const OffsetCandidate({
    required this.id,
    required this.accountId,
    required this.merchantNorm,
    required this.remaining,
    required this.occurredAtMs,
    required this.offsetMin,
  });

  final String id;
  final String accountId;
  final String? merchantNorm;

  /// Expense amount minus every amount already linked to it.
  final Money remaining;
  final int occurredAtMs;
  final int offsetMin;
}

sealed class RefundDecision {
  const RefundDecision();
}

/// Link [linked] of the refund to [expenseId]; [incomeRemainder] of the
/// refund (zero unless it was larger than the expense) stays income.
final class LinkRefund extends RefundDecision {
  const LinkRefund({
    required this.expenseId,
    required this.linked,
    required this.incomeRemainder,
  });

  final String expenseId;
  final Money linked;
  final Money incomeRemainder;
}

/// Several equally good originals: never auto-link (review).
final class AmbiguousRefund extends RefundDecision {
  const AmbiguousRefund(this.candidateIds);
  final List<String> candidateIds;
}

/// No original found: the refund counts as income.
final class NoRefundMatch extends RefundDecision {
  const NoRefundMatch();
}

/// Picks the original expense of [refund] among [candidates].
///
/// A candidate qualifies when it has the same currency, account and
/// non-empty merchant, a positive remaining amount, and a local date from
/// 60 days before to the day of the refund. Among those that can absorb the
/// whole refund the most recent wins; if none can (refund larger than every
/// remaining amount, EC-17) the most recent qualifying one wins and takes
/// what it can. Candidates with the same instant tie: [AmbiguousRefund].
RefundDecision decideRefund(
  RefundFact refund,
  Iterable<OffsetCandidate> candidates,
) {
  final merchant = refund.merchantNorm;
  if (merchant == null || merchant.isEmpty || refund.amount.minor <= 0) {
    return const NoRefundMatch();
  }
  final day = CivilDate.fromLocalMs(refund.occurredAtMs, refund.offsetMin);
  final earliest = day.plusDays(-refundMatchWindowDays);
  final ok = <OffsetCandidate>[
    for (final c in candidates)
      if (c.merchantNorm == merchant &&
          c.accountId == refund.accountId &&
          c.remaining.currency == refund.amount.currency &&
          c.remaining.minor > 0 &&
          _inWindow(
            CivilDate.fromLocalMs(c.occurredAtMs, c.offsetMin),
            earliest,
            day,
          ))
        c,
  ];
  if (ok.isEmpty) return const NoRefundMatch();
  final fits = [
    for (final c in ok)
      if (c.remaining.minor >= refund.amount.minor) c,
  ];
  final pool = fits.isNotEmpty ? fits : ok;
  var newest = pool.first.occurredAtMs;
  for (final c in pool) {
    if (c.occurredAtMs > newest) newest = c.occurredAtMs;
  }
  final top = [
    for (final c in pool)
      if (c.occurredAtMs == newest) c,
  ];
  if (top.length > 1) {
    return AmbiguousRefund([for (final c in top) c.id]..sort());
  }
  final e = top.single;
  final linkedMinor = e.remaining.minor < refund.amount.minor
      ? e.remaining.minor
      : refund.amount.minor;
  return LinkRefund(
    expenseId: e.id,
    linked: Money(refund.amount.currency, linkedMinor),
    incomeRemainder: Money(
      refund.amount.currency,
      refund.amount.minor - linkedMinor,
    ),
  );
}

bool _inWindow(CivilDate d, CivilDate from, CivilDate to) =>
    d.epochDay >= from.epochDay && d.epochDay <= to.epochDay;
