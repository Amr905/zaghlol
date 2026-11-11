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
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/db/daos/review_items_dao.dart' show ReviewKind;
import '../../../core/db/db_errors.dart';
import '../../accounts/domain/account.dart';
import '../../accounts/domain/accounts_repository.dart';
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
    required this._categorizer,
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
  final Categorizer _categorizer;
  final IngestIdGenerator _newId;
  final IngestClock _now;
  final LocalZone _zone;
  final CycleKeyOf? _cycleKeyOf;
  final List<PostPersistHook> _hooks;
  final DiagSink _diag;
  final DomainEventBus? _events;

  List<int>? _baseBytes;
  GuardConfig? _baseConfig;
  List<int>? _lastUserBytes;
  CaptureGuard? _lastFullGuard;

  int _nowMs() => _now().toUtc().millisecondsSinceEpoch;

  /// Ingests [batch] in one write transaction. Throws [IngestBatchFailed]
  /// when the transaction did not commit (nothing stored, nothing to ack).
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

    final state = _BatchState();
    try {
      await _store.inWriteTransaction(() async {
        final ctx = await _store.readContext();
        state.paydayDay = paydayDayOf(ctx.paydayDay);
        final guard = _guardFor(ctx);
        final labels = _LabelLanguage.of(ctx.language);
        for (final p in prepared) {
          if (state.outcomes.containsKey(p.m.deliveryId)) continue;
          final local = _Changes();
          final outcome = await _one(p, ctx, guard, labels, local);
          state.outcomes[p.m.deliveryId] = outcome;
          state.changes.addAll(local);
        }
      });
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
    // Committed.
    return _finish(batch, state);
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

  _Prepared _prepare(IncomingMessage m) {
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
    final built = buildGuardUserConfig(
      baseRegistryVersion: base.registryVersion,
      ignoreRules: [
        for (final r in ctx.ignoreRules)
          GuardIgnoreRuleInput(
            institutionCode: r.institutionCode,
            last4: r.last4,
            channel: r.channel,
          ),
      ],
      alwaysCaptureSenders: [
        for (final s in ctx.captureSenders)
          if (s.alwaysCapture)
            GuardUserSenderInput(sender: s.sender, channel: s.channel),
      ],
      customTemplateSenders: [
        for (final (sender, channel) in ctx.customTemplateSenders)
          GuardUserSenderInput(sender: sender, channel: channel),
      ],
      goldActive: false,
    );
    final userBytes = built.bytes;
    if (userBytes != null) {
      final cached = _lastFullGuard;
      if (cached != null && _sameBytes(_lastUserBytes, userBytes)) {
        return _Guard(cached, baseOnly: false);
      }
      final load = parseGuardConfig(baseBytes, userBytes);
      if (load.mode == GuardConfigMode.full) {
        final guard = CaptureGuard(load.config);
        _lastUserBytes = userBytes;
        _lastFullGuard = guard;
        return _Guard(guard, baseOnly: false);
      }
    }
    // The user part can't be built (caps, a row the Guard can't express):
    // base rules plus a per-message database ignore check.
    return _Guard(CaptureGuard(base), baseOnly: true);
  }

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
    BatchContext ctx,
    _Guard? guard,
    _LabelLanguage labels,
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
      if (decision is GuardDrop) {
        return _dropped(decision.reason.wire, local);
      }
      if (guard.baseOnly && decision is GuardKeep) {
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
    try {
      return await _store.inSavepoint(
        () => _persist(p, ctx, labels, local, result),
      );
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
        return await _store.inSavepoint(() => _storeFailed(p, result, e));
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
    Object error,
  ) async {
    final rawId = await _insertRaw(
      p,
      status: RawStatus.review,
      institution: _institutionOf(result),
      templateId: _templateIdOf(result),
    );
    await _review(
      kind: ReviewKind.unrecognized,
      rawId: rawId,
      payload: {
        'reason': 'ingestFailed',
        'code': error is SafeException ? error.code : 'INGEST_FAILED',
      },
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
    BatchContext ctx,
    _LabelLanguage labels,
    _Changes local,
    ParseResult result,
  ) async {
    switch (result) {
      case ParseDropped():
        // Handled before the savepoint.
        return const IngestDropped('parser_global');
      case ParseUnrecognized():
        return _unrecognized(p, result);
      case ParseGeneric():
        return _generic(p, ctx, local, result);
      case ParseParsed():
        return switch (dispositionOf(result.event, result.direction)) {
          CreateTxn(:final direction, :final status) => _parsed(
            p,
            labels,
            local,
            result,
            direction,
            status,
          ),
          BalanceOnlyEvent() => _balanceOnly(p, labels, local, result),
          DeferredEvent() => _deferred(p, result),
          UndirectedEvent() => _undirected(p, result),
        };
    }
  }

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
    _LabelLanguage labels,
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
      await _insertRaw(
        p,
        status: RawStatus.parsed,
        institution: inst,
        templateId: r.templateId,
        templateVersion: r.templateVersion,
      );
      await _attach(local, labels, target, r, occurredMs);
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
        await _insertRaw(
          p,
          status: RawStatus.parsed,
          institution: inst,
          templateId: r.templateId,
          templateVersion: r.templateVersion,
        );
        if (newIsPending) {
          // A late pending message: the payment is already posted.
          await _attach(local, labels, pick, r, occurredMs);
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
    final category = await _categorizer.categorize(
      CategorizeInput(
        merchantNorm: merchantNorm,
        counterparty: counterparty?.$2,
        institution: inst,
        direction: direction,
      ),
    );
    // (10) Raw + transaction.
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
        merchantRaw: _nonEmpty(f.merchant?.display),
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
    _LabelLanguage labels,
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
          label: labels.institutionLabel(_pipeline.registry, r.institutionCode),
          kind: inferAccountKind(
            event: r.event.wire,
            balanceIsAvailableLimit: f.balanceIsAvailableLimit,
            hasLast4: true,
          ),
        );
        if (card.id != target.accountId) moveTo = card.id;
      }
      final merchantNorm = _nonEmpty(f.merchant?.key);
      final gainsMerchant = target.merchantNorm == null && merchantNorm != null;
      final counterparty = target.counterpartyValue == null
          ? _counterpartyOf(f.counterparty)
          : null;
      CategorizeResult? category;
      if (target.categorySource == CategorySource.none &&
          (gainsMerchant || counterparty != null)) {
        final c = await _categorizer.categorize(
          CategorizeInput(
            merchantNorm: target.merchantNorm ?? merchantNorm,
            counterparty: target.counterpartyValue ?? counterparty?.$2,
            institution: r.institutionCode,
            direction: target.direction,
          ),
        );
        if (c.source != CategorySource.none) category = c;
      }
      final balance = f.balance;
      final confidence = target.parseConfidencePermille;
      final patch = TxnPatch(
        accountId: moveTo,
        originalAmount: target.originalAmount == null ? f.originalAmount : null,
        merchantRaw: target.merchantRaw == null
            ? _nonEmpty(f.merchant?.display)
            : null,
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
    BatchContext ctx,
    _Changes local,
    ParseGeneric g,
  ) async {
    CaptureSenderState? row;
    for (final s in ctx.captureSenders) {
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
    final category = await _categorizer.categorize(
      CategorizeInput(merchantNorm: merchantNorm, direction: direction),
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
        merchantRaw: _nonEmpty(g.merchant?.display),
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

  Future<String> _insertRaw(
    _Prepared p, {
    required String status,
    String? institution,
    String? templateId,
    int? templateVersion,
  }) async {
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

  IngestBatchResult _finish(List<IncomingMessage> batch, _BatchState state) {
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
            paydayDay: state.paydayDay,
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
      if (seen.add(m.deliveryId)) ackable.add(m.deliveryId);
    }
    return IngestBatchResult(
      outcomes: state.outcomes,
      ackable: ackable,
      changedTxnIds: changes.txns.keys.toSet(),
      changedAccountIds: accountIds,
      createdAccountIds: changes.created,
      event: event,
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
  });

  final IncomingMessage m;
  final ParseResult result;
  final String senderKey;
  final String bodyHash;
  final TxnSource? txnSource;
}

final class _Guard {
  const _Guard(this.guard, {required this.baseOnly});
  final CaptureGuard guard;
  final bool baseOnly;
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
  int paydayDay = 1;
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
