// T-089: pairs own-account movements so they never count as spending or
// income (BR-XFR-01/02, FR-CUR-06, EC-15, EC-16; domain-algorithms §4).
//
// Safety rules (the money never disappears or doubles):
// - Every call is one database transaction (BEGIN IMMEDIATE), so the UI
//   engine and the background engine serialise. Every write is conditional
//   on the leg still being free (`transfer_pair_id IS NULL`, live) and the
//   pair table's UNIQUE out/in columns allow one pair per leg, so for any
//   two racing callers exactly one wins; the loser rolls back and reports
//   `skipped`. A leg is therefore in at most one pair and marked internal
//   exactly when it is in one (or is a one-sided own-account leg).
// - Nothing is paired on doubt: more than one possible match on either side
//   goes to the review queue (`transfer_ambiguous`); a cross-currency
//   match is only ever a suggestion (`fx_pair_suggestion`); no amount or
//   currency is changed, converted or merged.
// - Unlinking clears the flag on both legs in the same transaction.
// - Only `posted` transfer legs take part; soft-deleted rows never do.
//
// Failures are code-only; nothing here logs and no payload carries amounts.

import 'dart:convert' show jsonDecode;

import 'package:drift/drift.dart' show Value, Variable;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/accounts_dao.dart';
import '../../../core/db/daos/prices_dao.dart';
import '../../../core/db/daos/review_items_dao.dart';
import '../../../core/db/daos/transactions_dao.dart';
import '../../../core/db/daos/transfers_dao.dart';
import '../../../core/db/daos/write_errors.dart';
import '../../../core/db/db_errors.dart';
import '../data/drift_transaction_repository.dart'
    show Clock, IdGenerator, newUuidV4;
import 'transactions_changed_event.dart';

/// Failure codes of this use case.
///
/// `XFR_NOT_FOUND`: a leg is missing or soft-deleted.
/// `XFR_INVALID`: not a posted out/in pair of legs (or the same leg twice).
/// `XFR_ALREADY_PAIRED`: a leg is already in a pair; unlink it first.
final class TransferPairingException extends SafeException {
  TransferPairingException(super.code);

  static const String notFound = 'XFR_NOT_FOUND';
  static const String invalid = 'XFR_INVALID';
  static const String alreadyPaired = 'XFR_ALREADY_PAIRED';
}

/// What [TransferPairingUseCase.onPersisted] did.
enum PairingStatus {
  /// Paired with one counterpart; both legs are internal.
  paired,

  /// Own-account leg with no counterpart yet (EC-15): internal, waiting.
  oneSidedInternal,

  /// More than one possible match: a `transfer_ambiguous` review item is
  /// open; nothing was paired (EC-16).
  ambiguous,

  /// A cross-currency candidate exists: an `fx_pair_suggestion` is open;
  /// nothing was paired (FR-CUR-06).
  suggested,

  /// No match; the leg waits for a late message.
  none,

  /// Not a posted transfer leg, already paired, or another actor got there
  /// first. Nothing changed.
  skipped,
}

final class PairingResult {
  const PairingResult(this.status, {this.pairId, this.pairKind, this.event});

  final PairingStatus status;

  /// The pair written (`paired`, `oneSidedInternal`).
  final String? pairId;

  /// The `transfer_pairs.kind` written, when a pair was written.
  final String? pairKind;

  /// Published already when a bus was given; null when nothing changed.
  final TransactionsChanged? event;
}

/// Thrown inside the transaction to roll it back when a conditional write
/// found the leg no longer free. Never leaves this file.
final class _Lost implements Exception {
  const _Lost();
}

typedef _Row = ({
  String id,
  String accountId,
  bool isOut,
  String currency,
  int amountMinor,
  int occurredAt,
  int offsetMin,
});

