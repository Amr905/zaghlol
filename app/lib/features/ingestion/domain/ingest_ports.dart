// T-046: the ports IngestRawMessages is built from (design note §1). Pure
// Dart. Implementations live in data/ (or in tests as fakes).

import '../../transactions/domain/transaction.dart';

/// Diagnostics: fixed codes and counts only (§12). Never ids (ULIDs encode
/// receive times), never message text, senders, amounts or last-4.
abstract interface class DiagSink {
  void count(String code, int n);
}

final class NoDiag implements DiagSink {
  const NoDiag();
  @override
  void count(String code, int n) {}
}

/// The device time zone (EC-10). Offsets are minutes east of UTC.
abstract interface class LocalZone {
  /// The offset in force at the UTC instant [utcMs].
  int offsetAtInstant(int utcMs);

  /// The offset in force at a wall-clock time, given as a UTC-flagged
  /// [DateTime] whose y/m/d h:m:s are the local wall clock (the parser's
  /// convention).
  int offsetAtWallClock(DateTime wallClock);
}

/// The bundled Guard base part (platform-channels §1.1): the asset from
/// T-036, or a test/spike base before then. Read and parsed once per use
/// case instance (the asset does not change while the app runs).
abstract interface class GuardConfigSource {
  List<int> baseBytes();
}

/// What the categorizer sees (§8). Never logged.
final class CategorizeInput {
  const CategorizeInput({
    required this.direction,
    this.merchantNorm,
    this.counterparty,
    this.institution,
  });

  final String? merchantNorm;
  final String? counterparty;
  final String? institution;
  final TxnDirection direction;

  @override
  String toString() => 'CategorizeInput(${direction.code})';
}

final class CategorizeResult {
  const CategorizeResult({
    required this.source,
    this.categoryId,
    this.catalogMerchantId,
  });

  static const CategorizeResult none = CategorizeResult(
    source: CategorySource.none,
  );

  final String? categoryId;
  final CategorySource source;
  final int? catalogMerchantId;
}

/// The categorize hook (§8). Called inside the write transaction; T-075's
/// replacement must keep its in-transaction part under 5 ms per message.
abstract interface class Categorizer {
  Future<CategorizeResult> categorize(CategorizeInput input);
}

/// A transaction the batch stored or changed, for post-persist hooks.
final class PersistedTxn {
  const PersistedTxn({
    required this.txnId,
    required this.accountId,
    required this.inserted,
  });

  final String txnId;
  final String accountId;

  /// False for a merge into an existing transaction.
  final bool inserted;
}

/// Runs inside the message's savepoint after its writes (T-089 pairing,
/// FX and card settlement, refund matching, suggestions plug in here). A
/// throw rolls back the message like any other per-message failure.
abstract interface class PostPersistHook {
  Future<void> afterPersist(PersistedTxn txn);
}

/// The payday-cycle key (`2026-11`) of a transaction's local time.
typedef CycleKeyOf = String Function(int occurredAtMs, int tzOffsetMin);
