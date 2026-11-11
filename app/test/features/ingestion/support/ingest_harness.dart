// T-046: an encrypted database plus IngestRawMessages wired with fakes
// (clock, ids, fixed zone, recording diag, event bus). All data synthetic.

import 'dart:async';

import 'package:drift/drift.dart' show Variable;
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/db_errors.dart';
import 'package:zaghlol/features/ingestion/application/ingest_raw_messages.dart';
import 'package:zaghlol/features/ingestion/application/ingest_store_port.dart';
import 'package:zaghlol/features/ingestion/data/device_local_zone.dart';
import 'package:zaghlol/features/ingestion/data/drift_ingest_store.dart';
import 'package:zaghlol/features/ingestion/data/ingest_factory.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_ports.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_records.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_types.dart';
import 'package:zaghlol/ingestion/spike_registry.dart' show RegistryGuardBase;
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/db/financial_fixtures.dart';
import 'test_registry.dart';

export '../../../core/db/financial_fixtures.dart' show EncryptedDb, t0;
export 'test_registry.dart';

const String canary = 'ZG_CANARY_7731';

/// Cairo, the fixed test zone (+02:00).
const int zoneOffsetMin = 120;

final Registry testRegistry = loadTestRegistry();

IncomingMessage sms(
  String id,
  String body, {
  int rx = t0,
  String source = zbankSms,
  MessageOrigin origin = MessageOrigin.spool,
}) => IncomingMessage(
  deliveryId: id,
  channel: 'sms',
  source: source,
  body: body,
  receivedAtMs: rx,
  origin: origin,
);

IncomingMessage notif(
  String id,
  String body, {
  int rx = t0,
  String source = zbankPackage,
}) => IncomingMessage(
  deliveryId: id,
  channel: 'notification',
  source: source,
  body: body,
  receivedAtMs: rx,
  origin: MessageOrigin.spool,
);

final class RecordingDiag implements DiagSink {
  final Map<String, int> counts = {};
  @override
  void count(String code, int n) => counts[code] = (counts[code] ?? 0) + n;
}

final class BytesGuardBase implements GuardConfigSource {
  BytesGuardBase(this.bytes);
  final List<int> bytes;
  @override
  List<int> baseBytes() => bytes;
}

final class ThrowingHook implements PostPersistHook {
  ThrowingHook(this.error, {this.times = 1});
  final Object error;
  int times;
  @override
  Future<void> afterPersist(PersistedTxn txn) async {
    if (times > 0) {
      times--;
      throw error;
    }
  }
}

/// Wraps a store port and fails the [failAt]-th call (1-based) with a
/// busy-like `DB_WRITE_FAILED`, simulating a crash or I/O error at that
/// step (before the commit).
final class FaultyStore implements IngestStorePort {
  FaultyStore(
    this._inner, {
    this.failAt,
    this.afterCrossChannelRead,
    this.poisonRaw,
  });

  /// CR-1/F2: raw inserts this matches throw a `StateError` (a defect, not
  /// a database error), even when stored alone for review.
  final bool Function(RawInsert row)? poisonRaw;

  final IngestStorePort _inner;
  int? failAt;

  /// Awaited after every dedupe-2 read (a test barrier for the race test).
  final Future<void> Function()? afterCrossChannelRead;
  int calls = 0;
  bool fired = false;

  Future<T> _step<T>(Future<T> Function() f) {
    calls++;
    if (failAt != null && calls == failAt) {
      fired = true;
      throw DbWriteException(DbWriteException.writeFailed);
    }
    return f();
  }