class TransferPairingUseCase {
  /// [loadSchedule] gives the payday schedule in force (required, so the
  /// events always name the right cycles; FU-114 77-1a). [events] gets the
  /// `TransactionsChanged` (and the detective `MascotTrigger` after an auto
  /// pair) after each commit.
  TransferPairingUseCase(
    this._db, {
    required this._loadSchedule,
    Clock? clock,
    IdGenerator? newId,
    this._events,
  }) : _now = clock ?? DateTime.now,
       _newId = newId ?? newUuidV4,
       _txns = TransactionsDao(_db),
       _accounts = AccountsDao(_db),
       _prices = PricesDao(_db),
       _reviews = ReviewItemsDao(_db),
       _pairs = TransferPairsDao(_db);

  final AppDatabase _db;
  final Future<PaydaySchedule> Function() _loadSchedule;
  final Clock _now;
  final IdGenerator _newId;
  final DomainEventBus? _events;
  final TransactionsDao _txns;
  final AccountsDao _accounts;
  final PricesDao _prices;
  final ReviewItemsDao _reviews;
  final TransferPairsDao _pairs;

  /// Most legs one candidate read returns.
  static const int _poolLimit = 100;

  int _nowMs() => _now().toUtc().millisecondsSinceEpoch;

  /// Run after a transfer leg is stored or edited (and again when a late
  /// message arrives: each new leg calls this for itself and finds the
  /// waiting leg). Idempotent.
  Future<PairingResult> onPersisted(String txnId) async {
    if (txnId.isEmpty) _invalid();
    final schedule = await _loadSchedule();
    final now = _nowMs();
    PairingResult result;
    try {
      result = await _txns.inTransaction(() => _evaluate(txnId, schedule, now));
    } on _Lost {
      return const PairingResult(PairingStatus.skipped);
    } on DbWriteException catch (e) {
      // A UNIQUE clash on the pair table means another actor paired the
      // leg first (rolled back); any other failure is real.
      if (e.code != DbWriteException.constraintUnique) rethrow;
      return const PairingResult(PairingStatus.skipped);
    }
    _publish(result);
    return result;
  }

  /// Links [outId] (a `transfer_out`) and [inId] (a `transfer_in`) by hand
  /// (FR-XFR-02): same currency gives kind `manual`, another currency
  /// `cross_currency`. Amounts are not compared (fees differ) and nothing
  /// is converted. An own-account out leg waiting alone is completed.
  /// Open review items about either leg are resolved as `linked`.
  Future<PairingResult> link(String outId, String inId) async {
    if (outId.isEmpty || inId.isEmpty || outId == inId) _invalid();
    final schedule = await _loadSchedule();
    final now = _nowMs();
    PairingResult result;
    try {
      result = await _txns.inTransaction(() async {
        final o = await _legRow(outId);
        final i = await _legRow(inId);
        if (o == null || i == null) {
          throw TransferPairingException(TransferPairingException.notFound);
        }
        if (!o.isOut || i.isOut) _invalid();
        if (o.currency == i.currency && o.accountId == i.accountId) _invalid();
        final kind = o.currency == i.currency
            ? TransferPairKind.manual
            : TransferPairKind.crossCurrency;
        final pairId = await _writePair(o, i, kind, now);
        await _resolveReviews([o.id, i.id], 'linked', now);
        return PairingResult(
          PairingStatus.paired,
          pairId: pairId,
          pairKind: kind,
          event: await _event(schedule, [o, i]),
        );
      });
    } on _Lost {
      throw TransferPairingException(TransferPairingException.alreadyPaired);
    } on DbWriteException catch (e) {
      if (e.code != DbWriteException.constraintUnique) rethrow;
      throw TransferPairingException(TransferPairingException.alreadyPaired);
    }
    _publish(result, mascot: false);
    return result;
  }

