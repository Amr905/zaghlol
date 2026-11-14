// T-143: the daily sync (FR-SYNC-01..05, EC-43, ADR-013, backend-api §4.2).
//
// One run:
//  1. single flight (in process) plus a `secure_state` lease, so the UI engine
//     and a background run never sync at once;
//  2. throttle / back-off from [SyncState]; a pending catalog snapshot is
//     fetched on its own;
//  3. the request is built from stored cursors and the outbox only (the
//     generated DTOs are the BR-SYNC-03 allow-list);
//  4. it is sent through T-144's time anchor (R4-2): the signed body, a
//     throttle answer included, reaches T-144 before anything else uses its
//     `serverTime`;
//  5. an effective answer is applied in ONE database transaction: catalog ops
//     and version, sent outbox rows, prices, flags. Any exception rolls all of
//     it back and the flags service reloads from the database;
//  6. after the commit, eligible transactions are re-categorized (FR-SYNC-05).
// A throttle answer applies nothing and keeps the outbox. Failures are
// code-only; nothing here logs a body, token, nonce or catalog text.

import '../../../ingestion/ingestion_pause_gate.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:zaghlol_domain/zaghlol_domain.dart' show SafeException;

import '../../../core/backend/backend_failure.dart';
import '../../../core/backend/backend_state.dart';
import '../../../core/backend/generated/api_models.g.dart';
import '../../../core/backend/ids.dart';
import '../../../core/db/app_database.dart' hide Settings;
import '../../../core/db/daos/catalog_dao.dart';
import '../../../core/db/daos/misc_daos.dart' show DiagLevel;
import '../../../core/db/daos/outbox_dao.dart';
import '../../../core/flags/flags_service.dart';
import '../../../core/logging/diag_code.dart';
import '../../../core/logging/diag_event.dart';
import '../../../core/logging/diag_logger.dart';
import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_repository.dart';
import '../../wealth/data/prices_repository.dart';
import '../domain/sync_schedule.dart';
import 'catalog_applier.dart';

/// `secure_state` keys of the sync.
const String syncStateKey = 'sync_state';
const String syncLeaseKey = 'sync_lease';

/// A lease older than this is a crashed run and may be taken over.
const Duration syncLeaseTtl = Duration(minutes: 5);

const int maxSyncContributions = 50;
const int maxSyncBankRequests = 10;

/// The backend calls the sync needs (BackendClient implements them).
abstract interface class SyncBackend {
  Future<SyncResponse> sync(SyncRequest request, TimeNonce nonce);
  Future<CatalogSnapshot> getFullCatalog(int version);
}

/// T-144's side: the serialized time anchor and the cached token's `iat`.
abstract interface class SyncAnchor {
  /// Runs [request] with a fresh nonce; the body goes to T-144 first.
  Future<SyncResponse> run(Future<SyncResponse> Function(TimeNonce) request);

  /// `iat` of the cached verified entitlement token (ms), or null.
  Future<int?> issuedAtMs();
}

enum SyncOutcomeKind {
  notDue,
  alreadyRunning,
  throttled,
  applied,
  failed,

  /// The restore flow holds the gate (WIRE-SVC): nothing ran.
  paused,
}

final class SyncOutcome {
  const SyncOutcome(this.kind, {this.catalogChanged = false, this.code});
  final SyncOutcomeKind kind;
  final bool catalogChanged;

  /// Failure code (never message text).
  final String? code;

  @override
  String toString() =>
      'SyncOutcome(${kind.name}${code == null ? '' : ' $code'})';
}

final class SyncException extends SafeException {
  SyncException(super.code);
  static const String applyFailed = 'SYNC_APPLY_FAILED';
  static const String badSnapshot = 'SYNC_SNAPSHOT_MISMATCH';
  static const String badRequest = 'SYNC_REQUEST_INVALID';
}

/// What the About screen shows (data only; T-146 owns the strings).
final class SyncStatus {
  const SyncStatus({
    required this.lastOkWallMs,
    required this.catalogVersion,
    required this.failures,
    required this.nextAttemptWallMs,
  });
  final int? lastOkWallMs;
  final int catalogVersion;
  final int failures;
  final int? nextAttemptWallMs;
}