  @override
  Future<T> inWriteTransaction<T>(Future<T> Function() body) =>
      _step(() => _inner.inWriteTransaction(body));
  @override
  Future<T> inSavepoint<T>(Future<T> Function() body) =>
      _step(() => _inner.inSavepoint(body));
  @override
  Future<BatchContext> readContext() => _step(_inner.readContext);
  @override
  Future<bool> isIgnored({
    required String institutionCode,
    required String? last4,
    required String channel,
  }) => _step(
    () => _inner.isIgnored(
      institutionCode: institutionCode,
      last4: last4,
      channel: channel,
    ),
  );
  @override
  Future<bool> hashExists(String bodyHash) =>
      _step(() => _inner.hashExists(bodyHash));
  @override
  Future<bool> insertRaw(RawInsert row) => _step(() {
    if (poisonRaw?.call(row) ?? false) throw StateError('poison');
    return _inner.insertRaw(row);
  });
  @override
  Future<List<TxnCandidate>> crossChannelCandidates({
    required String dedupeKey,
    required int fromMs,
    required int toMs,
  }) => _step(() async {
    final found = await _inner.crossChannelCandidates(
      dedupeKey: dedupeKey,
      fromMs: fromMs,
      toMs: toMs,
    );
    await afterCrossChannelRead?.call();
    return found;
  });
  @override
  Future<List<TxnCandidate>> statusCandidates({
    required String institution,
    required String currency,
    required String status,
    required int fromMs,
    required int toMs,
  }) => _step(
    () => _inner.statusCandidates(
      institution: institution,
      currency: currency,
      status: status,
      fromMs: fromMs,
      toMs: toMs,
    ),
  );
  @override
  Future<void> insertTxn(TxnInsert row) => _step(() => _inner.insertTxn(row));
  @override
  Future<int> updateTxn(String txnId, TxnPatch patch, {required int atMs}) =>
      _step(() => _inner.updateTxn(txnId, patch, atMs: atMs));
  @override
  Future<void> insertReview({
    required String id,
    required String kind,
    required int createdAtMs,
    String? rawMessageId,
    String? txnId,
    Map<String, Object?>? payload,
  }) => _step(
    () => _inner.insertReview(
      id: id,
      kind: kind,
      createdAtMs: createdAtMs,
      rawMessageId: rawMessageId,
      txnId: txnId,
      payload: payload,
    ),
  );
}

/// One encrypted database and the use case over it.
final class IngestWorld {
  IngestWorld._(this.edb);

  final EncryptedDb edb;
  AppDatabase get db => edb.db;
  int clockMs = t0 + 1000;
  int _nextId = 0;
  final RecordingDiag diag = RecordingDiag();
  final DomainEventBus bus = DomainEventBus();
  final List<DomainEvent> events = [];
  late final StreamSubscription<DomainEvent> _sub;

  static Future<IngestWorld> open({bool background = true}) async {
    final w = IngestWorld._(await EncryptedDb.open(background: background));
    w._sub = w.bus.events.listen(w.events.add);
    return w;
  }

  Future<void> close() async {
    await _sub.cancel();
    await bus.dispose();
    await edb.close();
  }

  String newId() => 'id${(_nextId++).toString().padLeft(5, '0')}';

  IngestRawMessages useCase({
    AppDatabase? on,
    IngestStorePort Function(IngestStorePort inner)? wrap,
    GuardConfigSource? guardBase,
    List<PostPersistHook> hooks = const [],
    String idPrefix = '',
    CategorizerFactory? categorizerFactory,
  }) {
    final database = on ?? db;
    return buildIngestRawMessages(
      database,
      pipeline: ParsingPipeline(testRegistry),
      guardBase: guardBase ?? RegistryGuardBase(testRegistry),
      newId: () => '$idPrefix${newId()}',
      clock: () => DateTime.fromMillisecondsSinceEpoch(clockMs, isUtc: true),
      zone: const FixedLocalZone(zoneOffsetMin),
      store: wrap == null ? null : wrap(DriftIngestStore(database)),
      hooks: hooks,
      categorizerFactory: categorizerFactory,
      diag: diag,
      events: bus,
    );
  }

  Future<IngestBatchResult> run(List<IncomingMessage> batch) =>
      useCase()(batch);

  // ---- Queries (test-only SQL).

  Future<List<Map<String, Object?>>> rows(
    String sql, [
    List<Object?> args = const [],
  ]) async {
    final result = await db
        .customSelect(sql, variables: [for (final a in args) _var(a)])
        .get();
    return [for (final r in result) r.data];
  }

  static Variable<Object> _var(Object? a) => switch (a) {
    final int i => Variable.withInt(i),
    final String s => Variable.withString(s),
    _ => throw ArgumentError('test arg'),
  };

  Future<int> count(String table, [String where = '1 = 1']) async =>
      (await rows('SELECT count(*) AS c FROM $table WHERE $where')).single['c']!
          as int;

  Future<List<Map<String, Object?>>> txns() => rows(
    'SELECT t.*, a.last4 AS acc_last4, a.institution_code AS acc_inst '
    'FROM transactions t JOIN accounts a ON a.id = t.account_id '
    'ORDER BY t.occurred_at, t.id',
  );

  Future<List<Map<String, Object?>>> raws() =>
      rows('SELECT * FROM raw_messages ORDER BY received_at, id');

  Future<List<Map<String, Object?>>> reviews() =>
      rows('SELECT * FROM review_items ORDER BY created_at, id');
}