  /// Unpairs the pair that [txnId] is a leg of and clears `is_internal` on
  /// both legs, in one transaction (FR-XFR-02). For a one-sided internal
  /// leg without a pair row it clears the flag. Returns the event, or null
  /// when there was nothing to undo (already unlinked, perhaps by another
  /// actor). The legs are not paired again by this call.
  Future<TransactionsChanged?> unlink(String txnId) async {
    if (txnId.isEmpty) _invalid();
    final schedule = await _loadSchedule();
    final now = _nowMs();
    final event = await _txns.inTransaction(() async {
      final pair = await _pairs.forTransaction(txnId);
      final ids = <String>{txnId};
      if (pair != null) {
        if (await _pairs.deleteById(pair.id) != 1) return null;
        ids
          ..add(pair.outTxnId)
          ..addAll([?pair.inTxnId]);
      }
      var cleared = 0;
      for (final id in ids) {
        cleared += await _db.customUpdate(
          'UPDATE transactions SET is_internal = 0, updated_at = ?2 '
          'WHERE id = ?1 AND transfer_pair_id IS NULL AND is_internal = 1',
          variables: [Variable.withString(id), Variable.withInt(now)],
          updates: {_db.transactions},
        );
      }
      if (cleared == 0 && pair == null) return null;
      for (final id in ids) {
        await _rememberUnlink(id, [
          for (final other in ids)
            if (other != id) other,
        ], now);
      }
      final rows = <_Row>[
        for (final id in ids) ?await _legRow(id, anyStatus: true),
      ];
      return _event(schedule, rows);
    });
    if (event != null) _events?.publish(event);
    return event;
  }

  /// Run after a transfer leg is deleted (soft or hard): dissolves its pair
  /// and frees the surviving leg, which counts again unless it is an
  /// own-account leg by its own right. Returns the event, or null when the
  /// leg was in no pair.
  Future<TransactionsChanged?> onRemoved(String txnId) async {
    if (txnId.isEmpty) _invalid();
    final schedule = await _loadSchedule();
    final now = _nowMs();
    final event = await _txns.inTransaction(() async {
      final pair = await _pairs.forTransaction(txnId);
      if (pair == null) return null;
      if (await _pairs.deleteById(pair.id) != 1) return null;
      final rows = <_Row>[];
      for (final id in {pair.outTxnId, ?pair.inTxnId}) {
        final r = await _legRow(id, anyStatus: true);
        if (r != null) rows.add(r);
        if (id == txnId) continue;
        await _freeLeg(id, now);
        final t = await _txns.byId(id);
        if (t != null &&
            t.deletedAt == null &&
            t.status == 'posted' &&
            t.counterpartyKind == 'own_account') {
          final kind = await _isCardSettlement(t.counterpartyValue)
              ? TransferPairKind.cardSettlement
              : TransferPairKind.auto;
          await _markOneSided(_rowOf(t), kind, now);
        }
      }
      final gone = await _txns.byId(txnId);
      if (gone != null && rows.every((r) => r.id != txnId)) {
        rows.add(_rowOf(gone));
      }
      return _event(schedule, rows);
    });
    if (event != null) _events?.publish(event);
    return event;
  }

  Future<void> _freeLeg(String id, int now) => _db.customUpdate(
    'UPDATE transactions SET is_internal = 0, transfer_pair_id = NULL, '
    'updated_at = ?2 WHERE id = ?1',
    variables: [Variable.withString(id), Variable.withInt(now)],
    updates: {_db.transactions},
  );

  /// A resolved review item per leg holding the legs it must not be paired
  /// with again (an empty list: do not re-mark it one-sided either).
  Future<void> _rememberUnlink(String id, List<String> others, int now) async {
    final itemId = _newId();
    await _reviews.insert(
      id: itemId,
      kind: ReviewKind.transferAmbiguous,
      txnId: id,
      payload: {'candidates': others},
      createdAt: now,
    );
    await _reviews.resolve(itemId, resolution: _unlinked, at: now);
  }

  static const String _unlinked = 'unlinked';

  /// Legs the user unlinked from [id]; null when it was never unlinked.
  Future<Set<String>?> _unlinkedFrom(String id) async {
    final rows = await _db
        .customSelect(
          'SELECT payload FROM review_items WHERE kind = ?1 '
          'AND resolution = ?2 AND txn_id = ?3',
          variables: [
            Variable.withString(ReviewKind.transferAmbiguous),
            Variable.withString(_unlinked),
            Variable.withString(id),
          ],
          readsFrom: {_db.reviewItems},
        )
        .get();
    if (rows.isEmpty) return null;
    final out = <String>{};
    for (final r in rows) {
      final raw = r.read<String?>('payload');
      if (raw == null) continue;
      final c = (jsonDecode(raw) as Map)['candidates'];
      if (c is List) out.addAll(c.whereType<String>());
    }
    return out;
  }