class SyncOrchestrator {
  SyncOrchestrator({
    required this._db,
    required this._backend,
    required this._anchor,
    required this._store,
    required this._flags,
    required this._prices,
    required this._settings,
    this._recategorize,
    int Function()? now,
    this._diag,
    this._registryVersion,
    this._pauseGate,
  }) : _now = now ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch),
       _applier = CatalogApplier(_db);

  final AppDatabase _db;
  final SyncBackend _backend;
  final SyncAnchor _anchor;
  final BackendStateStore _store;
  final FlagsService _flags;
  final PricesRepository _prices;
  final SettingsRepository _settings;
  final Future<void> Function()? _recategorize;
  final int Function() _now;
  final DiagLogger? _diag;
  final int? _registryVersion;

  /// Closed by the restore flow: no run starts and a running one is awaited.
  final IngestionPauseGate? _pauseGate;
  final CatalogApplier _applier;

  Future<SyncOutcome>? _inFlight;

  /// Runs one sync if it is due (or [force]). Concurrent callers share the
  /// running one.
  Future<SyncOutcome> run({bool force = false}) {
    final running = _inFlight;
    if (running != null) return running;
    final gate = _pauseGate;
    if (gate != null && gate.paused) {
      return Future.value(const SyncOutcome(SyncOutcomeKind.paused));
    }
    final f =
        (gate == null ? _guarded(force) : gate.guard(() => _guarded(force)))
            .whenComplete(() => _inFlight = null);
    _inFlight = f;
    return f;
  }

  Future<SyncStatus> status() async {
    final s = await _loadState();
    return SyncStatus(
      lastOkWallMs: s.lastOkWallMs,
      catalogVersion: (await CatalogDao(_db).meta())?.version ?? 0,
      failures: s.failures,
      nextAttemptWallMs: s.retryNotBeforeWallMs,
    );
  }

  // ---- lease -----------------------------------------------------------

  /// The lease value this run holds, or null when another run holds one.
  Future<Uint8List?> _acquire() async {
    final cur = await _store.read(syncLeaseKey);
    final now = _now();
    if (cur != null) {
      final until = int.tryParse(utf8.decode(cur, allowMalformed: true));
      // A lease further away than twice its TTL is not ours: clock moved.
      if (until != null &&
          until > now &&
          until - now <= 2 * syncLeaseTtl.inMilliseconds) {
        return null;
      }
    }
    final next = Uint8List.fromList(
      utf8.encode('${now + syncLeaseTtl.inMilliseconds}'),
    );
    final won = await _store.compareAndSet(
      syncLeaseKey,
      expected: cur,
      next: next,
    );
    return won ? next : null;
  }

  // ---- the run -----------------------------------------------------------

  Future<SyncOutcome> _guarded(bool force) async {
    final mine = await _acquire();
    if (mine == null) {
      return const SyncOutcome(SyncOutcomeKind.alreadyRunning);
    }
    try {
      return await _run(force);
    } finally {
      await _store.deleteIfEquals(syncLeaseKey, mine);
    }
  }

  Future<SyncState> _loadState() async =>
      SyncState.decode(await _store.read(syncStateKey));

  Future<void> _saveState(SyncState s) =>
      _store.write(syncStateKey, s.encode());

  Future<SyncOutcome> _run(bool force) async {
    var state = await _loadState();
    final now = _now();
    // A pending snapshot is not behind the server's 24 h window: it is a
    // plain download, only the back-off applies.
    final due = state.pendingFullVersion != null
        ? state.retryAllowed(now)
        : state.isDue(now);
    if (!force && !due) {
      return const SyncOutcome(SyncOutcomeKind.notDue);
    }
    final sent = <_Sent>[];
    try {
      final pending = state.pendingFullVersion;
      if (pending != null) {
        final snap = await _fetchFull(pending);
        await _db.transaction(() async {
          await _applier.apply(
            ops: snap.ops,
            toVersion: snap.version,
            full: true,
            appliedAtMs: _now(),
          );
        });
        state = state.copyWith(pendingFullVersion: null);
        await _saveState(state);
        await _afterCatalog();
        return const SyncOutcome(SyncOutcomeKind.applied, catalogChanged: true);
      }

      final request = await _buildRequest(sent);
      final response = await _anchor.run(
        (nonce) => _backend.sync(request, nonce),
      );
      final received = _now();
      final serverMs = DateTime.parse(response.serverTime)
          .millisecondsSinceEpoch;
      final nextMs = DateTime.parse(response.nextSyncNotBefore)
          .millisecondsSinceEpoch;

      if (_isThrottle(response)) {
        await _saveState(
          state.copyWith(
            serverMs: serverMs,
            wallAtServerMs: received,
            nextNotBeforeServerMs: nextMs,
            failures: 0,
            retryNotBeforeWallMs: null,
          ),
        );
        return const SyncOutcome(SyncOutcomeKind.throttled);
      }

      final plan = await _planCatalog(response.catalog);
      CatalogSnapshot? snapshot;
      int? pendingFull;
      if (plan.needsFull) {
        try {
          snapshot = await _fetchFull(plan.toVersion);
        } on BackendFailure {
          pendingFull = plan.toVersion;
        } on SyncException {
          pendingFull = plan.toVersion;
        }
      }
      final changed = await _applyAll(response, plan, snapshot, sent);
      await _saveState(
        state.copyWith(
          lastOkWallMs: received,
          serverMs: serverMs,
          wallAtServerMs: received,
          nextNotBeforeServerMs: nextMs,
          failures: 0,
          retryNotBeforeWallMs: pendingFull == null
              ? null
              : received + syncMinBackoff.inMilliseconds,
          pendingFullVersion: pendingFull,
        ),
      );
      await _record(DiagCodes.syncOk, DiagLevel.info);
      if (changed) await _afterCatalog();
      return SyncOutcome(SyncOutcomeKind.applied, catalogChanged: changed);
    } on BackendFailure catch (e) {
      return _failed(state, e.code, sent, retryAfter: e.retryAfter);
    } on SafeException catch (e) {
      return _failed(state, e.code, sent);
    } on Object {
      // Anything else (a database error): typed, code only, nothing echoed.
      await _reloadFlags();
      return _failed(state, SyncException.applyFailed, sent);
    }
  }

  bool _isThrottle(SyncResponse r) =>
      r.accepted == null &&
      r.catalog == null &&
      r.flags == null &&
      r.prices == null &&
      r.entitlement == null;

  Future<SyncOutcome> _failed(
    SyncState state,
    String code,
    List<_Sent> sent, {
    Duration? retryAfter,
  }) async {
    final failures = state.failures + 1;
    final at =
        _now() + syncBackoff(failures, retryAfter: retryAfter).inMilliseconds;
    await _saveState(
      state.copyWith(failures: failures, retryNotBeforeWallMs: at),
    );
    final dao = OutboxDao(_db);
    for (final s in sent) {
      try {
        await dao.markAttempt(s.id, nextAttemptAt: at);
      } on Object {
        // Best effort: the row stays queued either way.
      }
    }
    await _record(DiagCodes.syncFailed, DiagLevel.warn);
    return SyncOutcome(SyncOutcomeKind.failed, code: code);
  }

  Future<void> _record(DiagCode code, DiagLevel level) async =>
      _diag?.record(DiagEvent(level: level, code: code));

  Future<void> _afterCatalog() async {
    await _record(DiagCodes.catalogUpdated, DiagLevel.info);
    final job = _recategorize;
    if (job == null) return;
    try {
      await job();
    } on Object {
      // Re-categorization is a follow-up: the next catalog change repeats it.
      await _record(DiagCodes.syncFailed, DiagLevel.warn);
    }
  }

  Future<void> _reloadFlags() async {
    try {
      await _flags.load();
    } on Object {
      // load() fails closed on its own.
    }
  }

  // ---- request ---------------------------------------------------------------

  Future<SyncRequest> _buildRequest(List<_Sent> sent) async {
    final meta = await CatalogDao(_db).meta();
    final iat = await _anchor.issuedAtMs();
    final price = (await _prices.status()).backendAsOfMs;
    final optIn = await _settings.get(Settings.contributionOptIn);
    final dao = OutboxDao(_db);
    final now = _now();

    final contributions = <ContributionInput>[];
    if (optIn) {
      for (final r in await dao.due(
        now: now,
        kind: OutboxKind.contribution,
        limit: maxSyncContributions,
      )) {
        final m = _payload(r.payload, const {
          'merchantNorm',
          'institutionCode',
          'categoryCode',
        });
        if (m == null) {
          await dao.deleteIds([r.id]); // never sendable
          continue;
        }
        contributions.add(
          ContributionInput(
            merchantNorm: m['merchantNorm']!,
            institutionCode: m['institutionCode']!,
            categoryCode: m['categoryCode']!,
          ),
        );
        sent.add(_Sent(r.id));
      }
    }
    final banks = <BankRequestInput>[];
    for (final r in await dao.due(
      now: now,
      kind: OutboxKind.bankRequest,
      limit: maxSyncBankRequests,
    )) {
      final m = _payload(r.payload, const {
        'institutionName',
        'country',
        'channel',
      });
      final channel = switch (m?['channel']) {
        'sms' => BankRequestInputChannel.sms,
        'notification' => BankRequestInputChannel.notification,
        _ => null,
      };
      if (m == null || channel == null) {
        await dao.deleteIds([r.id]);
        continue;
      }
      banks.add(
        BankRequestInput(
          institutionName: m['institutionName']!,
          country: m['country']!,
          channel: channel,
        ),
      );
      sent.add(_Sent(r.id));
    }

    final request = SyncRequest(
      catalogVersion: meta?.version ?? 0,
      flagsVersion: _flags.current.version,
      pricesAsOf: price == null ? null : _iso(price),
      entitlementIssuedAt: iat == null ? null : _iso(iat),
      registryVersion: _registryVersion,
      contributions: contributions.isEmpty ? null : contributions,
      bankRequests: banks.isEmpty ? null : banks,
    );
    try {
      request.toJson(); // fail before anything is sent
    } on SafeException {
      // A queued row broke the contract: drop what we were about to send.
      await dao.deleteIds([for (final s in sent) s.id]);
      sent.clear();
      throw SyncException(SyncException.badRequest);
    }
    return request;
  }

  static Map<String, String>? _payload(String json, Set<String> keys) {
    try {
      final m = jsonDecode(json);
      if (m is! Map || m.length != keys.length) return null;
      final out = <String, String>{};
      for (final k in keys) {
        final v = m[k];
        if (v is! String) return null;
        out[k] = v;
      }
      return out;
    } on FormatException {
      return null;
    }
  }

  static String _iso(int ms) {
    final s = DateTime.fromMillisecondsSinceEpoch(
      ms,
      isUtc: true,
    ).toIso8601String();
    return '${s.substring(0, 19)}Z';
  }

  // ---- apply -------------------------------------------------------------------

  Future<_CatalogPlan> _planCatalog(CatalogDelta? c) async {
    if (c == null) return const _CatalogPlan.none();
    final local = (await CatalogDao(_db).meta())?.version ?? 0;
    if (c.toVersion <= local && c.mode == CatalogDeltaMode.delta) {
      return const _CatalogPlan.none();
    }
    final full =
        c.mode != CatalogDeltaMode.delta ||
        c.fromVersion != local ||
        c.ops == null;
    return _CatalogPlan(
      toVersion: c.toVersion,
      needsFull: full,
      ops: full ? null : c.ops,
    );
  }

  Future<CatalogSnapshot> _fetchFull(int version) async {
    final snap = await _backend.getFullCatalog(version);
    if (snap.version != version) {
      throw SyncException(SyncException.badSnapshot);
    }
    return snap;
  }

  Future<bool> _applyAll(
    SyncResponse r,
    _CatalogPlan plan,
    CatalogSnapshot? snapshot,
    List<_Sent> sent,
  ) async {
    var changed = false;
    try {
      await _db.transaction(() async {
        if (snapshot != null) {
          await _applier.apply(
            ops: snapshot.ops,
            toVersion: snapshot.version,
            full: true,
            appliedAtMs: _now(),
          );
          changed = true;
        } else if (plan.ops != null) {
          await _applier.apply(
            ops: plan.ops!,
            toVersion: plan.toVersion,
            full: false,
            appliedAtMs: _now(),
          );
          changed = true;
        }
        await OutboxDao(_db).deleteIds([for (final s in sent) s.id]);
        final p = r.prices;
        if (p != null) await _prices.apply(_pricesJson(p));
        final f = r.flags;
        if (f != null) {
          await _flags.apply(RemoteFlags(version: f.version, values: f.values));
        }
      });
    } on Object {
      await _reloadFlags();
      rethrow;
    }
    return changed;
  }

  static Map<String, Object?> _pricesJson(PricesBlock p) => {
    'asOf': p.asOf,
    'stale': p.stale,
    'gold': [
      for (final g in p.gold)
        {'symbol': g.symbol, 'currency': g.currency, 'price': g.price},
    ],
    'fx': {'base': p.fx.base_, 'rates': p.fx.rates},
  };
}

final class _Sent {
  const _Sent(this.id);
  final String id;
}

final class _CatalogPlan {
  const _CatalogPlan({
    required this.toVersion,
    required this.needsFull,
    this.ops,
  });
  const _CatalogPlan.none() : toVersion = 0, needsFull = false, ops = null;

  final int toVersion;
  final bool needsFull;
  final List<CatalogOp>? ops;
}
