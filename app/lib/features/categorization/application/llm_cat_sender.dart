// T-358: the sender of the auto-category queue (LLM-CATEGORISE, FR-LCAT-01…04,
// FR-LCAT-40/41/43; llm-categorise.md §1, §3, §7).
//
// What may leave the phone: the merchant keys returned by
// `LlmCatQueueFiller.pickForSend` (eligible, business-evidence rows only), the
// language, the consent terms, a request id and the proof, all assembled by
// `LlmGatewayClient.categorise`. This class never reads a transaction,
// amount, date, account or message; it has no other way to name a merchant.
//
// Gate (nothing sent, no proof made): flag fresh ON, known terms covered by
// `cat.llm_consent`, not paused until sync, local quota not at 0 before
// `resetsAt` (all inside `pickForSend`), plus the scheduling below.
//
// Scheduling (in memory; no background permission): [run] is called at app
// open / foreground and after ingest or sync. At most one send per
// [minInterval] while open; after a failure nothing is sent for [backoff]
// (or the server's retry delay, 1 min…1 h) and the queue rows carry the same
// `next_attempt_at`. Offline sends nothing and costs no interval.
//
// Replies are untrusted: only merchants that were sent are read, once each;
// `ok` needs a category in the closed set of live system categories, a
// confidence and a known source, otherwise the merchant is `no_answer`.
// An answer is applied only through [AiSuggestionApplier] (which fills
// "needs classification" rows only). `quota` and missing merchants stay
// queued. The local allowance is never counted here: the gateway client
// stores the backend's snapshot.
//
// Merchant names are never logged, kept in an error or put in a report.

import 'dart:async';

import '../../../core/backend/backend_client.dart'
    show CategoriseResponse, CategoriseResultSource, CategoriseResultStatus;
import '../../../core/db/app_database.dart';
import '../../../core/db/daos/llm_cat_queue_dao.dart';
import '../../../core/llm/llm_gateway_client.dart';
import 'llm_cat_queue.dart';

/// The gateway's `categorise` call, injected so tests drive it.
typedef LlmCategoriseCall = Future<CategoriseResponse> Function({
  required List<String> merchants,
  required LlmLang lang,
  required LlmTerms terms,
  required String requestId,
});

enum LlmCatSendOutcome {
  /// A request was made and its reply handled.
  sent,

  /// Nothing to send, or the gate is closed.
  idle,

  /// Too soon after the last send, or inside a back-off.
  throttled,

  /// A request failed; back-off started.
  failed,

  /// No network; nothing was sent, nothing is counted.
  offline,

  /// Another [run] is in progress.
  busy,
}

final class LlmCatSendReport {
  const LlmCatSendReport(
    this.outcome, {
    this.applied = 0,
    this.noAnswer = 0,
    this.stayed = 0,
  });
  final LlmCatSendOutcome outcome;
  final int applied;
  final int noAnswer;
  final int stayed;

  @override
  String toString() => 'LlmCatSendReport(${outcome.name})';
}

class LlmCatSender {
  LlmCatSender(
    this._db, {
    required this.filler,
    required this.applier,
    required this.call,
    required this.newRequestId,
    required this.terms,
    required this.allowedCategoryIds,
    this.onConsentRequired = _noop,
    required this.batchMax,
    this.minInterval = const Duration(minutes: 10),
    this.backoff = const Duration(hours: 1),
    this.requestIdWindow = const Duration(seconds: 110),
  });

  final AppDatabase _db;
  final LlmCatQueueFiller filler;
  final AiSuggestionApplier applier;
  final LlmCategoriseCall call;
  final String Function() newRequestId;

  /// FU-425: runs on a `409 LLM_CONSENT_REQUIRED`: resets the config cursor so
  /// the next sync brings the provider the server has now. No sync, no send.
  final Future<void> Function() onConsentRequired;
  static Future<void> _noop() async {}

  /// The consent terms of the active provider; null until it is known
  /// (nothing is sent then).
  final LlmTerms? Function() terms;

  /// Category ids an answer may name: live system categories (never custom).
  final Future<Set<String>> Function() allowedCategoryIds;
  final int Function() batchMax;
  final Duration minInterval;
  final Duration backoff;

  /// How long a request id may be reused for the same batch (the server's
  /// idempotency window is 2 minutes).
  final Duration requestIdWindow;

  DateTime? _lastSendAt;
  DateTime? _blockedUntil;
  bool _running = false;
  ({String id, List<String> keys, DateTime at})? _pending;

  /// Switch off: the queue is emptied and nothing pending is kept.
  Future<void> switchedOff() async {
    _pending = null;
    await LlmCatQueueDao(_db).clear();
  }