  // ---------------------------------------------------------------- core

  Future<PairingResult> _evaluate(
    String txnId,
    PaydaySchedule schedule,
    int now,
  ) async {
    const skipped = PairingResult(PairingStatus.skipped);
    final row = await _txns.byId(txnId);
    if (row == null ||
        row.deletedAt != null ||
        row.status != 'posted' ||
        row.amountMinor <= 0 ||
        (row.direction != 'transfer_out' && row.direction != 'transfer_in')) {
      return skipped;
    }
    final self = _rowOf(row);
    var existing = row.transferPairId == null
        ? null
        : await _pairs.byId(row.transferPairId!);
    if (existing != null && existing.inTxnId != null) {
      final otherId = existing.outTxnId == txnId
          ? existing.inTxnId!
          : existing.outTxnId;
      final other = await _txns.byId(otherId);
      if (other == null || other.deletedAt != null) {
        await _pairs.deleteById(existing.id);
        await _freeLeg(txnId, now);
        existing = null;
      }
    }
    // Already in a complete pair: nothing to do. A one-sided out leg may
    // still find its counterpart.
    if (existing != null && (existing.inTxnId != null || !self.isOut)) {
      return skipped;
    }
    final account = await _accounts.byId(self.accountId);
    final leg = _legOf(self);
    final unlinked = await _unlinkedFrom(txnId);
    final pool = await _freeLegs(
      self,
      within: transferPairWindow,
      skip: unlinked,
    );

    switch (decideSameCurrency(leg, pool.values.map(_legOf))) {
      case PairWith(:final counterpart):
        final other = pool[counterpart.id]!;
        final o = self.isOut ? self : other;
        final i = self.isOut ? other : self;
        final inAccount = await _accounts.byId(i.accountId);
        final kind = (inAccount?.kind == 'credit' || inAccount?.kind == 'bnpl')
            ? TransferPairKind.cardSettlement
            : TransferPairKind.auto;
        final pairId = await _writePair(o, i, kind, now);
        await _resolveReviews([o.id, i.id], 'paired', now);
        return PairingResult(
          PairingStatus.paired,
          pairId: pairId,
          pairKind: kind,
          event: await _event(schedule, [o, i]),
        );
      case AmbiguousMatch(:final candidateIds):
        await _openReview(
          ReviewKind.transferAmbiguous,
          txnId,
          candidateIds,
          now,
        );
        return const PairingResult(PairingStatus.ambiguous);
      case NoMatch():
        break;
    }

    // Two legs of one conversion inside a multi-currency account.
    if (account?.kind == 'multi_currency') {
      final cands = fxConversionCandidates(leg, pool.values.map(_legOf));
      if (cands.isNotEmpty) {
        final unique =
            cands.length == 1 &&
            fxConversionCandidates(cands.single, [
                  ...pool.values.map(_legOf),
                  leg,
                ]).length ==
                1;
        if (!unique) {
          await _openReview(ReviewKind.transferAmbiguous, txnId, [
            for (final c in cands) c.id,
          ], now);
          return const PairingResult(PairingStatus.ambiguous);
        }
        final other = pool[cands.single.id]!;
        final o = self.isOut ? self : other;
        final i = self.isOut ? other : self;
        if (await _rateFits(o, i)) {
          final pairId = await _writePair(
            o,
            i,
            TransferPairKind.fxConversion,
            now,
          );
          await _resolveReviews([o.id, i.id], 'paired', now);
          return PairingResult(
            PairingStatus.paired,
            pairId: pairId,
            pairKind: TransferPairKind.fxConversion,
            event: await _event(schedule, [o, i]),
          );
        }
        // A known rate says these amounts are not one conversion.
        await _openReview(ReviewKind.fxPairSuggestion, txnId, [other.id], now);
        return const PairingResult(PairingStatus.suggested);
      }
    }

    // Cross-currency candidates are suggestions only.
    final wide = await _freeLegs(
      self,
      within: crossCurrencyWindow,
      skip: unlinked,
    );
    final rates = await _ratesFor(wide.values.map(_legOf), leg);
    final cross = crossCurrencyCandidates(
      leg,
      wide.values.map(_legOf),
      (from, to) => rates['${from.code}>${to.code}'],
    );
    if (cross.isNotEmpty) {
      final opened = await _openReview(
        ReviewKind.fxPairSuggestion,
        txnId,
        [for (final c in cross.take(5)) c.id],
        now,
        alsoSkipIfOpenOn: [for (final c in cross) c.id],
      );
      if (opened) return const PairingResult(PairingStatus.suggested);
    }

    // Own-account counterparty with no match yet (EC-15, cc payment).
    if (row.counterpartyKind == 'own_account' &&
        existing == null &&
        unlinked == null) {
      final kind = await _isCardSettlement(row.counterpartyValue)
          ? TransferPairKind.cardSettlement
          : TransferPairKind.auto;
      final pairId = await _markOneSided(self, kind, now);
      return PairingResult(
        PairingStatus.oneSidedInternal,
        pairId: pairId,
        pairKind: kind,
        event: await _event(schedule, [self]),
      );
    }
    return const PairingResult(PairingStatus.none);
  }

