// T-046: the pure decisions of the ingest use case (design note §3–§6, §10;
// domain-algorithms §3; parsing-engine §6 "Event → transaction"). No I/O,
// no Flutter, no Drift; integer arithmetic only.

import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart'
    show TemplateDirection, TemplateEvent;

import '../../transactions/domain/transaction.dart';
import 'ingest_policy.dart';
import 'ingest_records.dart';

/// Cross-channel window (BR-ING-02 rule 2, A-30): minutes apart.
const int kCrossChannelWindowMinutes = 2;

/// Candidate fetch bound around `occurred_at` (the window itself is checked
/// in code, on two clocks).
const int kCrossChannelFetchMs = 24 * 60 * 60 * 1000;

/// Pending/settled (A-63): days between the pending and the settled one.
const int kPendingWindowMs = 7 * 24 * 60 * 60 * 1000;

/// Clock slack on the "before"/"after" side of the pending window.
const int kPendingSlackMs = kCrossChannelWindowMinutes * 60 * 1000;

/// Pending/settled amount tolerance, percent.
const int kPendingTolerancePercent = 5;

/// What a parsed message turns into (parsing-engine §6 table).
sealed class EventDisposition {
  const EventDisposition();
}

final class CreateTxn extends EventDisposition {
  const CreateTxn(this.direction, this.status);
  final TxnDirection direction;
  final TxnStatus status;
}

/// No transaction: raw `parsed` + balance.
final class BalanceOnlyEvent extends EventDisposition {
  const BalanceOnlyEvent();
}

/// No handler in this build: raw `reparse_pending`.
final class DeferredEvent extends EventDisposition {
  const DeferredEvent();
}

/// A transfer-like event whose template declares no direction: the
/// template is wrong, so the raw message goes to review (`unrecognized`).
final class UndirectedEvent extends EventDisposition {
  const UndirectedEvent();
}

/// Events stored as `reparse_pending` until their handler lands
/// (`fx_conversion`: T-089).
const Set<TemplateEvent> kEventsWithoutHandler = {TemplateEvent.fxConversion};

EventDisposition dispositionOf(
  TemplateEvent event,
  TemplateDirection direction,
) {
  if (kEventsWithoutHandler.contains(event)) return const DeferredEvent();
  const posted = TxnStatus.posted;
  switch (event) {
    case TemplateEvent.cardPurchase:
    case TemplateEvent.cardPurchaseFx:
    case TemplateEvent.atmWithdrawal:
    case TemplateEvent.bnplInstallment:
    case TemplateEvent.settled:
      return const CreateTxn(TxnDirection.expense, posted);
    case TemplateEvent.pendingAuth:
      return const CreateTxn(TxnDirection.expense, TxnStatus.pending);
    case TemplateEvent.declined:
      return const CreateTxn(TxnDirection.expense, TxnStatus.declined);
    case TemplateEvent.transferOut:
    case TemplateEvent.transferIn:
    case TemplateEvent.instapayOut:
    case TemplateEvent.instapayIn:
    case TemplateEvent.ccPayment:
    case TemplateEvent.walletTopup:
      return switch (direction) {
        TemplateDirection.expense => const CreateTxn(
          TxnDirection.transferOut,
          posted,
        ),
        TemplateDirection.income => const CreateTxn(
          TxnDirection.transferIn,
          posted,
        ),
        TemplateDirection.neutral => const UndirectedEvent(),
      };
    case TemplateEvent.salary:
      return const CreateTxn(TxnDirection.income, posted);
    case TemplateEvent.refund:
    case TemplateEvent.reversal:
      return const CreateTxn(TxnDirection.refund, posted);
    case TemplateEvent.fee:
      return const CreateTxn(TxnDirection.fee, posted);
    case TemplateEvent.balanceOnly:
      return const BalanceOnlyEvent();
    case TemplateEvent.fxConversion:
      return const DeferredEvent();
  }
}

/// `transactions.source` for a `raw_messages.channel`, or null for a
/// channel ingest does not store (the raw CHECK would refuse it too).
TxnSource? txnSourceOf(String channel) => switch (channel) {
  'sms' => TxnSource.sms,
  'notification' => TxnSource.notification,
  'shortcut_message' => TxnSource.shortcut,
  'apple_pay' => TxnSource.applePay,
  'share' || 'paste' => TxnSource.share,
  'ocr' => TxnSource.ocr,
  'pdf' => TxnSource.pdf,
  'csv' => TxnSource.csv,
  _ => null,
};

/// `transactions.dedupe_key` (design note §3): built from
/// `Money.toStorage()`, never from message text (T-012 F5).
String dedupeKeyOf(String institution, TxnDirection direction, Money amount) {
  final s = amount.toStorage();
  return 'd1|$institution|${direction.code}|${s.currency}|${s.minor}';
}

/// Dedupe 2 compares within a status class: `declined` only with
/// `declined`; `pending` and `posted` with each other.
String statusClassOf(TxnStatus status) => switch (status) {
  TxnStatus.declined => 'declined',
  TxnStatus.reversed => 'reversed',
  TxnStatus.pending || TxnStatus.posted => 'live',
};

