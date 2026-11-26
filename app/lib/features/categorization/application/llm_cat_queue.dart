// T-357: fills the auto-category queue and picks what may be sent
// (LLM-CATEGORISE, FR-LCAT-04/05/06/40; llm-categorise.md §1, §7). Nothing
// here talks to the network: the sender (T-358) sends what [pickForSend]
// returns and reports each answer through [AiSuggestionApplier].
//
// Safety:
//  * Gate first: the `llm_categorise` flag (fresh snapshot only), known
//    consent terms and `cat.llm_consent` covering them. Closed gate: nothing
//    is written or picked.
//  * A merchant is queued only when every one of its "needs
//    classification" rows is a business payment (`llmPaymentKindOf`), its
//    key passes `LlmEligibility` (never tried: no suggestion row in any
//    state), its raw text shows no identifier or person-like name, and no
//    `merchant_norm` user rule exists.
//  * The fill is a recompute (counts are set, not added; merchants that no
//    longer qualify leave the queue), so it is idempotent and resumable.
//  * The quota snapshot is read, never written: the backend is the only
//    counter, so nothing here can count an allowance twice.
// Merchant names are never logged or put in an error.

import 'package:drift/drift.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/ai_merchant_suggestions_dao.dart';
import '../../../core/db/daos/llm_cat_queue_dao.dart';
import '../../../core/db/daos/write_errors.dart';
import '../../../core/llm/llm_feature.dart';
import '../../../core/llm/llm_quota_snapshot.dart';
import '../data/recategorizer.dart';
import '../domain/categorize_input.dart';
import '../domain/llm_payment_kind.dart';

/// The consent sheet version of the auto-category feature (FR-LCAT-44).
const int catLlmConsentVersion = 1;

/// Queue limits (llm-categorise §7): 100 distinct merchants, 60 days.
const int llmCatQueueCap = 100;
const Duration llmCatQueueMaxAge = Duration(days: 60);

/// The local gate, injected so tests (and T-358) can drive it.
final class LlmCatGate {
  const LlmCatGate({
    required this.isFlagOn,
    required this.hasConsent,
    required this.quota,
  });

  /// `llm_categorise` on in a fresh snapshot (fail closed).
  final bool Function() isFlagOn;

  /// `cat.llm_consent` covers the active provider at [catLlmConsentVersion].
  final Future<bool> Function() hasConsent;

  final LlmQuotaStore quota;

  Future<bool> open() async => isFlagOn() && await hasConsent();
}

/// The result of [LlmCatQueueFiller.fill].
final class LlmCatFillReport {
  const LlmCatFillReport({
    required this.ran,
    required this.queued,
    required this.removed,
  });

  /// False when the gate was closed (nothing read or written).
  final bool ran;
  final int queued;
  final int removed;

  static const LlmCatFillReport closed = LlmCatFillReport(
    ran: false,
    queued: 0,
    removed: 0,
  );
}

/// A card purchase on an expense row, or a card refund on a refund row.
bool _businessEvidence(TemplateEvent e, String direction) =>
    (direction == 'expense' && _cardEvents.contains(e)) ||
    (direction == 'refund' && e == TemplateEvent.refund);

/// Template events that are a card / POS / online purchase at a business.
const Set<TemplateEvent> _cardEvents = {
  TemplateEvent.cardPurchase,
  TemplateEvent.cardPurchaseFx,
};

final RegExp _tableKey = RegExp(r'^[a-z0-9]+( [a-z0-9]+)*$');

/// True when [key] fits the queue's CHECK (2–64, `[a-z0-9]` words).
bool isQueueableKey(String key) =>
    key.length >= 2 && key.length <= 64 && _tableKey.hasMatch(key);

class LlmCatQueueFiller {
  LlmCatQueueFiller(
    this._db, {
    required this.gate,
    required this.lexicon,
    this.templateEvents = _noEvents,
  });

  /// Template id -> the event the registry declares for it. The only typed
  /// evidence that a row without a counterparty is a card / POS purchase
  /// (the parser leaves the counterparty kind null on those rows). Empty
  /// (the default) means no row is treated as a business payment by
  /// evidence: fail closed.
  final Map<String, TemplateEvent> Function() templateEvents;