  /// True when [last4] names one of the user's credit or BNPL accounts.
  Future<bool> _isCardSettlement(String? last4) async {
    if (last4 == null || last4.isEmpty) return false;
    final n = await _db
        .customSelect(
          'SELECT count(*) AS n FROM accounts WHERE last4 = ?1 '
          "AND kind IN ('credit','bnpl')",
          variables: [Variable.withString(last4)],
          readsFrom: {_db.accounts},
        )
        .getSingle();
    return n.read<int>('n') > 0;
  }

  /// With a known rate, the two legs of a conversion must agree within the
  /// 3% band; with none known there is nothing to contradict the explicit
  /// transfer directions.
  Future<bool> _rateFits(_Row o, _Row i) async {
    final from = Currency.of(o.currency);
    final to = Currency.of(i.currency);
    final rate = await _rate(from, to);
    if (rate == null) return true;
    final expected = convertWithRate(Money(from, o.amountMinor), to, rate);
    return expected != null &&
        withinTolerance(
          expected,
          Money(to, i.amountMinor),
          crossCurrencyToleranceBp,
        );
  }

  Future<Map<String, int>> _ratesFor(
    Iterable<TransferLeg> pool,
    TransferLeg leg,
  ) async {
    final out = <String, int>{};
    for (final c in {for (final p in pool) p.amount.currency}) {
      final from = leg.amount.currency;
      if (c == from) continue;
      final r = await _rate(from, c);
      if (r != null) out['${from.code}>${c.code}'] = r;
    }
    return out;
  }

  /// Direct rate, else the inverse of the opposite rate (integer math).
  Future<int?> _rate(Currency from, Currency to) async {
    final direct = await _prices.rate(from, to);
    if (direct != null && direct.rateE9 > 0) return direct.rateE9;
    final back = await _prices.rate(to, from);
    if (back == null || back.rateE9 <= 0) return null;
    final inv =
        (BigInt.from(10).pow(18) + BigInt.from(back.rateE9) ~/ BigInt.two) ~/
        BigInt.from(back.rateE9);
    return inv > BigInt.zero && inv <= BigInt.from(Money.maxMinor)
        ? inv.toInt()
        : null;
  }

  // -------------------------------------------------------------- writes

