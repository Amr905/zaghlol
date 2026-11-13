// T-046: IngestRawMessages, the single path from a raw message to a stored
// transaction (design note in docs/04-tasks/tasks/T-046.md; parsing-engine
// §6; BR-ING-02, NFR-REL-01).
//
// Order: parse every message before the transaction (pure; never on the
// DB). Then ONE write transaction per batch (`BEGIN IMMEDIATE`): step 0
// reads the capture controls and builds the Guard; each message runs in its
// own savepoint (Guard re-check → stage-0 drop → dedupe 1 → disposition →
// dedupe 2 → pending/settled → account → categorize → insert raw + txn →
// balance → review items → hooks). Commit, then emit events, then return;
// the caller acks `ackable` only after this returned.
//
// Privacy: nothing here logs or prints. No outcome, exception, review
// payload or diag code carries a body, sender, last-4, merchant or amount
// (review payloads hold ids, reason codes, confidence and typed amounts the
// user is asked to confirm).

import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;
import 'package:zaghlol_domain/zaghlol_domain.dart';
// T-075's `CategorySource` is mapped to the stored one by code.
import 'package:zaghlol_parsing/zaghlol_parsing.dart' hide CategorySource;

import '../../../core/db/daos/review_items_dao.dart' show ReviewKind;
import '../../../core/db/db_errors.dart';
import '../../accounts/domain/account.dart';
import '../../accounts/domain/accounts_repository.dart';
import '../../categorization/domain/categorize_input.dart';
import '../../transactions/domain/transaction.dart';
import '../domain/body_hash.dart';
import '../domain/ingest_policy.dart';
import '../domain/ingest_ports.dart';
import '../domain/ingest_records.dart';
import '../domain/ingest_rules.dart';
import '../domain/ingest_types.dart';
import 'ingest_store_port.dart';

/// Largest batch one call accepts (the spool drains 20; native caps 100).
const int kMaxIngestBatch = 100;

/// `raw_messages.parse_status` values.
abstract final class RawStatus {
  static const String parsed = 'parsed';
  static const String review = 'review';
  static const String reparsePending = 'reparse_pending';
}

/// Diag codes (fixed set, design note §12).
abstract final class IngestDiag {
  static const String dupHash = 'ING_DUP_HASH';

  /// The `body_hash` unique index caught a copy the dedupe-1 read missed
  /// (should not happen inside BEGIN IMMEDIATE; the backstop).
  static const String dupRace = 'ING_DUP_RACE';
  static const String mergeCrossChannel = 'ING_MERGE_XCH';
  static const String mergePending = 'ING_MERGE_PENDING';
  static const String messageFailed = 'ING_MSG_FAILED';
  static const String configInvalid = 'ING_CONFIG_INVALID';

  /// CR-1/F2: a message that failed alone was stored for review.
  static const String quarantined = 'ING_QUARANTINED';

  /// CR-1/F2: a message could not be stored even alone (kept in the spool).
  static const String kept = 'ING_KEPT';

  /// `ING_DROP_<REASON>` with the drop reason upper-cased.
  static String drop(String reason) => 'ING_DROP_${reason.toUpperCase()}';
}

typedef IngestClock = DateTime Function();
typedef IngestIdGenerator = String Function();

final class IngestRawMessages {
  IngestRawMessages({
    required this._store,
    required this._pipeline,
    required this._guardBase,
    required this._accounts,
    required this._newCategorizer,
    required this._newId,
    IngestClock? clock,
    LocalZone? zone,
    this._cycleKeyOf,
    List<PostPersistHook> hooks = const [],
    this._diag = const NoDiag(),
    this._events,
  }) : _now = clock ?? DateTime.now,
       _zone = zone ?? const _UtcZone(),
       _hooks = List.unmodifiable(hooks);

  final IngestStorePort _store;
  final ParsingPipeline _pipeline;
  final GuardConfigSource _guardBase;
  final AccountsRepository _accounts;
  final CategorizerFactory _newCategorizer;
  final IngestIdGenerator _newId;
  final IngestClock _now;
  final LocalZone _zone;
  final CycleKeyOf? _cycleKeyOf;
  final List<PostPersistHook> _hooks;
  final DiagSink _diag;
  final DomainEventBus? _events;

  List<int>? _baseBytes;
  GuardConfig? _baseConfig;
  final List<(List<int>, CaptureGuard)> _guardCache = [];
  CaptureGuard? _baseGuard;

  /// The payday schedule in force (T-051): `payday_eras`, reconciled with
  /// `payday_day` as `PaydayScheduleStore` does.
  PaydaySchedule _scheduleOf(BatchContext ctx) {
    final ms = _nowMs();
    return PaydaySchedule.resolve(
      erasJson: ctx.paydayEras,
      paydayDay: paydayDayOf(ctx.paydayDay),
      today: CivilDate.fromLocalMs(ms, _zone.offsetAtInstant(ms)),
    );
  }

  int _nowMs() => _now().toUtc().millisecondsSinceEpoch;

  /// Ingests [batch] in one write transaction. Throws [IngestBatchFailed]
  /// when nothing of it may be acked (CONFIG_INVALID, a transient database
  /// failure, an oversized batch).
  ///
  /// CR-1/F2: when the batch transaction fails with an error that is not
  /// transient, its messages are retried one per transaction, and one that
  /// still fails is stored alone for review (`ingestFailed`), so one poison
  /// message never blocks the others or the spool behind them. A message
  /// that can't be stored even that way is left out of `ackable` (kept in
  /// the spool, never deleted) and listed in [IngestBatchResult.kept].
  Future<IngestBatchResult> call(List<IncomingMessage> batch) async {
    if (batch.isEmpty) return IngestBatchResult.empty;
    if (batch.length > kMaxIngestBatch) {
      throw IngestBatchFailed(IngestBatchFailed.tooLarge);
    }
    // §9: an unusable base stops the batch before the transaction; nothing
    // is acked, so a build defect can't delete captured messages.
    if (batch.any((m) => m.origin.isBackground) && _base() == null) {
      _diag.count(IngestDiag.configInvalid, 1);
      throw IngestBatchFailed(IngestBatchFailed.configInvalid);
    }
    // Pure work outside the transaction (§2a, §2b).
    final prepared = [for (final m in batch) _prepare(m)];
    // §8: one categorizer per batch, made before BEGIN.
    final categorizer = await _guarded(_newCategorizer);
    final _BatchState state;
    try {
      state = await _run(prepared, categorizer);
    } on IngestBatchFailed catch (e) {
      if (!_isolatable(e)) rethrow;
      return _isolate(batch, prepared, categorizer, e.code);
    }
    // Committed.
    return _finish(batch, state);
  }

  /// Failures a per-message retry can get past (a defect or an unstorable
  /// message). Transient and configuration failures can't.
  static bool _isolatable(IngestBatchFailed e) =>
      !e.isTransient &&
      e.code != IngestBatchFailed.configInvalid &&
      e.code != IngestBatchFailed.tooLarge;