  static Map<String, TemplateEvent> _noEvents() => const {};

  final AppDatabase _db;
  final LlmCatGate gate;
  final Future<NameLexicon> Function() lexicon;

  /// Recomputes the queue from the "needs classification" rows of the last
  /// [llmCatQueueMaxAge]. One DB transaction.
  Future<LlmCatFillReport> fill({required DateTime now}) async {
    if (!await gate.open()) return LlmCatFillReport.closed;
    final lx = await lexicon();
    final nowMs = now.toUtc().millisecondsSinceEpoch;
    final since = nowMs - llmCatQueueMaxAge.inMilliseconds;
    final queue = LlmCatQueueDao(_db);
    final suggestions = AiMerchantSuggestionsDao(_db);

    return guardWrite(
      () => _db.transaction(() async {
        final rows = await _db
            .customSelect(
              'SELECT merchant_norm, merchant_raw, direction, source, '
              'counterparty_kind, counterparty_value, is_internal, template_id, '
              'transfer_pair_id IS NOT NULL AS paired, created_at '
              'FROM transactions WHERE merchant_norm IS NOT NULL '
              'AND created_at >= ?1 AND $needsClassificationSql',
              variables: [Variable.withInt(since)],
              readsFrom: {_db.transactions},
            )
            .get();
        final ruled = {
          for (final r
              in await _db
                  .customSelect(
                    'SELECT match_value FROM merchant_rules '
                    "WHERE match_kind = 'merchant_norm'",
                    readsFrom: {_db.merchantRules},
                  )
                  .get())
            r.read<String>('match_value'),
        };

        final byKey = <String, List<QueryRow>>{};
        for (final r in rows) {
          (byKey[r.read<String>('merchant_norm')] ??= []).add(r);
        }
        final tried = await suggestions.statesOf(byKey.keys);
        final events = templateEvents();

        final eligible = <({String key, int count, int lastSeen})>[];
        for (final e in byKey.entries) {
          final key = e.key;
          if (!isQueueableKey(key) || ruled.contains(key)) continue;
          if (e.value.every((r) => _rowEligible(r, key, lx, tried, events))) {
            eligible.add((
              key: key,
              count: e.value.length,
              lastSeen: e.value
                  .map((r) => r.read<int>('created_at'))
                  .reduce((a, b) => a > b ? a : b),
            ));
          }
        }
        // Newest first; the cap keeps the most recently seen merchants.
        eligible.sort((a, b) {
          final c = b.lastSeen.compareTo(a.lastSeen);
          return c != 0 ? c : a.key.compareTo(b.key);
        });
        final keep = eligible.take(llmCatQueueCap).toList();
        final keepKeys = {for (final k in keep) k.key};

        final stale = [
          for (final q in await queue.all())
            if (!keepKeys.contains(q.merchantNorm)) q.merchantNorm,
        ];
        var removed = await queue.remove(stale);
        for (final k in keep) {
          await queue.put(
            k.key,
            txnCount: k.count,
            lastSeenAt: k.lastSeen,
            at: nowMs,
          );
        }
        removed += await queue.trim(
          maxRows: llmCatQueueCap,
          expireBefore: since,
        );
        return LlmCatFillReport(
          ran: true,
          queued: await queue.count(),
          removed: removed,
        );
      }),
    );
  }