  /// Pairs [o] and [i] with every write conditional; throws [_Lost] (the
  /// transaction rolls back) when either leg is no longer free.
  Future<String> _writePair(_Row o, _Row i, String kind, int now) async {
    final oneSided = await _pairs.forTransaction(o.id);
    final String pairId;
    if (oneSided != null) {
      // Complete a waiting one-sided out leg.
      if (oneSided.outTxnId != o.id || oneSided.inTxnId != null) {
        throw const _Lost();
      }
      pairId = oneSided.id;
      final n = await guardWrite(
        () => _db.customUpdate(
          'UPDATE transfer_pairs SET in_txn_id = ?2, kind = ?3 '
          'WHERE id = ?1 AND in_txn_id IS NULL',
          variables: [
            Variable.withString(pairId),
            Variable.withString(i.id),
            Variable.withString(kind),
          ],
          updates: {_db.transferPairs},
        ),
      );
      if (n != 1) throw const _Lost();
    } else {
      pairId = _newId();
      await _pairs.insert(
        TransferPairsCompanion.insert(
          id: pairId,
          outTxnId: o.id,
          inTxnId: Value(i.id),
          kind: kind,
          createdAt: now,
        ),
      );
      await _claim(o.id, pairId, now);
    }
    await _claim(i.id, pairId, now);
    return pairId;
  }

  /// One-sided own-account leg (EC-15): an out leg gets a pair row with no
  /// in side; an in leg (the schema has no such row) is only flagged.
  Future<String?> _markOneSided(_Row r, String kind, int now) async {
    if (!r.isOut) {
      await _claim(r.id, null, now);
      return null;
    }
    final pairId = _newId();
    await _pairs.insert(
      TransferPairsCompanion.insert(
        id: pairId,
        outTxnId: r.id,
        kind: kind,
        createdAt: now,
      ),
    );
    await _claim(r.id, pairId, now);
    return pairId;
  }

  /// Marks [id] internal and points it at [pairId], only while it is live
  /// and has no pair. Exactly one row must change.
  Future<void> _claim(String id, String? pairId, int now) async {
    final n = await guardWrite(
      () => _db.customUpdate(
        'UPDATE transactions SET is_internal = 1, transfer_pair_id = ?2, '
        'updated_at = ?3 WHERE id = ?1 AND deleted_at IS NULL '
        'AND transfer_pair_id IS NULL',
        variables: [
          Variable.withString(id),
          Variable<String>(pairId),
          Variable.withInt(now),
        ],
        updates: {_db.transactions},
      ),
    );
    if (n != 1) throw const _Lost();
  }

  /// Opens a review item for [txnId] unless an open one of the same kind
  /// already exists on it (or on a leg in [alsoSkipIfOpenOn]). Returns true
  /// when one is open afterwards.
  Future<bool> _openReview(
    String kind,
    String txnId,
    List<String> candidateIds,
    int now, {
    List<String> alsoSkipIfOpenOn = const [],
  }) async {
    final ids = [txnId, ...alsoSkipIfOpenOn];
    final marks = [for (var k = 0; k < ids.length; k++) '?${k + 2}'].join(',');
    final open = await _db
        .customSelect(
          'SELECT count(*) AS n FROM review_items WHERE kind = ?1 '
          'AND resolved_at IS NULL AND txn_id IN ($marks)',
          variables: [
            Variable.withString(kind),
            for (final id in ids) Variable.withString(id),
          ],
          readsFrom: {_db.reviewItems},
        )
        .getSingle();
    if (open.read<int>('n') > 0) return true;
    await _reviews.insert(
      id: _newId(),
      kind: kind,
      txnId: txnId,
      payload: {'candidates': candidateIds},
      createdAt: now,
    );
    return true;
  }

  Future<void> _resolveReviews(List<String> ids, String how, int now) async {
    final marks = [for (var k = 0; k < ids.length; k++) '?${k + 3}'].join(',');
    await guardWrite(
      () => _db.customUpdate(
        'UPDATE review_items SET resolved_at = ?1, resolution = ?2 '
        "WHERE resolved_at IS NULL AND kind IN ('transfer_ambiguous',"
        "'fx_pair_suggestion') AND txn_id IN ($marks)",
        variables: [
          Variable.withInt(now),
          Variable.withString(how),
          for (final id in ids) Variable.withString(id),
        ],
        updates: {_db.reviewItems},
      ),
    );
  }

