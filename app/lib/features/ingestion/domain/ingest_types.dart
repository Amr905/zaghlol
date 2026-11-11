// T-046: the input and output of IngestRawMessages (design note §1). Pure
// Dart: no Flutter, no Drift. No outcome, result or exception carries a
// body, sender, last-4, merchant or amount, and every toString prints a kind
// or a code only. Nothing here is ever logged.

import 'package:zaghlol_domain/zaghlol_domain.dart';

/// How a message reached the use case.
enum MessageOrigin {
  /// Drained from the native spool (SMS / notification capture).
  spool,

  /// Read by the Android inbox catch-up scan (T-048): the spool path minus
  /// the ack.
  inboxScan,

  /// Share, paste or OCR text after the user confirmed it (§11): skips the
  /// Guard, is stored user-verified, and is never merged automatically.
  userConfirmed;

  /// Background origins go through the Guard re-check (BR-CAP-01).
  bool get isBackground => this != userConfirmed;
}

/// One message to ingest. [channel] is a `raw_messages.channel` wire value.
final class IncomingMessage {
  const IncomingMessage({
    required this.deliveryId,
    required this.channel,
    required this.source,
    required this.body,
    required this.receivedAtMs,
    required this.origin,
    this.simSlot,
  });

  /// The spool entry id (ack key) or another caller-chosen id. Unique per
  /// batch; a repeated id keeps the first outcome.
  final String deliveryId;
  final String channel;

  /// SMS sender id, notification package, Shortcut card name.
  final String source;

  /// Sensitive: never logged, never put into an error.
  final String body;

  /// The UTC instant the phone received the message (epoch ms).
  final int receivedAtMs;
  final int? simSlot;
  final MessageOrigin origin;

  @override
  String toString() => 'IncomingMessage(${origin.name})';
}

/// What happened to one message. Sealed: handle every case.
sealed class IngestOutcome {
  const IngestOutcome();

  /// A fixed code for diagnostics and tests.
  String get kind;

  @override
  String toString() => 'IngestOutcome($kind)';
}

/// A new transaction was stored.
final class IngestInserted extends IngestOutcome {
  const IngestInserted(this.txnId);
  final String txnId;
  @override
  String get kind => 'inserted';
}

/// The message is a second copy of a stored payment from another channel
/// (dedupe 2): its raw row is stored, no new transaction.
final class IngestMergedCrossChannel extends IngestOutcome {
  const IngestMergedCrossChannel(this.txnId);
  final String txnId;
  @override
  String get kind => 'merged_cross_channel';
}

/// A settled message updated its pending transaction, or a late pending
/// message was attached to its posted one (A-63).
final class IngestMergedPending extends IngestOutcome {
  const IngestMergedPending(this.txnId);
  final String txnId;
  @override
  String get kind => 'merged_pending';
}

/// The same message was stored before (dedupe 1, `body_hash`).
final class IngestDuplicate extends IngestOutcome {
  const IngestDuplicate();
  @override
  String get kind => 'duplicate';
}

/// Not stored at all. [reason] is a fixed code: a Guard drop wire name
/// (`ignored_card`, `not_financial`...), `ignored_rule` (base-only Guard plus
/// the database check), `parser_global` / `parser_institution` (stage 0) or
/// `unknown_channel`.
final class IngestDropped extends IngestOutcome {
  const IngestDropped(this.reason);
  final String reason;
  @override
  String get kind => 'dropped';
}

/// The raw message is stored and a review item points at it.
/// [reviewKind] is the `review_items.kind`.
final class IngestReview extends IngestOutcome {
  const IngestReview(this.rawId, this.reviewKind);
  final String rawId;
  final String reviewKind;
  @override
  String get kind => 'review';
}

/// A balance notice: raw row stored, balance recorded, no transaction.
final class IngestBalanceOnly extends IngestOutcome {
  const IngestBalanceOnly(this.rawId);
  final String rawId;
  @override
  String get kind => 'balance_only';
}

/// An event this build has no handler for (`fx_conversion` until T-089):
/// raw row stored `reparse_pending`, nothing else (T-076 re-runs it).
final class IngestDeferred extends IngestOutcome {
  const IngestDeferred(this.rawId);
  final String rawId;
  @override
  String get kind => 'deferred';
}

/// User-confirmed input that looks like stored payments (§11): nothing was
/// written; the confirming screen asks the user.
final class IngestPossibleDuplicate extends IngestOutcome {
  IngestPossibleDuplicate(Iterable<String> candidateTxnIds)
    : candidateTxnIds = List.unmodifiable(candidateTxnIds);
  final List<String> candidateTxnIds;
  @override
  String get kind => 'possible_duplicate';
}

/// The result of one committed batch.
final class IngestBatchResult {
  IngestBatchResult({
    required Map<String, IngestOutcome> outcomes,
    required List<String> ackable,
    required Set<String> changedTxnIds,
    required Set<String> changedAccountIds,
    required Set<String> createdAccountIds,
    this.event,
    List<String> kept = const [],
  }) : outcomes = Map.unmodifiable(outcomes),
       kept = List.unmodifiable(kept),
       ackable = List.unmodifiable(ackable),
       changedTxnIds = Set.unmodifiable(changedTxnIds),
       changedAccountIds = Set.unmodifiable(changedAccountIds),
       createdAccountIds = Set.unmodifiable(createdAccountIds);

  static final IngestBatchResult empty = IngestBatchResult(
    outcomes: const {},
    ackable: const [],
    changedTxnIds: const {},
    changedAccountIds: const {},
    createdAccountIds: const {},
  );

  /// By delivery id.
  final Map<String, IngestOutcome> outcomes;

  /// Every delivery id of the committed batch, in input order, except
  /// [kept]: the caller acks exactly these, after this result was returned.
  final List<String> ackable;

  /// CR-1/F2: delivery ids that could not be stored even alone for review
  /// (no outcome; never acked, so they stay in the spool, never deleted).
  final List<String> kept;
  final Set<String> changedTxnIds;

  /// Accounts whose transactions or balances changed.
  final Set<String> changedAccountIds;
  final Set<String> createdAccountIds;

  /// The event published after the commit; null when nothing changed.
  final TransactionsChanged? event;

  @override
  String toString() => 'IngestBatchResult(${outcomes.length})';
}

/// The batch transaction did not commit: nothing of the batch is stored and
/// nothing may be acked.
///
/// Codes: `CONFIG_INVALID` (the bundled Guard base is unusable; a build
/// defect must not delete captured messages), `DB_WRITE_FAILED` /
/// `DB_READ_FAILED` (busy, I/O, full: transient), `INGEST_MSG_UNSTORABLE`
/// (a message could not even be stored alone for review),
/// `INGEST_BATCH_TOO_LARGE`, `INGEST_INTERNAL` (an unexpected error).
final class IngestBatchFailed extends SafeException {
  IngestBatchFailed(super.code);

  static const String configInvalid = 'CONFIG_INVALID';
  static const String writeFailed = 'DB_WRITE_FAILED';
  static const String readFailed = 'DB_READ_FAILED';
  static const String unstorable = 'INGEST_MSG_UNSTORABLE';
  static const String tooLarge = 'INGEST_BATCH_TOO_LARGE';
  static const String internal = 'INGEST_INTERNAL';

  /// True when the same batch may succeed on the next cycle (busy, I/O).
  bool get isTransient => code == writeFailed || code == readFailed;
}