/// Last-4 rule of dedupe 2 and pending/settled: equal, or (PO Q1,
/// provisional) missing on one side.
bool last4Compatible(String? a, String? b) {
  if (a == null || b == null) {
    return kMergeWhenLast4MissingOnOneSide || (a == null && b == null);
  }
  return a == b;
}

/// Merchant rule of pending/settled: equal when both have one.
bool merchantCompatible(String? a, String? b) =>
    a == null || b == null || a == b;

/// The ±2 min window on two clocks: the minutes of `occurred_at`, or the
/// raws' `received_at` (both on the phone clock, EC-10).
bool withinCrossChannelWindow({
  required int occurredA,
  required int occurredB,
  int? receivedA,
  int? receivedB,
}) {
  final minuteA = _floorDiv(occurredA, 60000);
  final minuteB = _floorDiv(occurredB, 60000);
  if ((minuteA - minuteB).abs() <= kCrossChannelWindowMinutes) return true;
  if (receivedA == null || receivedB == null) return false;
  return (receivedA - receivedB).abs() <= kCrossChannelWindowMinutes * 60000;
}

int _floorDiv(int a, int b) => (a - (a % b)) ~/ b;

/// The new message's side of a dedupe 2 comparison.
final class NewTxnKeys {
  const NewTxnKeys({
    required this.source,
    required this.status,
    required this.occurredAtMs,
    required this.receivedAtMs,
    this.last4,
  });

  final String source;
  final TxnStatus status;
  final int occurredAtMs;
  final int receivedAtMs;
  final String? last4;
}

/// Dedupe 2 (BR-ING-02 rule 2, A-30, EC-01). [candidates] already share
/// the dedupe key and lie within [kCrossChannelFetchMs]. Soft-deleted ones
/// count (a deleted payment is not resurrected by its second copy).
List<TxnCandidate> crossChannelMatches(
  NewTxnKeys n,
  List<TxnCandidate> candidates,
) => [
  for (final c in candidates)
    if (c.source != n.source &&
        statusClassOf(c.status) == statusClassOf(n.status) &&
        withinCrossChannelWindow(
          occurredA: n.occurredAtMs,
          occurredB: c.occurredAtMs,
          receivedA: n.receivedAtMs,
          receivedB: c.rawReceivedAtMs,
        ) &&
        last4Compatible(n.last4, c.accountLast4))
      c,
];

/// `|a − p| × 100 ≤ 5 × p` in integers (A-63). [settled] and [pending] are
/// minor units of one currency.
bool withinPendingTolerance(int settled, int pending) {
  if (pending <= 0 || settled < 0) return false;
  return (settled - pending).abs() * 100 <= kPendingTolerancePercent * pending;
}

/// The pending (or posted, for the symmetric case) transaction to merge
/// with: amounts within tolerance, then the smallest difference, then the
/// oldest, then the id. [pendingAmountOf] picks which side is "p".
TxnCandidate? pickPendingMatch({
  required int newAmountMinor,
  required bool newIsPending,
  required List<TxnCandidate> candidates,
}) {
  TxnCandidate? best;
  var bestDiff = 0;
  for (final c in candidates) {
    final settled = newIsPending ? c.amount.minor : newAmountMinor;
    final pending = newIsPending ? newAmountMinor : c.amount.minor;
    if (!withinPendingTolerance(settled, pending)) continue;
    final diff = (settled - pending).abs();
    if (best == null ||
        diff < bestDiff ||
        (diff == bestDiff &&
            (c.occurredAtMs < best.occurredAtMs ||
                (c.occurredAtMs == best.occurredAtMs &&
                    c.id.compareTo(best.id) < 0)))) {
      best = c;
      bestDiff = diff;
    }
  }
  return best;
}

/// The payday cycle key (`YYYY-MM` of the cycle start month) of a local
/// time (domain-algorithms §2; A-43: no payday is day 1). [paydayDay]
/// outside 1..28 is treated as 1.
String cycleKeyFor({
  required int occurredAtMs,
  required int tzOffsetMin,
  required int paydayDay,
}) {
  final payday = paydayDay < 1 || paydayDay > 28 ? 1 : paydayDay;
  final local = DateTime.fromMillisecondsSinceEpoch(
    occurredAtMs + tzOffsetMin * 60000,
    isUtc: true,
  );
  var year = local.year;
  var month = local.month;
  if (local.day < payday) {
    month -= 1;
    if (month == 0) {
      month = 12;
      year -= 1;
    }
  }
  return '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}';
}

/// `settings.payday_day` as stored, or 1 (A-43).
int paydayDayOf(String? stored) {
  final n = stored == null ? null : int.tryParse(stored.trim());
  return n == null || n < 1 || n > 28 ? 1 : n;
}

/// Offsets the schema accepts (`occurred_tz_offset_min`, ±18 h).
int clampTzOffset(int minutes) =>
    minutes < -1080 ? -1080 : (minutes > 1080 ? 1080 : minutes);