  static bool _rowEligible(
    QueryRow r,
    String key,
    NameLexicon lx,
    Map<String, String> tried,
    Map<String, TemplateEvent> events,
  ) {
    final direction = r.read<String>('direction');
    final storedKind = r.read<String?>('counterparty_kind');
    final tid = r.read<String?>('template_id');
    final event = tid == null ? null : events[tid];
    // Typed evidence only: a card / POS / online purchase template on an
    // expense row with no counterparty is a business payment. Nothing is
    // inferred from text; transfers, ATM, income, fees and unknown events
    // stay null (the rule then refuses).
    final counterpartyKind =
        storedKind ??
        (event != null && _businessEvidence(event, direction)
            ? 'merchant'
            : null);
    final paymentKind =
        event != null &&
            !_cardEvents.contains(event) &&
            event != TemplateEvent.refund
        ? LlmPaymentKind.unknown
        : null;
    final kind =
        paymentKind ??
        llmPaymentKindOf(
          direction: direction,
          source: r.read<String>('source'),
          counterpartyKind: counterpartyKind,
          isInternal: r.read<int>('is_internal') != 0,
          hasTransferPair: r.read<int>('paired') != 0,
        );
    final raw = r.read<String?>('merchant_raw');
    final input = categorizeInputFor(
      merchantRaw: raw,
      merchantNorm: key,
      counterpartyKind: counterpartyKind,
      counterpartyValue: r.read<String?>('counterparty_value'),
    );
    final onKey = LlmEligibility.check(
      input,
      key,
      lx,
      kind: kind,
      triedBefore: tried.containsKey,
    );
    if (!onKey.isEligible) return false;
    // The key is a transliteration; the raw text must not show an
    // identifier or a person's name either (stricter, fail closed).
    final cleaned = cleanMerchant(raw ?? '').cleaned;
    if (cleaned.trim().isEmpty) return true;
    final onRaw = LlmEligibility.check(input, cleaned, lx, kind: kind);
    return switch (onRaw) {
      Ineligible(reason: LlmIneligibleReason.identifier) ||
      Ineligible(reason: LlmIneligibleReason.personLike) ||
      Ineligible(reason: LlmIneligibleReason.lexiconMissing) => false,
      _ => true,
    };
  }

  /// The merchant keys the sender may send now, in send order: at most
  /// [batchMax], and at most the snapshot's remaining allowance. Empty when
  /// the gate is closed, the feature is paused until the next sync, or the
  /// snapshot says nothing is left before `resetsAt`. Refreshes the queue
  /// first, so a merchant that stopped qualifying is never picked. Sends
  /// nothing and counts nothing.
  Future<List<String>> pickForSend({
    required DateTime now,
    required int batchMax,
  }) async {
    if (batchMax <= 0) return const [];
    if (!await gate.open()) return const [];
    if (await gate.quota.isPaused(LlmFeature.categorise)) return const [];
    final snap = await gate.quota.current(LlmFeature.categorise, now);
    final limit = snap == null
        ? batchMax
        : (snap.remaining < batchMax ? snap.remaining : batchMax);
    if (limit <= 0) return const [];
    final report = await fill(now: now);
    if (!report.ran) return const [];
    final due = await LlmCatQueueDao(_db)
        .due(now: now.toUtc().millisecondsSinceEpoch, limit: limit);
    return [for (final q in due) q.merchantNorm];
  }
}

/// Stores the backend's answers and applies them (T-358 calls this).
class AiSuggestionApplier {
  AiSuggestionApplier(this._db, {required this.newCategorizer});

  final AppDatabase _db;

  /// A fresh categorizer over this database (with the AI tier).
  final Categorizer Function() newCategorizer;

  /// An `ok` answer: stores [categoryId] as [merchantNorm]'s `unconfirmed`
  /// suggestion (never over a user verdict), takes the merchant off the
  /// queue and fills its "needs classification" rows. One DB transaction;
  /// a repeat changes nothing. Returns the transactions changed.
  Future<int> accept({
    required String merchantNorm,
    required String categoryId,
    required int confidence,
    required String source,
    required DateTime at,
  }) {
    final ms = at.toUtc().millisecondsSinceEpoch;
    return guardWrite(
      () => _db.transaction(() async {
        await AiMerchantSuggestionsDao(_db).putAnswer(
          merchantNorm: merchantNorm,
          categoryId: categoryId,
          confidence: confidence,
          source: source,
          at: ms,
        );
        await LlmCatQueueDao(_db).remove([merchantNorm]);
        final r = await Recategorizer(_db)
            .applySuggestion(merchantNorm, newCategorizer(), at: ms);
        return r.changed;
      }),
    );
  }

  /// `unknown` / `low_confidence` / `rejected`: marked tried (never
  /// re-sent), off the queue; no transaction changes.
  Future<void> noAnswer({required String merchantNorm, required DateTime at}) =>
      guardWrite(
        () => _db.transaction(() async {
          await AiMerchantSuggestionsDao(_db).putNoAnswer(
            merchantNorm: merchantNorm,
            at: at.toUtc().millisecondsSinceEpoch,
          );
          await LlmCatQueueDao(_db).remove([merchantNorm]);
        }),
      );
}
