// T-091: pure rules for bill splits and reimbursements (domain-algorithms §5,
// FR-XFR-04…09, BR-XFR-04…08, EC-37, EC-39, EC-40). No Flutter, no database.
//
// Money rules: integer minor units only; one currency per plan (nothing is
// converted); no amount is counted twice: every grant is capped by what the
// expense, the participant and the incoming transfer still have, and what is
// not granted stays income (BR-XFR-06). Doubt never grants: a request that
// is malformed is rejected with a reason, never silently rewritten.

import '../money/money.dart';

/// Why a split's shares are not acceptable.
enum ShareProblem { negative, currencyMismatch, exceedsExpense }

/// Checks participants' [shares] (everyone but the user) against the
/// expense [amount]. The user's own share is the rest (BR-XFR-04).
ShareProblem? checkShares(Money amount, Iterable<Money> shares) {
  var sum = 0;
  for (final s in shares) {
    if (s.currency != amount.currency) return ShareProblem.currencyMismatch;
    if (s.minor < 0) return ShareProblem.negative;
    sum += s.minor;
    if (sum > amount.minor) return ShareProblem.exceedsExpense;
  }
  return null;
}

/// Splits [total] evenly between [people] (the user included); the extra
/// minor units go to the first people (largest remainder). The shares add
/// up to [total] exactly.
List<Money> equalSplit(Money total, int people) {
  if (people < 1) throw ArgumentError('people must be at least 1');
  return total.allocateEven(people);
}

/// The user's own share: the expense minus what the others owe, never below
/// zero.
Money ownShare(Money amount, Iterable<Money> shares) {
  var rest = amount.minor;
  for (final s in shares) {
    rest -= s.minor;
  }
  return Money(amount.currency, rest < 0 ? 0 : rest);
}

/// Net personal spend of an expense: paid minus linked offsets, never below
/// zero (BR-XFR-04, BR-TXN-01).
Money netOfOffsets(Money amount, Money linked) {
  final left = amount.minor - linked.minor;
  return Money(amount.currency, left < 0 ? 0 : left);
}

/// What a participant still owes: share minus the repayments attributed to
/// them, never below zero (FR-XFR-05).
Money unsettledShare(Money share, Money repaid) => netOfOffsets(share, repaid);

/// One expense the user may assign money to.
final class ExpenseRoom {
  const ExpenseRoom({
    required this.expenseId,
    required this.remaining,
    this.participantRemaining = const {},
  });

  final String expenseId;

  /// Expense amount minus every link already on it.
  final Money remaining;

  /// Unsettled share per participant id (see [unsettledShare]).
  final Map<String, Money> participantRemaining;
}

/// "Put [amount] of this incoming transfer on [expenseId]".
final class AllocationRequest {
  const AllocationRequest({
    required this.expenseId,
    required this.amount,
    this.participantId,
  });

  final String expenseId;
  final Money amount;

  /// The friend who paid it, when the user says so.
  final String? participantId;
}

enum RejectReason {
  nonPositive,
  currencyMismatch,
  unknownExpense,
  unknownParticipant,
  duplicateExpense,
  noRoom,
}

final class GrantedLink {
  const GrantedLink({
    required this.expenseId,
    required this.participantId,
    required this.requested,
    required this.granted,
  });

  final String expenseId;
  final String? participantId;
  final Money requested;

  /// At most [requested]; smaller when a cap bit (EC-37).
  final Money granted;

  bool get clamped => granted.minor < requested.minor;
}

final class RejectedRequest {
  const RejectedRequest(this.request, this.reason);
  final AllocationRequest request;
  final RejectReason reason;
}

final class ReimbursementPlan {
  const ReimbursementPlan({
    required this.grants,
    required this.rejected,
    required this.incomeRemainder,
  });

  final List<GrantedLink> grants;
  final List<RejectedRequest> rejected;

  /// What is left of the incoming transfer after the grants; it stays
  /// income (BR-XFR-06).
  final Money incomeRemainder;
}

/// Allocates an incoming transfer with [sourceRemaining] left (its amount
/// minus links already taken from it) over [requests], in order.
///
/// Each request is granted `min(requested, expense remaining, participant
/// unsettled share when one is named, source left)`. One request per expense
/// per call (the schema allows one link per expense and source). A request
/// that would grant nothing is rejected as [RejectReason.noRoom]. Σ granted
/// never exceeds [sourceRemaining], and per expense never exceeds its
/// remaining amount.
ReimbursementPlan planReimbursement({
  required Money sourceRemaining,
  required Iterable<AllocationRequest> requests,
  required Iterable<ExpenseRoom> rooms,
}) {
  final currency = sourceRemaining.currency;
  final byId = {for (final r in rooms) r.expenseId: r};
  final seen = <String>{};
  final partLeft = <String, int>{};
  var left = sourceRemaining.minor < 0 ? 0 : sourceRemaining.minor;
  final grants = <GrantedLink>[];
  final rejected = <RejectedRequest>[];

  for (final q in requests) {
    RejectReason? bad;
    final room = byId[q.expenseId];
    if (q.amount.minor <= 0) {
      bad = RejectReason.nonPositive;
    } else if (q.amount.currency != currency ||
        (room != null && room.remaining.currency != currency)) {
      bad = RejectReason.currencyMismatch;
    } else if (room == null) {
      bad = RejectReason.unknownExpense;
    } else if (!seen.add(q.expenseId)) {
      bad = RejectReason.duplicateExpense;
    } else if (q.participantId != null &&
        !room.participantRemaining.containsKey(q.participantId)) {
      bad = RejectReason.unknownParticipant;
    }
    if (bad != null) {
      rejected.add(RejectedRequest(q, bad));
      continue;
    }
    var cap = room!.remaining.minor;
    final p = q.participantId;
    if (p != null) {
      final pl = partLeft[p] ?? room.participantRemaining[p]!.minor;
      if (pl < cap) cap = pl;
    }
    if (left < cap) cap = left;
    if (q.amount.minor < cap) cap = q.amount.minor;
    if (cap <= 0) {
      rejected.add(RejectedRequest(q, RejectReason.noRoom));
      continue;
    }
    left -= cap;
    if (p != null) {
      partLeft[p] = (partLeft[p] ?? room.participantRemaining[p]!.minor) - cap;
    }
    grants.add(
      GrantedLink(
        expenseId: q.expenseId,
        participantId: p,
        requested: q.amount,
        granted: Money(currency, cap),
      ),
    );
  }
  return ReimbursementPlan(
    grants: grants,
    rejected: rejected,
    incomeRemainder: Money(currency, left),
  );
}

/// A link as the repair rule sees it.
final class LinkFact {
  const LinkFact({
    required this.id,
    required this.amountMinor,
    required this.createdAtMs,
  });

  final String id;
  final int amountMinor;
  final int createdAtMs;
}

/// EC-40: the transaction's amount is about to become [newAmountMinor];
/// returns the ids of the newest links to remove until the rest fits. Ties
/// on time go by id so the result is stable. Empty when nothing exceeds.
List<String> linksToRemove(int newAmountMinor, Iterable<LinkFact> links) {
  final cap = newAmountMinor < 0 ? 0 : newAmountMinor;
  final all = links.toList()
    ..sort((a, b) {
      final c = b.createdAtMs.compareTo(a.createdAtMs);
      return c != 0 ? c : b.id.compareTo(a.id);
    });
  var sum = 0;
  for (final l in all) {
    sum += l.amountMinor;
  }
  final out = <String>[];
  for (final l in all) {
    if (sum <= cap) break;
    out.add(l.id);
    sum -= l.amountMinor;
  }
  return out;
}