  // --------------------------------------------------------------- reads

  _Row _rowOf(TransactionRow r) => (
    id: r.id,
    accountId: r.accountId,
    isOut: r.direction == 'transfer_out',
    currency: r.currency,
    amountMinor: r.amountMinor,
    occurredAt: r.occurredAt,
    offsetMin: r.occurredTzOffsetMin,
  );

  TransferLeg _legOf(_Row r) => TransferLeg(
    id: r.id,
    accountId: r.accountId,
    isOut: r.isOut,
    amount: Money(Currency.of(r.currency), r.amountMinor),
    occurredAt: DateTime.fromMillisecondsSinceEpoch(r.occurredAt, isUtc: true),
  );

  /// A live transfer leg by id (posted unless [anyStatus]).
  Future<_Row?> _legRow(String id, {bool anyStatus = false}) async {
    final row = await _txns.byId(id);
    if (row == null ||
        row.deletedAt != null ||
        (row.direction != 'transfer_out' && row.direction != 'transfer_in') ||
        (!anyStatus && (row.status != 'posted' || row.amountMinor <= 0))) {
      return null;
    }
    return _rowOf(row);
  }

  /// Free legs (live, posted, transfer, unpaired or a one-sided out) within
  /// [within] of [self], nearest first, by id.
  Future<Map<String, _Row>> _freeLegs(
    _Row self, {
    required Duration within,
    Set<String>? skip,
  }) async {
    final w = within.inMilliseconds;
    final rows = await _db
        .customSelect(
          'SELECT t.id, t.account_id, t.direction, t.currency, '
          't.amount_minor, t.occurred_at, t.occurred_tz_offset_min '
          'FROM transactions t '
          'LEFT JOIN transfer_pairs p ON p.id = t.transfer_pair_id '
          'WHERE t.deleted_at IS NULL AND t.status = \'posted\' '
          "AND t.direction IN ('transfer_out','transfer_in') "
          'AND t.amount_minor > 0 AND t.id <> ?1 '
          'AND t.occurred_at BETWEEN ?2 AND ?3 '
          'AND (p.id IS NULL OR (p.in_txn_id IS NULL AND p.out_txn_id = t.id)) '
          'ORDER BY abs(t.occurred_at - ?4), t.id LIMIT ?5',
          variables: [
            Variable.withString(self.id),
            Variable.withInt(self.occurredAt - w),
            Variable.withInt(self.occurredAt + w),
            Variable.withInt(self.occurredAt),
            Variable.withInt(_poolLimit),
          ],
          readsFrom: {_db.transactions, _db.transferPairs},
        )
        .get();
    return {
      for (final r in rows)
        if (skip == null || !skip.contains(r.read<String>('id')))
          r.read<String>('id'): (
            id: r.read<String>('id'),
            accountId: r.read<String>('account_id'),
            isOut: r.read<String>('direction') == 'transfer_out',
            currency: r.read<String>('currency'),
            amountMinor: r.read<int>('amount_minor'),
            occurredAt: r.read<int>('occurred_at'),
            offsetMin: r.read<int>('occurred_tz_offset_min'),
          ),
    };
  }

  Future<TransactionsChanged> _event(
    PaydaySchedule schedule,
    List<_Row> rows,
  ) => transactionsChangedFor(_db, schedule, [
    for (final r in rows)
      (
        id: r.id,
        accountId: r.accountId,
        occurredAt: r.occurredAt,
        offsetMin: r.offsetMin,
      ),
  ]);

  void _publish(PairingResult r, {bool mascot = true}) {
    final bus = _events;
    final e = r.event;
    if (bus == null || e == null) return;
    bus.publish(e);
    if (mascot &&
        r.status == PairingStatus.paired &&
        r.pairKind == TransferPairKind.auto) {
      bus.publish(
        const MascotTrigger(pose: 'detective', reason: 'self_transfer'),
      );
    }
  }

  static Never _invalid() =>
      throw TransferPairingException(TransferPairingException.invalid);
}