  /// Runs [body], mapping every error to an [IngestBatchFailed] code (never
  /// the error's text).
  static Future<T> _guarded<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on IngestBatchFailed {
      rethrow;
    } on DbWriteException catch (e) {
      throw IngestBatchFailed(
        e.code == DbWriteException.writeFailed
            ? IngestBatchFailed.writeFailed
            : IngestBatchFailed.unstorable,
      );
    } on DbReadException {
      throw IngestBatchFailed(IngestBatchFailed.readFailed);
    } on Object {
      throw IngestBatchFailed(IngestBatchFailed.internal);
    }
  }

  /// One write transaction over [prepared] (§2, §10).
  Future<_BatchState> _run(
    List<_Prepared> prepared,
    Categorizer categorizer,
  ) async {
    final state = _BatchState();
    await _guarded(
      () => _store.inWriteTransaction(() async {
        final ctx = await _store.readContext();
        state.schedule = _scheduleOf(ctx);
        final guard = _guardFor(ctx);
        final scope = _BatchScope(
          ctx,
          _LabelLanguage.of(ctx.language),
          categorizer,
        );
        for (final p in prepared) {
          if (state.outcomes.containsKey(p.m.deliveryId)) continue;
          final local = _Changes();
          final outcome = await _one(p, scope, guard, local);
          state.outcomes[p.m.deliveryId] = outcome;
          state.changes.addAll(local);
        }
      }),
    );
    return state;
  }

  /// CR-1/F2: one transaction per message; a message that still fails is
  /// quarantined (stored alone for review); one that can't be stored even
  /// so is kept in the spool. A transient failure stops here: what already
  /// committed is published, nothing is acked, and its re-delivery is a
  /// `duplicate`.
  Future<IngestBatchResult> _isolate(
    List<IncomingMessage> batch,
    List<_Prepared> prepared,
    Categorizer categorizer,
    String batchCode,
  ) async {
    final total = _BatchState();
    final kept = <String>[];
    try {
      for (final p in prepared) {
        final id = p.m.deliveryId;
        if (total.outcomes.containsKey(id) || kept.contains(id)) continue;
        _BatchState one;
        try {
          // A batch of one already failed alone.
          if (prepared.length == 1) throw IngestBatchFailed(batchCode);
          one = await _run([p], categorizer);
        } on IngestBatchFailed catch (e) {
          if (!_isolatable(e)) rethrow;
          try {
            one = await _quarantine(p, e.code);
          } on IngestBatchFailed catch (e2) {
            if (!_isolatable(e2)) rethrow;
            _diag.count(IngestDiag.kept, 1);
            kept.add(id);
            continue;
          }
        }
        total.addAll(one);
      }
    } on IngestBatchFailed {
      if (total.outcomes.isNotEmpty) _finish(batch, total, kept: kept);
      rethrow;
    }
    return _finish(batch, total, kept: kept);
  }

  /// Stores [p] alone as raw `review` + an `unrecognized` item (`reason:
  /// ingestFailed`, [code] only), in its own transaction. The Guard
  /// re-check, the stage-0 drop and dedupe 1 still come first (an OTP is
  /// never stored; a committed copy stays a duplicate). No account,
  /// categorizer, merge or hook runs.
  Future<_BatchState> _quarantine(_Prepared p, String code) async {
    final state = _BatchState();
    await _guarded(
      () => _store.inWriteTransaction(() async {
        final ctx = await _store.readContext();
        state.schedule = _scheduleOf(ctx);
        final local = _Changes();
        final pre = await _precheck(p, _guardFor(ctx), local);
        IngestOutcome outcome;
        if (pre != null) {
          outcome = pre;
        } else {
          try {
            outcome = await _store.inSavepoint(
              () => _storeFailed(p, p.result, code),
            );
            local.diag(IngestDiag.quarantined);
          } on _RaceLost {
            outcome = const IngestDuplicate();
          }
        }
        state.outcomes[p.m.deliveryId] = outcome;
        state.changes.addAll(local);
      }),
    );
    return state;
  }

  // ---------------------------------------------------------------------
  // T-076: re-parse of a stored message.

  /// Parses the stored [row] again with the current registry and applies
  /// what changed, in one write transaction. Skips the Guard and dedupe 1
  /// (the row is already stored); dedupe 2 and the pending/settled merge
  /// still apply. Rules:
  /// - `review` / `reparse_pending` row that now parses into a transaction
  ///   (or a balance notice): the SAME raw row becomes `parsed` (its open
  ///   review items resolve) and the normal pipeline writes the
  ///   transaction. Anything that would again end in review, or still has
  ///   no handler, changes nothing and creates no review item (FU-109:
  ///   a personal-origin message never enters review; the origin is not
  ///   stored, so a re-parse never creates review items itself). A match
  ///   in the pending/settled merge only promotes the raw row: the matched
  ///   transaction (amount, status, fields) is never written in re-parse
  ///   mode, so no review item comes from the merge either.
  /// - `parsed` row whose template changed: only the NULL fields of its
  ///   transaction are filled (the cross-channel attach rule), and only
  ///   when that transaction is live, not user-verified, not part of a
  ///   transfer pair and consistent with the new parse. Amount, direction,
  ///   status and category are never changed.
  /// - A user-verified or deleted transaction is never written.
  /// - Nothing is ever deleted.
  /// A row the user or another engine changed since it was read is skipped
  /// (the status guard of [IngestStorePort.promoteRaw]).
  Future<ReparseResult> reparse(StoredRaw row) async {
    final p = _prepare(
      IncomingMessage(
        deliveryId: row.id,
        channel: row.channel,
        source: row.sender ?? '',
        body: row.body,
        receivedAtMs: row.receivedAtMs,
        simSlot: row.simSlot,
        origin: MessageOrigin.reparse,
      ),
      existing: row,
    );
    final categorizer = await _guarded(_newCategorizer);
    final state = _BatchState();
    var outcome = ReparseOutcome.unchanged;
    await _guarded(
      () => _store.inWriteTransaction(() async {
        final ctx = await _store.readContext();
        state.schedule = _scheduleOf(ctx);
        final scope = _BatchScope(
          ctx,
          _LabelLanguage.of(ctx.language),
          categorizer,
        );
        final local = _Changes();
        try {
          outcome = await _store.inSavepoint(
            () => _reparseOne(p, row, scope, local),
          );
          state.changes.addAll(local);
        } on _RaceLost {
          outcome = ReparseOutcome.skipped;
        }
      }),
    );
    final done = _finish(const [], state);
    return ReparseResult(outcome, done.changedTxnIds);
  }

  Future<ReparseOutcome> _reparseOne(
    _Prepared p,
    StoredRaw row,
    _BatchScope b,
    _Changes local,
  ) async {
    final result = p.result;
    final registryVersion = _pipeline.registry.registryVersion;
    // Anything but a clean transaction or balance notice: no change. A
    // review or parsed row is stamped so the next start skips it; a
    // pending row is retried next time.
    final CreateTxn? create;
    final bool balanceOnly;
    if (result is ParseParsed && p.txnSource != null) {
      final d = dispositionOf(result.event, result.direction);
      create = d is CreateTxn && result.fields.amount != null ? d : null;
      balanceOnly = d is BalanceOnlyEvent;
    } else {
      create = null;
      balanceOnly = false;
    }
    Future<ReparseOutcome> stamp() async {
      if (row.parseStatus == RawStatus.reparsePending) {
        return ReparseOutcome.unchanged;
      }
      final done = await _store.promoteRaw(
        PromoteRaw(
          id: row.id,
          fromStatus: row.parseStatus,
          toStatus: row.parseStatus,
          registryVersion: registryVersion,
          atMs: _nowMs(),
        ),
      );
      return done ? ReparseOutcome.unchanged : ReparseOutcome.skipped;
    }

    if (row.parseStatus == RawStatus.parsed) {
      if (result is! ParseParsed || create == null) return stamp();
      final changed =
          result.templateId != row.templateId ||
          result.templateVersion != row.templateVersion;
      if (!changed) return stamp();
      final target = await _store.txnOfRaw(row.id);
      final t = target?.candidate;
      final amount = result.fields.amount;
      if (target == null ||
          t == null ||
          amount == null ||
          target.linked ||
          t.isUserVerified ||
          t.isDeleted ||
          t.direction != create.direction ||
          t.status != create.status ||
          t.amount != amount) {
        return stamp();
      }
      // Stamp first (conditional on the row's state), then fill.
      final done = await _store.promoteRaw(
        PromoteRaw(
          id: row.id,
          fromStatus: RawStatus.parsed,
          toStatus: RawStatus.parsed,
          registryVersion: registryVersion,
          atMs: _nowMs(),
          institutionCode: result.institutionCode,
          templateId: result.templateId,
          templateVersion: result.templateVersion,
        ),
      );
      if (!done) throw const _RaceLost();
      await _attach(
        local,
        b,
        t,
        result,
        _occurred(result.fields.occurredAt).$1,
      );
      return local.txns.isEmpty
          ? ReparseOutcome.unchanged
          : ReparseOutcome.updated;
    }

    // review / reparse_pending.
    if (create == null && !balanceOnly) return stamp();
    final outcome = await _persist(p, b, local, result);
    return switch (outcome) {
      IngestInserted() ||
      IngestMergedCrossChannel() ||
      IngestMergedPending() ||
      IngestBalanceOnly() => ReparseOutcome.converted,
      _ => throw const _RaceLost(),
    };
  }

  // ---------------------------------------------------------------------
  // Before the transaction.

  GuardConfig? _base() {
    if (_baseBytes != null) return _baseConfig;
    final bytes = List<int>.unmodifiable(_guardBase.baseBytes());
    _baseBytes = bytes;
    final load = parseGuardConfig(bytes);
    _baseConfig = load.mode == GuardConfigMode.invalid ? null : load.config;
    return _baseConfig;
  }

  _Prepared _prepare(IncomingMessage m, {StoredRaw? existing}) {
    final regChannel = _registryChannelOf(m);
    final wallOffset = _zone.offsetAtInstant(m.receivedAtMs);
    final receivedWall = DateTime.fromMillisecondsSinceEpoch(
      m.receivedAtMs + clampTzOffset(wallOffset) * 60000,
      isUtc: true,
    );
    ParseResult result;
    if (regChannel == null) {
      result = const ParseUnrecognized(UnrecognizedReason.unknownSource);
    } else {
      try {
        result = _pipeline.parse(
          ParseRequest(
            body: m.body,
            source: m.source,
            channel: regChannel,
            receivedAt: receivedWall,
          ),
        );
      } on Object {
        result = const ParseUnrecognized(UnrecognizedReason.internalError);
      }
    }
    final senderKey = senderKeyOf(m.channel, m.source);
    return _Prepared(
      m: m,
      result: result,
      senderKey: senderKey,
      bodyHash: bodyHashV1(senderKey: senderKey, body: m.body),
      txnSource: txnSourceOf(m.channel),
      existing: existing,
    );
  }

  /// The parser channel. Background messages keep their own channel (the
  /// Guard drops anything else); user-confirmed paste/OCR/PDF/CSV text is
  /// parsed like a share.
  static RegistryChannel? _registryChannelOf(IncomingMessage m) {
    final direct = RegistryChannel.fromWire(m.channel);
    if (direct != null) return direct;
    if (m.origin == MessageOrigin.userConfirmed &&
        txnSourceOf(m.channel) != null) {
      return RegistryChannel.share;
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Step 0: the Guard (§9).

  _Guard? _guardFor(BatchContext ctx) {
    final base = _baseConfig;
    final baseBytes = _baseBytes;
    if (base == null || baseBytes == null) return null;
    final version = base.registryVersion;
    final rules = [
      for (final r in ctx.ignoreRules)
        GuardIgnoreRuleInput(
          institutionCode: r.institutionCode,
          last4: r.last4,
          channel: r.channel,
        ),
    ];
    final always = [
      for (final s in ctx.captureSenders)
        if (s.alwaysCapture)
          GuardUserSenderInput(sender: s.sender, channel: s.channel),
    ];
    final custom = [
      for (final (sender, channel) in ctx.customTemplateSenders)
        GuardUserSenderInput(sender: sender, channel: channel),
    ];
    final full = _guardWith(baseBytes, version, rules, always, custom);
    if (full != null) return _Guard(full);

    // F1: the user part can't be built as a whole (a row the Guard can't
    // express, or a cap). Never switch the user's keeps off: leave out only
    // the rows the builder rejects one by one, and check every registry keep
    // against the database ignore rules (which also covers the rules left
    // out). If the senders still don't fit, a sender the user asked to
    // capture is kept in Dart when the base Guard calls it not financial.
    final okRules = [
      for (final r in rules)
        if (_ruleOk(version, r)) r,
    ];
    final okSenders = [
      for (final s in always)
        if (_senderOk(version, s)) s,
      if (kCaptureCustomTemplateSendersWithoutGold)
        for (final s in custom)
          if (_senderOk(version, s)) s,
    ];
    final withRules = _guardWith(
      baseBytes,
      version,
      okRules,
      okSenders,
      const [],
    );
    if (withRules != null) return _Guard(withRules, dbIgnoreCheck: true);
    final sendersOnly = _guardWith(
      baseBytes,
      version,
      const [],
      okSenders,
      const [],
    );
    if (sendersOnly != null) return _Guard(sendersOnly, dbIgnoreCheck: true);
    return _Guard(
      _baseGuard ??= CaptureGuard(base),
      dbIgnoreCheck: true,
      userSenders: {
        for (final s in okSenders)
          if (GuardChannel.fromWire(s.channel) case final ch?)
            (ch.wire, guardSourceKey(ch, s.sender)),
      },
    );
  }

  /// The Guard over the base plus a user part built from these rows, or
  /// null when the builder or the loader rejects it. The last few built
  /// guards are cached by their user bytes (the rows rarely change).
  CaptureGuard? _guardWith(
    List<int> baseBytes,
    int version,
    List<GuardIgnoreRuleInput> rules,
    List<GuardUserSenderInput> always,
    List<GuardUserSenderInput> custom,
  ) {
    final built = buildGuardUserConfig(
      baseRegistryVersion: version,
      ignoreRules: rules,
      alwaysCaptureSenders: always,
      customTemplateSenders: custom,
      goldActive: false,
    );
    final userBytes = built.bytes;
    if (userBytes == null) return null;
    for (final (bytes, guard) in _guardCache) {
      if (_sameBytes(bytes, userBytes)) return guard;
    }
    final load = parseGuardConfig(baseBytes, userBytes);
    if (load.mode != GuardConfigMode.full) return null;
    final guard = CaptureGuard(load.config);
    _guardCache.add((userBytes, guard));
    if (_guardCache.length > 2) _guardCache.removeAt(0);
    return guard;
  }

  static bool _ruleOk(int version, GuardIgnoreRuleInput r) =>
      buildGuardUserConfig(
        baseRegistryVersion: version,
        ignoreRules: [r],
        alwaysCaptureSenders: const [],
        customTemplateSenders: const [],
        goldActive: false,
      ).ok;

  static bool _senderOk(int version, GuardUserSenderInput s) =>
      buildGuardUserConfig(
        baseRegistryVersion: version,
        ignoreRules: const [],
        alwaysCaptureSenders: [s],
        customTemplateSenders: const [],
        goldActive: false,
      ).ok;

  static bool _sameBytes(List<int>? a, List<int> b) {
    if (a == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ---------------------------------------------------------------------
  // One message.

  Future<IngestOutcome> _one(
    _Prepared p,
    _BatchScope b,
    _Guard? guard,
    _Changes local,
  ) async {
    final pre = await _precheck(p, guard, local);
    if (pre != null) return pre;
    final result = p.result;
    try {
      return await _store.inSavepoint(() => _persist(p, b, local, result));
    } on _RaceLost {
      local.clear();
      local.diag(IngestDiag.dupRace);
      return const IngestDuplicate();
    } on Object catch (e) {
      if (!_isMessageLevel(e)) rethrow;
      // §10: the message alone goes to review; the batch continues.
      local.clear();
      local.diag(IngestDiag.messageFailed);
      try {
        return await _store.inSavepoint(
          () => _storeFailed(
            p,
            result,
            e is SafeException ? e.code : 'INGEST_FAILED',
          ),
        );
      } on _RaceLost {
        return const IngestDuplicate();
      } on IngestBatchFailed {
        rethrow;
      } on DbWriteException catch (e2) {
        if (e2.code == DbWriteException.writeFailed) rethrow;
        throw IngestBatchFailed(IngestBatchFailed.unstorable);
      }
    }
  }

  /// Steps 1 to 3 (Guard re-check, stage-0 drop, dedupe 1): the outcome
  /// when the message stops here, else null.
  Future<IngestOutcome?> _precheck(
    _Prepared p,
    _Guard? guard,
    _Changes local,
  ) async {
    final m = p.m;
    // (1) Guard re-check, background origins only.
    if (m.origin.isBackground) {
      if (guard == null) {
        throw IngestBatchFailed(IngestBatchFailed.configInvalid);
      }
      final decision = guard.guard.decide(
        channel: m.channel,
        source: m.source,
        body: m.body,
      );
      if (decision is GuardDrop &&
          !(decision.reason == GuardDropReason.notFinancial &&
              m.origin != MessageOrigin.inboxScanPersonal &&
              guard.isUserSender(m.channel, m.source))) {
        return _dropped(decision.reason.wire, local);
      }
      if (guard.dbIgnoreCheck && decision is GuardKeep) {
        final inst = decision.inst;
        final channel = GuardChannel.fromWire(m.channel);
        final ignoreChannel = channel == null
            ? null
            : guardIgnoreChannel(channel);
        if (inst != null &&
            ignoreChannel != null &&
            await _store.isIgnored(
              institutionCode: inst,
              last4: decision.last4,
              channel: ignoreChannel.wire,
            )) {
          return _dropped('ignored_rule', local);
        }
      }
    }
    if (p.txnSource == null) return _dropped('unknown_channel', local);
    // (2) Stage-0 drop (OTP / promotion): nothing is written.
    final result = p.result;
    if (result is ParseDropped) {
      return _dropped(
        result.reason == DropReason.globalPattern
            ? 'parser_global'
            : 'parser_institution',
        local,
      );
    }
    // (3) Dedupe 1.
    if (await _store.hashExists(p.bodyHash)) {
      local.diag(IngestDiag.dupHash);
      return const IngestDuplicate();
    }
    return null;
  }

  IngestOutcome _dropped(String reason, _Changes local) {
    local.diag(IngestDiag.drop(reason));
    return IngestDropped(reason);
  }

  static bool _isMessageLevel(Object e) =>
      (e is DbWriteException && e.code != DbWriteException.writeFailed) ||
      e is AccountsException ||
      e is TransactionsException ||
      e is CurrencyMismatch ||
      e is MoneyOverflow ||
      e is CorruptMoney ||
      e is UnknownCurrency;

  Future<IngestOutcome> _storeFailed(
    _Prepared p,
    ParseResult result,
    String code,
  ) async {
    // FU-109: a personal-origin message never enters the review queue.
    if (p.m.origin == MessageOrigin.inboxScanPersonal) {
      return const IngestDropped('personal_unparsed');
    }
    final rawId = await _insertRaw(
      p,
      status: RawStatus.review,
      institution: _institutionOf(result),
      templateId: _templateIdOf(result),
    );
    await _review(
      kind: ReviewKind.unrecognized,
      rawId: rawId,
      payload: {'reason': 'ingestFailed', 'code': code},
    );
    return IngestReview(rawId, ReviewKind.unrecognized);
  }

  static String? _institutionOf(ParseResult r) => switch (r) {
    ParseParsed(:final institutionCode) => institutionCode,
    ParseUnrecognized(:final institutionCode) => institutionCode,
    _ => null,
  };

  static String? _templateIdOf(ParseResult r) => switch (r) {
    ParseParsed(:final templateId) => templateId,
    ParseUnrecognized(:final templateId) => templateId,
    _ => null,
  };

  Future<IngestOutcome> _persist(
    _Prepared p,
    _BatchScope b,
    _Changes local,
    ParseResult result,
  ) async {
    if (p.m.origin == MessageOrigin.inboxScanPersonal &&
        _wouldGoToReview(result)) {
      // FU-109 M-1: a personal sender's message that is not a clean
      // transaction is not stored at all.
      return const IngestDropped('personal_unparsed');
    }
    switch (result) {
      case ParseDropped():
        // Handled before the savepoint.
        return const IngestDropped('parser_global');
      case ParseUnrecognized():
        return _unrecognized(p, result);
      case ParseGeneric():
        return _generic(p, b, local, result);
      case ParseParsed():
        return switch (dispositionOf(result.event, result.direction)) {
          CreateTxn(:final direction, :final status) => _parsed(
            p,
            b,
            local,
            result,
            direction,
            status,
          ),
          BalanceOnlyEvent() => _balanceOnly(p, b.labels, local, result),
          DeferredEvent() => _deferred(p, result),
          UndirectedEvent() => _undirected(p, result),
        };
    }
  }

  /// True for the results that end in a review item (or a stored review raw
  /// row) instead of a transaction, balance or deferred row.
  static bool _wouldGoToReview(ParseResult r) => switch (r) {
    ParseUnrecognized() || ParseGeneric() => true,
    ParseParsed() => dispositionOf(r.event, r.direction) is UndirectedEvent,
    ParseDropped() => false,
  };

  Future<IngestOutcome> _unrecognized(_Prepared p, ParseUnrecognized r) async {
    final rawId = await _insertRaw(
      p,
      status: RawStatus.review,
      institution: r.institutionCode,
      templateId: r.templateId,
    );
    await _review(
      kind: ReviewKind.unrecognized,
      rawId: rawId,
      payload: {
        'reason': r.reason.name,
        'institutionCode': ?r.institutionCode,
        'templateId': ?r.templateId,
      },
    );
    return IngestReview(rawId, ReviewKind.unrecognized);
  }

  Future<IngestOutcome> _deferred(_Prepared p, ParseParsed r) async {
    final rawId = await _insertRaw(
      p,
      status: RawStatus.reparsePending,
      institution: r.institutionCode,
      templateId: r.templateId,
      templateVersion: r.templateVersion,
    );
    return IngestDeferred(rawId);
  }

  Future<IngestOutcome> _undirected(_Prepared p, ParseParsed r) async {
    final rawId = await _insertRaw(
      p,
      status: RawStatus.review,
      institution: r.institutionCode,
      templateId: r.templateId,
      templateVersion: r.templateVersion,
    );
    await _review(
      kind: ReviewKind.unrecognized,
      rawId: rawId,
      payload: {
        'reason': 'directionUnknown',
        'institutionCode': r.institutionCode,
        'templateId': r.templateId,
      },
    );
    return IngestReview(rawId, ReviewKind.unrecognized);
  }

  Future<IngestOutcome> _balanceOnly(
    _Prepared p,
    _LabelLanguage labels,
    _Changes local,
    ParseParsed r,
  ) async {
    final rawId = await _insertRaw(
      p,
      status: RawStatus.parsed,
      institution: r.institutionCode,
      templateId: r.templateId,
      templateVersion: r.templateVersion,
    );
    final f = r.fields;
    final first = f.balance ?? f.available;
    if (first != null) {
      final account = await _resolve(
        local,
        institution: r.institutionCode,
        last4: f.last4,
        currency: first.currency,
        label: labels.institutionLabel(_pipeline.registry, r.institutionCode),
        kind: inferAccountKind(
          event: r.event.wire,
          balanceIsAvailableLimit: f.balanceIsAvailableLimit,
          hasLast4: f.last4 != null,
        ),
      );
      await _recordBalance(
        local,
        accountId: account.id,
        occurredAtMs: _occurred(f.occurredAt).$1,
        balance: f.balance,
        available: f.available,
      );
    }
    return IngestBalanceOnly(rawId);
  }

  // ---------------------------------------------------------------------
  // Parsed transactions (§4–§8).

  Future<IngestOutcome> _parsed(
    _Prepared p,
    _BatchScope b,
    _Changes local,
    ParseParsed r,
    TxnDirection direction,
    TxnStatus status,
  ) async {
    final f = r.fields;
    final amount = f.amount;
    if (amount == null) {
      // A template event that needs an amount came without one.
      return _unrecognized(
        p,
        ParseUnrecognized(
          UnrecognizedReason.invalidAmount,
          institutionCode: r.institutionCode,
          templateId: r.templateId,
        ),
      );
    }
    final userConfirmed = p.m.origin == MessageOrigin.userConfirmed;
    final inst = r.institutionCode;
    final (occurredMs, offsetMin) = _occurred(f.occurredAt);
    final dedupeKey = dedupeKeyOf(inst, direction, amount);
    final merchantNorm = _nonEmpty(f.merchant?.key);
    final labels = b.labels;

    // (6) Dedupe 2, cross-channel.
    final candidates = await _store.crossChannelCandidates(
      dedupeKey: dedupeKey,
      fromMs: occurredMs - kCrossChannelFetchMs,
      toMs: occurredMs + kCrossChannelFetchMs,
    );
    final matches = crossChannelMatches(
      NewTxnKeys(
        source: p.txnSource!.code,
        status: status,
        occurredAtMs: occurredMs,
        receivedAtMs: p.m.receivedAtMs,
        last4: f.last4,
      ),
      candidates,
    );
    if (userConfirmed && matches.isNotEmpty) {
      // §11: never auto-merge user input; the screen asks.
      return IngestPossibleDuplicate([for (final c in matches) c.id]);
    }
    if (matches.length == 1) {
      final target = matches.single;
      // Raw first (CR-6 backstop), then the attach.
      await _insertRaw(
        p,
        status: RawStatus.parsed,
        institution: inst,
        templateId: r.templateId,
        templateVersion: r.templateVersion,
      );
      await _attach(local, b, target, r, occurredMs);
      local.diag(IngestDiag.mergeCrossChannel);
      return IngestMergedCrossChannel(target.id);
    }
    final possibleDuplicates = [for (final c in matches) c.id];

    // (7) Pending / settled (A-63, EC-54), both arrival orders.
    if (!userConfirmed &&
        possibleDuplicates.isEmpty &&
        direction == TxnDirection.expense &&
        (status == TxnStatus.posted || status == TxnStatus.pending)) {
      final newIsPending = status == TxnStatus.pending;
      final found = await _store.statusCandidates(
        institution: inst,
        currency: amount.currency.code,
        status: newIsPending ? TxnStatus.posted.code : TxnStatus.pending.code,
        fromMs: newIsPending
            ? occurredMs - kPendingSlackMs
            : occurredMs - kPendingWindowMs,
        toMs: newIsPending
            ? occurredMs + kPendingWindowMs
            : occurredMs + kPendingSlackMs,
      );
      final pick = pickPendingMatch(
        newAmountMinor: amount.minor,
        newIsPending: newIsPending,
        candidates: [
          for (final c in found)
            if (last4Compatible(f.last4, c.accountLast4) &&
                merchantCompatible(merchantNorm, c.merchantNorm))
              c,
        ],
      );
      if (pick != null) {
        // Raw first (CR-6 backstop), then the merge.
        await _insertRaw(
          p,
          status: RawStatus.parsed,
          institution: inst,
          templateId: r.templateId,
          templateVersion: r.templateVersion,
        );
        if (p.m.origin == MessageOrigin.reparse) {
          // Re-parse: never touch an existing transaction (user-verified or
          // not); the raw row is only promoted above.
        } else if (newIsPending) {
          // A late pending message: the payment is already posted.
          await _attach(local, b, pick, r, occurredMs);
        } else {
          await _settle(local, pick, r, amount, occurredMs);
        }
        local.diag(IngestDiag.mergePending);
        return IngestMergedPending(pick.id);
      }
    }

    // (8) Account.
    final account = await _resolve(
      local,
      institution: inst,
      last4: f.last4,
      currency: amount.currency,
      label: labels.institutionLabel(_pipeline.registry, inst),
      kind: inferAccountKind(
        event: r.event.wire,
        balanceIsAvailableLimit: f.balanceIsAvailableLimit,
        hasLast4: f.last4 != null,
      ),
    );
    // (9) Categorize.
    final counterparty = _counterpartyOf(f.counterparty);
    final merchantRaw = _nonEmpty(f.merchant?.display);
    final category = await _categorize(
      b.categorizer,
      merchantRaw: merchantRaw,
      merchantNorm: merchantNorm,
      counterpartyKind: counterparty?.$1,
      counterpartyValue: counterparty?.$2,
    );
    // (10) Raw + transaction; raw first (CR-6 backstop).
    final rawId = await _insertRaw(
      p,
      status: RawStatus.parsed,
      institution: inst,
      templateId: r.templateId,
      templateVersion: r.templateVersion,
    );
    final txnId = _newId();
    final balance = f.balance;
    await _store.insertTxn(
      TxnInsert(
        id: txnId,
        accountId: account.id,
        rawMessageId: rawId,
        source: p.txnSource!,
        direction: direction,
        status: status,
        amount: amount,
        originalAmount: f.originalAmount,
        occurredAtMs: occurredMs,
        tzOffsetMin: offsetMin,
        merchantRaw: merchantRaw,
        merchantNorm: merchantNorm,
        catalogMerchantId: category.catalogMerchantId,
        counterpartyKind: counterparty?.$1,
        counterpartyValue: counterparty?.$2,
        categoryId: category.categoryId,
        categorySource: category.source,
        isUserVerified: userConfirmed,
        referenceNo: _nonEmpty(f.ref),
        balanceAfterMinor:
            balance != null && balance.currency == amount.currency
            ? balance.minor
            : null,
        templateId: r.templateId,
        parseConfidencePermille: r.confidencePermille,
        dedupeKey: dedupeKey,
        createdAtMs: _nowMs(),
      ),
    );
    local.txn(txnId, account.id, occurredMs, offsetMin);
    // (11) Balance (newest wins; never summed or converted).
    await _recordBalance(
      local,
      accountId: account.id,
      occurredAtMs: occurredMs,
      balance: f.balance,
      available: f.available,
      sourceTxnId: txnId,
    );
    // (12) Review items.
    if (possibleDuplicates.isNotEmpty) {
      await _review(
        kind: ReviewKind.lowConfidence,
        rawId: rawId,
        txnId: txnId,
        payload: {
          'reason': 'possibleDuplicate',
          'candidateTxnIds': possibleDuplicates,
        },
      );
    }
    if (r.needsReview) {
      await _review(
        kind: ReviewKind.lowConfidence,
        rawId: rawId,
        txnId: txnId,
        payload: {
          'reason': 'lowConfidence',
          'confidencePermille': r.confidencePermille,
          'reasons': [for (final x in r.reasons) x.name],
        },
      );
    }
    // (13) Hooks.
    await _runHooks(txnId, account.id, inserted: true);
    return IngestInserted(txnId);
  }

  /// Cross-channel attach (§5) and the symmetric late-pending attach: only
  /// NULL fields of [target] are filled; a user-verified or soft-deleted
  /// target is never modified (a deleted payment stays exactly as the user
  /// left it). The new message's balance is recorded either way.
  Future<void> _attach(
    _Changes local,
    _BatchScope b,
    TxnCandidate target,
    ParseParsed r,
    int occurredMs,
  ) async {
    final f = r.fields;
    var accountId = target.accountId;
    if (!target.isUserVerified && !target.isDeleted) {
      String? moveTo;
      if (target.accountLast4 == null && f.last4 != null) {
        final card = await _resolve(
          local,
          institution: r.institutionCode,
          last4: f.last4,
          currency: target.amount.currency,
          label: b.labels.institutionLabel(
            _pipeline.registry,
            r.institutionCode,
          ),
          kind: inferAccountKind(
            event: r.event.wire,
            balanceIsAvailableLimit: f.balanceIsAvailableLimit,
            hasLast4: true,
          ),
        );
        if (card.id != target.accountId) moveTo = card.id;
      }
      final merchantNorm = _nonEmpty(f.merchant?.key);
      final merchantRaw = _nonEmpty(f.merchant?.display);
      final gainsMerchant = target.merchantNorm == null && merchantNorm != null;
      final counterparty = target.counterpartyValue == null
          ? _counterpartyOf(f.counterparty)
          : null;
      _Category? category;
      if (target.categorySource == CategorySource.none &&
          (gainsMerchant || counterparty != null)) {
        final c = await _categorize(
          b.categorizer,
          merchantRaw: target.merchantRaw ?? merchantRaw,
          merchantNorm: target.merchantNorm ?? merchantNorm,
          counterpartyKind: target.counterpartyValue != null
              ? target.counterpartyKind
              : counterparty?.$1,
          counterpartyValue: target.counterpartyValue ?? counterparty?.$2,
        );
        if (c.source != CategorySource.none) category = c;
      }
      final balance = f.balance;
      final confidence = target.parseConfidencePermille;
      final patch = TxnPatch(
        accountId: moveTo,
        originalAmount: target.originalAmount == null ? f.originalAmount : null,
        merchantRaw: target.merchantRaw == null ? merchantRaw : null,
        merchantNorm: gainsMerchant ? merchantNorm : null,
        counterpartyKind: counterparty?.$1,
        counterpartyValue: counterparty?.$2,
        referenceNo: target.referenceNo == null ? _nonEmpty(f.ref) : null,
        balanceAfterMinor:
            target.balanceAfterMinor == null &&
                balance != null &&
                balance.currency == target.amount.currency
            ? balance.minor
            : null,
        parseConfidencePermille:
            confidence == null || r.confidencePermille > confidence
            ? r.confidencePermille
            : null,
        categoryId: category?.categoryId,
        categorySource: category?.source,
        catalogMerchantId: category?.catalogMerchantId,
      );
      if (!patch.isEmpty) {
        await _store.updateTxn(target.id, patch, atMs: _nowMs());
        local.txn(
          target.id,
          target.accountId,
          target.occurredAtMs,
          target.tzOffsetMin,
        );
        if (moveTo != null) {
          accountId = moveTo;
          local.txn(target.id, moveTo, target.occurredAtMs, target.tzOffsetMin);
        }
      }
    }
    await _recordBalance(
      local,
      accountId: accountId,
      occurredAtMs: occurredMs,
      balance: f.balance,
      available: f.available,
      sourceTxnId: target.id,
    );
    await _runHooks(target.id, accountId, inserted: false);
  }

  /// A settled (or posted) message for pending [p] (A-63): P gets the
  /// settled amount, the original amount if given, status `posted`, and its
  /// NULL fields filled. A user-verified P only changes status (plus a
  /// review item when the amounts differ).
  Future<void> _settle(
    _Changes local,
    TxnCandidate p,
    ParseParsed r,
    Money amount,
    int occurredMs,
  ) async {
    final f = r.fields;
    final now = _nowMs();
    final amountDiffers = amount != p.amount;
    if (p.isUserVerified) {
      await _store.updateTxn(
        p.id,
        const TxnPatch(status: TxnStatus.posted),
        atMs: now,
      );
      if (amountDiffers) {
        await _review(
          kind: ReviewKind.lowConfidence,
          txnId: p.id,
          payload: {
            'reason': 'settledAmountDiffers',
            'settledAmount': amount.toJson(),
          },
        );
      }
    } else {
      final merchantNorm = _nonEmpty(f.merchant?.key);
      final counterparty = p.counterpartyValue == null
          ? _counterpartyOf(f.counterparty)
          : null;
      final balance = f.balance;
      final institution = p.accountInstitution ?? r.institutionCode;
      await _store.updateTxn(
        p.id,
        TxnPatch(
          status: TxnStatus.posted,
          amount: amountDiffers ? amount : null,
          dedupeKey: amountDiffers
              ? dedupeKeyOf(institution, p.direction, amount)
              : null,
          originalAmount: f.originalAmount,
          merchantRaw: p.merchantRaw == null
              ? _nonEmpty(f.merchant?.display)
              : null,
          merchantNorm: p.merchantNorm == null ? merchantNorm : null,
          counterpartyKind: counterparty?.$1,
          counterpartyValue: counterparty?.$2,
          referenceNo: p.referenceNo == null ? _nonEmpty(f.ref) : null,
          balanceAfterMinor:
              p.balanceAfterMinor == null &&
                  balance != null &&
                  balance.currency == amount.currency
              ? balance.minor
              : null,
        ),
        atMs: now,
      );
    }
    local.txn(p.id, p.accountId, p.occurredAtMs, p.tzOffsetMin);
    await _recordBalance(
      local,
      accountId: p.accountId,
      occurredAtMs: occurredMs,
      balance: f.balance,
      available: f.available,
      sourceTxnId: p.id,
    );
    await _runHooks(p.id, p.accountId, inserted: false);
  }

  // ---------------------------------------------------------------------
  // Generic results (FU-080, A-66).

  Future<IngestOutcome> _generic(
    _Prepared p,
    _BatchScope b,
    _Changes local,
    ParseGeneric g,
  ) async {
    CaptureSenderState? row;
    for (final s in b.ctx.captureSenders) {
      if (senderKeyOf(s.channel, s.sender) == p.senderKey &&
          s.channel == _senderChannelOf(p.m.channel)) {
        row = s;
        break;
      }
    }
    final disposition = genericDisposition(
      confirmedCount: row?.confirmedCount ?? 0,
      alwaysCapture: row?.alwaysCapture ?? false,
    );
    final direction = switch (g.direction) {
      TemplateDirection.expense => TxnDirection.expense,
      TemplateDirection.income => TxnDirection.income,
      _ => null,
    };
    final autoSave =
        disposition == GenericDisposition.autoSaveLowConfidence &&
        direction != null &&
        p.m.origin.isBackground &&
        kGenericAutoSaveAccount == GenericAutoSaveAccount.senderAccount;
    if (!autoSave) {
      final rawId = await _insertRaw(p, status: RawStatus.review);
      await _review(
        kind: ReviewKind.newSender,
        rawId: rawId,
        payload: {
          'generic': true,
          'amount': g.amount.toJson(),
          'direction': ?direction?.code,
          'hasLast4': g.last4 != null,
          'confidencePermille': g.confidencePermille,
          'reasons': [for (final x in g.reasons) x.name],
        },
      );
      return IngestReview(rawId, ReviewKind.newSender);
    }
    final (occurredMs, offsetMin) = _occurred(g.occurredAt);
    final account = await _resolve(
      local,
      institution: _genericInstitution(p.senderKey),
      last4: g.last4,
      currency: g.amount.currency,
      label: p.m.source.trim().isEmpty ? p.senderKey : p.m.source.trim(),
      kind: inferAccountKind(hasLast4: g.last4 != null),
    );
    final merchantNorm = _nonEmpty(g.merchant?.key);
    final merchantRaw = _nonEmpty(g.merchant?.display);
    final category = await _categorize(
      b.categorizer,
      merchantRaw: merchantRaw,
      merchantNorm: merchantNorm,
    );
    final rawId = await _insertRaw(p, status: RawStatus.parsed);
    final txnId = _newId();
    await _store.insertTxn(
      TxnInsert(
        id: txnId,
        accountId: account.id,
        rawMessageId: rawId,
        source: p.txnSource!,
        direction: direction,
        status: TxnStatus.posted,
        amount: g.amount,
        occurredAtMs: occurredMs,
        tzOffsetMin: offsetMin,
        merchantRaw: merchantRaw,
        merchantNorm: merchantNorm,
        catalogMerchantId: category.catalogMerchantId,
        categoryId: category.categoryId,
        categorySource: category.source,
        isUserVerified: false,
        parseConfidencePermille: g.confidencePermille,
        createdAtMs: _nowMs(),
      ),
    );
    local.txn(txnId, account.id, occurredMs, offsetMin);
    await _review(
      kind: ReviewKind.lowConfidence,
      rawId: rawId,
      txnId: txnId,
      payload: {
        'reason': 'generic',
        'generic': true,
        'confidencePermille': g.confidencePermille,
        'reasons': [for (final x in g.reasons) x.name],
      },
    );
    await _runHooks(txnId, account.id, inserted: true);
    return IngestInserted(txnId);
  }

  /// `capture_senders.channel` for a raw channel.
  static String _senderChannelOf(String channel) =>
      channel == 'shortcut_message' || channel == 'notification'
      ? channel
      : 'sms';

  /// The `accounts.institution_code` of a generic sender's account: a hash
  /// of the sender key, so no sender text lands in a code column.
  static String _genericInstitution(String senderKey) {
    final digest = sha256.convert(utf8.encode('zg.gen.v1\u0000$senderKey'));
    return 'g_${digest.toString().substring(0, 16)}';
  }

  // ---------------------------------------------------------------------
  // Helpers.

  /// UTC epoch ms and offset of a parser wall clock (EC-10).
  (int, int) _occurred(DateTime wall) {
    final w = DateTime.utc(
      wall.year,
      wall.month,
      wall.day,
      wall.hour,
      wall.minute,
      wall.second,
    );
    final offset = clampTzOffset(_zone.offsetAtWallClock(w));
    return (w.millisecondsSinceEpoch - offset * 60000, offset);
  }

  /// Inserts the raw row (`ON CONFLICT(body_hash) DO NOTHING`); a conflict
  /// throws [_RaceLost], which rolls the message's savepoint back.
  ///
  /// CR-6: in every branch this MUST run before any transaction insert or
  /// update (attach, settle, insert). It is the `ux_raw_body_hash` backstop
  /// behind dedupe 1: a copy that a concurrent writer committed first must
  /// fail here, before it changes a transaction.
  Future<String> _insertRaw(
    _Prepared p, {
    required String status,
    String? institution,
    String? templateId,
    int? templateVersion,
  }) async {
    final old = p.existing;
    if (old != null) {
      // T-076: the row already exists (and keeps its body_hash). Promote it
      // only while it is still in the state this re-parse started from.
      final done = await _store.promoteRaw(
        PromoteRaw(
          id: old.id,
          fromStatus: old.parseStatus,
          toStatus: status,
          registryVersion: _pipeline.registry.registryVersion,
          atMs: _nowMs(),
          institutionCode: institution,
          templateId: templateId,
          templateVersion: templateVersion,
        ),
      );
      if (!done) throw const _RaceLost();
      return old.id;
    }
    final id = _newId();
    final inserted = await _store.insertRaw(
      RawInsert(
        id: id,
        channel: p.m.channel,
        sender: p.m.source,
        institutionCode: institution,
        body: p.m.body,
        bodyHash: p.bodyHash,
        receivedAtMs: p.m.receivedAtMs,
        simSlot: p.m.simSlot,
        parseStatus: status,
        templateId: templateId,
        templateVersion: templateVersion,
        registryVersion: _pipeline.registry.registryVersion,
        createdAtMs: _nowMs(),
      ),
    );
    if (!inserted) throw const _RaceLost();
    return id;
  }

  Future<void> _review({
    required String kind,
    String? rawId,
    String? txnId,
    Map<String, Object?>? payload,
  }) => _store.insertReview(
    id: _newId(),
    kind: kind,
    rawMessageId: rawId,
    txnId: txnId,
    payload: payload,
    createdAtMs: _nowMs(),
  );

  Future<Account> _resolve(
    _Changes local, {
    required String institution,
    required String? last4,
    required Currency currency,
    required String label,
    required AccountKind kind,
  }) async {
    final resolved = await _accounts.resolve(
      AccountHint(
        institutionCode: institution,
        last4: last4,
        currency: currency,
        label: label,
        kind: kind,
      ),
    );
    if (resolved.created) local.created.add(resolved.account.id);
    return resolved.account;
  }

  Future<void> _recordBalance(
    _Changes local, {
    required String accountId,
    required int occurredAtMs,
    Money? balance,
    Money? available,
    String? sourceTxnId,
  }) async {
    if (balance == null && available == null) return;
    // Two figures in different currencies: keep the balance only (never
    // converted, never mixed).
    final avail =
        balance != null &&
            available != null &&
            balance.currency != available.currency
        ? null
        : available;
    final changed = await _accounts.recordBalance(
      accountId: accountId,
      asOf: DateTime.fromMillisecondsSinceEpoch(occurredAtMs, isUtc: true),
      balance: balance,
      available: avail,
      sourceTxnId: sourceTxnId,
    );
    if (changed) local.accounts.add(accountId);
  }

  /// Categorize (§8) with T-075's categorizer. A port failure propagates
  /// (never read as "no category"); the stored source is mapped by code.
  static Future<_Category> _categorize(
    Categorizer categorizer, {
    String? merchantRaw,
    String? merchantNorm,
    String? counterpartyKind,
    String? counterpartyValue,
  }) async {
    final d = await categorizer.categorize(
      categorizeInputFor(
        merchantRaw: merchantRaw,
        merchantNorm: merchantNorm,
        counterpartyKind: counterpartyKind,
        counterpartyValue: counterpartyValue,
      ),
    );
    return _Category(
      categoryId: d.categoryId,
      catalogMerchantId: d.catalogMerchantId,
      // `none` when the decision has no category (needs classification).
      source: d.categoryId == null
          ? CategorySource.none
          : CategorySource.fromCode(d.source.code),
    );
  }

  Future<void> _runHooks(
    String txnId,
    String accountId, {
    required bool inserted,
  }) async {
    for (final h in _hooks) {
      await h.afterPersist(
        PersistedTxn(txnId: txnId, accountId: accountId, inserted: inserted),
      );
    }
  }

  static (String, String)? _counterpartyOf(Counterparty? c) {
    if (c == null) return null;
    return switch (c.kind) {
      CounterpartyKind.ipaAddress when _nonEmpty(c.ipa) != null => (
        'ipa',
        c.ipa!.trim(),
      ),
      CounterpartyKind.phone when _nonEmpty(c.phone) != null => (
        'phone',
        c.phone!.trim(),
      ),
      _ when _nonEmpty(c.name) != null => ('person', c.name!.trim()),
      _ => null,
    };
  }

  static String? _nonEmpty(String? s) {
    if (s == null) return null;
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  // ---------------------------------------------------------------------
  // After the commit.

  IngestBatchResult _finish(
    List<IncomingMessage> batch,
    _BatchState state, {
    List<String> kept = const [],
  }) {
    final changes = state.changes;
    for (final e in changes.diagCounts.entries) {
      _diag.count(e.key, e.value);
    }
    final accountIds = <String>{
      ...changes.accounts,
      for (final t in changes.txns.values) ...t.accountIds,
    };
    TransactionsChanged? event;
    if (changes.txns.isNotEmpty || accountIds.isNotEmpty) {
      final cycleOf =
          _cycleKeyOf ??
          (int ms, int off) => cycleKeyFor(
            occurredAtMs: ms,
            tzOffsetMin: off,
            schedule: state.schedule,
          );
      event = TransactionsChanged(
        accountIds: accountIds,
        cycleKeys: {
          for (final t in changes.txns.values)
            cycleOf(t.occurredAtMs, t.tzOffsetMin),
        },
      );
      _events?.publish(event);
    }
    final ackable = <String>[];
    final seen = <String>{};
    for (final m in batch) {
      if (kept.contains(m.deliveryId)) continue;
      if (seen.add(m.deliveryId)) ackable.add(m.deliveryId);
    }
    return IngestBatchResult(
      outcomes: state.outcomes,
      ackable: ackable,
      changedTxnIds: changes.txns.keys.toSet(),
      changedAccountIds: accountIds,
      createdAccountIds: changes.created,
      event: event,
      kept: kept,
    );
  }
}

final class _Prepared {
  const _Prepared({
    required this.m,
    required this.result,
    required this.senderKey,
    required this.bodyHash,
    required this.txnSource,
    this.existing,
  });

  /// T-076: the stored row a re-parse works on; its raw row is updated, not
  /// inserted.
  final StoredRaw? existing;
  final IncomingMessage m;
  final ParseResult result;
  final String senderKey;
  final String bodyHash;
  final TxnSource? txnSource;
}

/// What one batch shares: step-0 context, label language, categorizer.
final class _BatchScope {
  const _BatchScope(this.ctx, this.labels, this.categorizer);
  final BatchContext ctx;
  final _LabelLanguage labels;
  final Categorizer categorizer;
}

/// A categorize decision in stored terms.
final class _Category {
  const _Category({
    required this.source,
    this.categoryId,
    this.catalogMerchantId,
  });
  final String? categoryId;
  final CategorySource source;
  final int? catalogMerchantId;
}

final class _Guard {
  const _Guard(
    this.guard, {
    this.dbIgnoreCheck = false,
    this.userSenders = const {},
  });
  final CaptureGuard guard;

  /// Some ignore rules are not in [guard]: check registry keeps against
  /// the database too.
  final bool dbIgnoreCheck;

  /// `(channel wire, sender key)` the user asked to capture that are not in
  /// [guard]'s user part (it could not hold them).
  final Set<(String, String)> userSenders;

  bool isUserSender(String channelWire, String source) {
    if (userSenders.isEmpty) return false;
    final ch = GuardChannel.fromWire(channelWire);
    if (ch == null) return false;
    return userSenders.contains((ch.wire, guardSourceKey(ch, source)));
  }
}

/// Rolls back a savepoint whose raw insert lost the `body_hash` race.
final class _RaceLost implements Exception {
  const _RaceLost();
}

final class _TxnChange {
  _TxnChange(this.occurredAtMs, this.tzOffsetMin);
  final int occurredAtMs;
  final int tzOffsetMin;
  final Set<String> accountIds = {};
}

/// What one message changed; merged into the batch only when its savepoint
/// committed.
final class _Changes {
  final Map<String, _TxnChange> txns = {};
  final Set<String> accounts = {};
  final Set<String> created = {};
  final Map<String, int> diagCounts = {};

  void txn(String id, String accountId, int occurredAtMs, int tzOffsetMin) {
    txns
        .putIfAbsent(id, () => _TxnChange(occurredAtMs, tzOffsetMin))
        .accountIds
        .add(accountId);
  }

  void diag(String code) => diagCounts[code] = (diagCounts[code] ?? 0) + 1;

  void clear() {
    txns.clear();
    accounts.clear();
    created.clear();
    diagCounts.clear();
  }

  void addAll(_Changes o) {
    for (final e in o.txns.entries) {
      final t = txns.putIfAbsent(
        e.key,
        () => _TxnChange(e.value.occurredAtMs, e.value.tzOffsetMin),
      );
      t.accountIds.addAll(e.value.accountIds);
    }
    accounts.addAll(o.accounts);
    created.addAll(o.created);
    for (final e in o.diagCounts.entries) {
      diagCounts[e.key] = (diagCounts[e.key] ?? 0) + e.value;
    }
  }
}

final class _BatchState {
  final Map<String, IngestOutcome> outcomes = {};
  final _Changes changes = _Changes();
  PaydaySchedule schedule = PaydaySchedule.single(1);

  void addAll(_BatchState o) {
    outcomes.addAll(o.outcomes);
    changes.addAll(o.changes);
    schedule = o.schedule;
  }
}

/// The language of new account labels: `settings.language` (`en…` is
/// English; anything else, or unset, Arabic: the app is RTL-first).
final class _LabelLanguage {
  const _LabelLanguage(this.english);

  factory _LabelLanguage.of(String? stored) =>
      _LabelLanguage(stored != null && stored.trim().startsWith('en'));

  final bool english;

  String institutionLabel(Registry registry, String code) {
    final inst = registry.byCode(code);
    if (inst == null) return code;
    final name = english ? inst.nameEn : inst.nameAr;
    return name.trim().isEmpty ? code : name;
  }
}

/// UTC (tests and callers that pass no zone).
final class _UtcZone implements LocalZone {
  const _UtcZone();
  @override
  int offsetAtInstant(int utcMs) => 0;
  @override
  int offsetAtWallClock(DateTime wallClock) => 0;
}