  Future<LlmCatSendReport> run({
    required DateTime now,
    required LlmLang lang,
  }) async {
    if (_running) return const LlmCatSendReport(LlmCatSendOutcome.busy);
    _running = true;
    try {
      return await _run(now.toUtc(), lang);
    } finally {
      _running = false;
    }
  }

  Future<LlmCatSendReport> _run(DateTime now, LlmLang lang) async {
    const idle = LlmCatSendReport(LlmCatSendOutcome.idle);
    final t = terms();
    if (t == null) return idle;
    final last = _lastSendAt;
    final until = _blockedUntil;
    if ((last != null && now.difference(last) < minInterval) ||
        (until != null && now.isBefore(until))) {
      return const LlmCatSendReport(LlmCatSendOutcome.throttled);
    }
    final picked = await filler.pickForSend(now: now, batchMax: batchMax());
    if (picked.isEmpty) return idle;

    // A retry of the same batch inside the window keeps its request id and
    // its order, so the backend counts it once.
    final p = _pending;
    final reuse =
        p != null &&
        now.difference(p.at) < requestIdWindow &&
        p.keys.length == picked.length &&
        p.keys.toSet().containsAll(picked);
    final keys = reuse ? p.keys : picked;
    final id = reuse ? p.id : newRequestId();
    if (!reuse) _pending = (id: id, keys: keys, at: now);

    _lastSendAt = now;
    final CategoriseResponse res;
    try {
      res = await call(merchants: keys, lang: lang, terms: t, requestId: id);
    } on LlmOffline {
      _lastSendAt = last;
      return const LlmCatSendReport(LlmCatSendOutcome.offline);
    } on LlmBlocked {
      _lastSendAt = last;
      return idle;
    } on LlmConsentRequired {
      // The client cleared the consent (the gate is closed from now on), the
      // queue stays (not a withdrawal); the provider id of the 409 is never
      // used. Nothing more until the user agrees again.
      _pending = null;
      try {
        await onConsentRequired();
      } on Object {
        // Resetting the cursor is best effort.
      }
      return idle;
    } on LlmServicePaused {
      return idle;
    } on LlmQuotaExhausted {
      // The client stored the backend's snapshot; the rows stay queued.
      _pending = null;
      return idle;
    } on LlmCancelled {
      return idle;
    } on LlmGatewayException catch (e) {
      await _failed(keys, now, switch (e) {
        LlmRateLimited(:final retryAfter) => retryAfter,
        LlmUpstreamUnavailable(:final retryAfter) => retryAfter,
        _ => null,
      });
      return const LlmCatSendReport(LlmCatSendOutcome.failed);
    }
    _pending = null;
    return _handle(keys, res, now);
  }

  Future<void> _failed(
    List<String> keys,
    DateTime now,
    Duration? retryAfter,
  ) async {
    var wait = backoff;
    if (retryAfter != null) {
      wait = retryAfter < const Duration(minutes: 1)
          ? const Duration(minutes: 1)
          : (retryAfter > backoff ? backoff : retryAfter);
    }
    _blockedUntil = now.add(wait);
    await LlmCatQueueDao(
      _db,
    ).markAttempt(keys, nextAttemptAt: _blockedUntil!.millisecondsSinceEpoch);
  }

  Future<LlmCatSendReport> _handle(
    List<String> sent,
    CategoriseResponse res,
    DateTime now,
  ) async {
    final asked = sent.toSet();
    final seen = <String>{};
    final allowed = await allowedCategoryIds();
    var applied = 0;
    var none = 0;
    for (final r in res.results) {
      // Only merchants that were sent, once each: an echoed stranger or a
      // repeat is ignored.
      if (!asked.contains(r.merchant) || !seen.add(r.merchant)) continue;
      switch (r.status) {
        case CategoriseResultStatus.ok:
          final id = r.category == null ? null : 'sys:${r.category}';
          final source = r.source?.wire;
          final conf = r.confidence;
          if (id != null &&
              allowed.contains(id) &&
              conf != null &&
              source != null &&
              r.source != CategoriseResultSource.unknown) {
            await applier.accept(
              merchantNorm: r.merchant,
              categoryId: id,
              confidence: conf,
              source: source,
              at: now,
            );
            applied++;
          } else {
            await applier.noAnswer(merchantNorm: r.merchant, at: now);
            none++;
          }
        case CategoriseResultStatus.unknownValue:
        case CategoriseResultStatus.lowConfidence:
        case CategoriseResultStatus.rejected:
          await applier.noAnswer(merchantNorm: r.merchant, at: now);
          none++;
        case CategoriseResultStatus.quota:
        case CategoriseResultStatus.unknown:
          break; // stays queued
      }
    }
    return LlmCatSendReport(
      LlmCatSendOutcome.sent,
      applied: applied,
      noAnswer: none,
      stayed: sent.length - applied - none,
    );
  }
}
