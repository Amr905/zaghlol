// T-046: the ports IngestRawMessages is built from (design note §1). Pure
// Dart. Implementations live in data/ (or in tests as fakes).

import 'package:zaghlol_parsing/zaghlol_parsing.dart' show Categorizer;

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

/// Makes the categorizer for one batch (§8; T-075 "create one Categorizer
/// per batch/run": the keywords are loaded once per instance, and rules or
/// the catalog may change between batches). Called once per batch, before
/// the write transaction; the instance is used only inside it, on the same
/// connection, so a rule the UI committed before our BEGIN is applied.
typedef CategorizerFactory = Future<Categorizer> Function();

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
