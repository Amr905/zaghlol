// T-049: the review queue (FR-ING-A-06). Nothing uncertain is lost: every
// item waits here until the user resolves it. Each action runs in one
// transaction and starts with the DAO's conditional resolve, so two taps or
// two engines have exactly one winner and the loser changes nothing.
// Payloads and message bodies are never logged or put into errors.

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/backend/outbound_text_filter.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/app_database_providers.dart';
import '../../../core/db/daos/outbox_dao.dart';
import '../../../core/db/daos/review_items_dao.dart';
import '../../../core/db/daos/write_errors.dart';
import '../../../core/db/db_errors.dart' show DbCorruptException;
import '../../transactions/data/drift_transaction_repository.dart'
    show Clock, IdGenerator;
import '../../transactions/data/transactions_providers.dart'
    show clockProvider, idGeneratorProvider;

/// `review_items.resolution` slugs this repository writes.
abstract final class ReviewResolution {
  static const String dismissed = 'dismissed';
  static const String manual = 'manual';
  static const String accepted = 'accepted';
  static const String bankRequested = 'bank_requested';

  /// T-250: the user removed an old due reminder saved as spending.
  static const String removed = 'removed';

  /// T-250: the user kept it (the transaction is now user-verified).
  static const String kept = 'kept';
}

/// Typed failure; the code never carries message text.
final class ReviewException extends SafeException {
  ReviewException(super.code);

  static const String notFound = 'REVIEW_NOT_FOUND';
  static const String invalid = 'REVIEW_INVALID';
  static const String notApplicable = 'REVIEW_NOT_APPLICABLE';
}

/// What the user typed for an unrecognized message (FR-ING-A-06).
final class ManualTxnInput {
  const ManualTxnInput({
    required this.accountId,
    required this.direction,
    required this.amount,
    this.originalAmount,
    required this.occurredAt,
    required this.tzOffsetMin,
    this.merchant,
    this.categoryId,
    this.source = 'manual',
    this.categorySource,
    this.merchantNorm,
    this.counterpartyKind,
    this.counterpartyValue,
    this.catalogMerchantId,
    this.allowForeignCurrency = false,
  });

  final String accountId;

  /// A stored direction code (`expense`, `income`, ...).
  final String direction;

  /// Positive; integer minor units in an explicit currency.
  final Money amount;

  /// A foreign amount read with the charge: its own currency, never summed.
  final Money? originalAmount;
  final DateTime occurredAt;
  final int tzOffsetMin;
  final String? merchant;
  final String? categoryId;

  /// Stored `transactions.source`: `manual` for typed input; the message's
  /// channel (`sms`, `notification`, ...) when the user confirmed a
  /// prefilled generic suggestion as read.
  final String source;

  /// Stored category source; null means `user` with a category, else `none`.
  final String? categorySource;
  final String? merchantNorm;

  /// The other party of a transfer read from the message (T-243).
  final String? counterpartyKind;
  final String? counterpartyValue;
  final int? catalogMerchantId;

  /// A message read in a currency other than the card's (a USD purchase on
  /// an EGP card) is stored as read, like ingest does; typed input keeps
  /// the account's currency.
  final bool allowForeignCurrency;
}

/// Outcome of a resolve call. [applied] is false when another actor had
/// already resolved the item (nothing changed).
final class ReviewOutcome {
  const ReviewOutcome({required this.applied, this.txnId});
  final bool applied;
  final String? txnId;
}

class ReviewRepository {
  ReviewRepository(this._db, {required this._clock, required this._newId})
    : _reviews = ReviewItemsDao(_db);

  final AppDatabase _db;
  final ReviewItemsDao _reviews;
  final Clock _clock;
  final IdGenerator _newId;

  int get _now => _clock().toUtc().millisecondsSinceEpoch;

  /// Open items, oldest first.
  Future<List<ReviewItemRow>> open({String? kind, int limit = 100}) =>
      guardRead(() => _reviews.open(kind: kind, limit: limit));

  Future<int> countOpen() => guardRead(_reviews.countOpen);

  /// Live open count for the Home pill.
  Stream<int> watchOpenCount() => _db
      .customSelect(
        'SELECT count(*) AS n FROM review_items WHERE resolved_at IS NULL',
        readsFrom: {_db.reviewItems},
      )
      .watchSingle()
      .map((r) => r.read<int>('n'));

  /// Dismiss: the item is resolved and its raw message (if any) is marked
  /// `dismissed`.
  Future<ReviewOutcome> dismiss(String itemId) => _act(itemId, (item) async {
    if (!await _resolve(item, ReviewResolution.dismissed)) {
      return const ReviewOutcome(applied: false);
    }
    // FU-122: an item that backs a stored transaction only drops the flag; its
    // raw message stays as parsed.
    if (item.txnId == null) await _setRawStatus(item.rawMessageId, 'dismissed');
    return const ReviewOutcome(applied: true);
  });

  /// Manual fields for an unrecognized message: creates a verified
  /// transaction linked to the raw message and marks the message `parsed`.
  Future<ReviewOutcome> resolveManually(
    String itemId,
    ManualTxnInput input,
  ) async {
    if (input.amount.minor <= 0 || input.accountId.isEmpty) {
      throw ReviewException(ReviewException.invalid);
    }
    return _act(itemId, (item) async {
      if ((item.kind != ReviewKind.unrecognized &&
              item.kind != ReviewKind.newSender) ||
          item.txnId != null) {
        throw ReviewException(ReviewException.notApplicable);
      }
      if (!await _resolve(item, ReviewResolution.manual)) {
        return const ReviewOutcome(applied: false);
      }
      final acc = await (_db.select(
        _db.accounts,
      )..where((a) => a.id.equals(input.accountId))).getSingleOrNull();
      if (acc == null ||
          (!input.allowForeignCurrency &&
              acc.defaultCurrency != input.amount.currency.code)) {
        // Rolls the resolve back: the transaction wrapper sees the throw.
        throw ReviewException(ReviewException.invalid);
      }
      final stored = input.amount.toStorage();
      final original = input.originalAmount?.toStorage();
      final id = _newId();
      final now = _now;
      await _db
          .into(_db.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: id,
              accountId: input.accountId,
              rawMessageId: Value(item.rawMessageId),
              source: input.source,
              direction: input.direction,
              amountMinor: stored.minor,
              currency: stored.currency,
              originalAmountMinor: Value(original?.minor),
              originalCurrency: Value(original?.currency),
              occurredAt: input.occurredAt.toUtc().millisecondsSinceEpoch,
              occurredTzOffsetMin: input.tzOffsetMin,
              merchantRaw: Value(input.merchant),
              merchantNorm: Value(input.merchantNorm),
              counterpartyKind: Value(input.counterpartyKind),
              counterpartyValue: Value(input.counterpartyValue),
              catalogMerchantId: Value(input.catalogMerchantId),
              categoryId: Value(input.categoryId),
              categorySource:
                  input.categorySource ??
                  (input.categoryId == null ? 'none' : 'user'),
              isUserVerified: const Value(1),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _setRawStatus(item.rawMessageId, 'parsed');
      return ReviewOutcome(applied: true, txnId: id);
    });
  }

  /// Accept the suggestion: resolves the item and, when it is about a
  /// transaction, marks that transaction user-verified. Applying a
  /// suggestion's own effect (subscription, offset link, ...) belongs to the
  /// feature that raised it.
  Future<ReviewOutcome> acceptSuggestion(String itemId) =>
      _act(itemId, (item) async {
        if (!await _resolve(item, ReviewResolution.accepted)) {
          return const ReviewOutcome(applied: false);
        }
        final txnId = item.txnId;
        if (txnId != null) {
          await (_db.update(
            _db.transactions,
          )..where((t) => t.id.equals(txnId))).write(
            TransactionsCompanion(
              isUserVerified: const Value(1),
              updatedAt: Value(_now),
            ),
          );
        }
        return ReviewOutcome(applied: true, txnId: txnId);
      });

  // ---- T-250: old due reminders saved as spending.

  /// The transaction behind the open old-due item [itemId] when it may
  /// still be removed: the item is open and of reason `oldDueNotice`, and
  /// its transaction is live and not user-verified (an edit since the offer
  /// locks it). Null otherwise; never writes.
  Future<String?> oldDueTxnToRemove(String itemId) => guardRead(() async {
    final item = await _reviews.byId(itemId);
    if (item == null || item.resolvedAt != null || !_isOldDue(item)) {
      return null;
    }
    final txnId = item.txnId!;
    final t = await (_db.select(
      _db.transactions,
    )..where((x) => x.id.equals(txnId))).getSingleOrNull();
    if (t == null || t.deletedAt != null || t.isUserVerified != 0) return null;
    return txnId;
  });

  /// Resolves the old-due item [itemId] as `removed` after the user's Remove
  /// deleted its transaction. False when it was resolved already.
  Future<bool> markOldDueRemoved(String itemId) => _act(itemId, (item) async {
    if (!_isOldDue(item)) {
      throw ReviewException(ReviewException.notApplicable);
    }
    return ReviewOutcome(
      applied: await _resolve(item, ReviewResolution.removed),
      txnId: item.txnId,
    );
  }).then((o) => o.applied);

  /// Keep: resolves the old-due item [itemId] as `kept` and marks its
  /// transaction user-verified, so it is never offered again. False when
  /// another actor resolved it first (nothing changed).
  Future<bool> keepOldDue(String itemId) => _act(itemId, (item) async {
    if (!_isOldDue(item)) {
      throw ReviewException(ReviewException.notApplicable);
    }
    if (!await _resolve(item, ReviewResolution.kept)) {
      return const ReviewOutcome(applied: false);
    }
    await (_db.update(
      _db.transactions,
    )..where((t) => t.id.equals(item.txnId!))).write(
      TransactionsCompanion(
        isUserVerified: const Value(1),
        updatedAt: Value(_now),
      ),
    );
    return ReviewOutcome(applied: true, txnId: item.txnId);
  }).then((o) => o.applied);

  static bool _isOldDue(ReviewItemRow item) {
    if (item.kind != ReviewKind.lowConfidence || item.txnId == null) {
      return false;
    }
    try {
      return reviewPayloadOf(item)?['reason'] == ReviewReason.oldDueNotice;
    } on DbCorruptException {
      return false;
    }
  }

  /// "Request my bank": queues a `bank_request` in the outbox (name,
  /// country and channel only, BR-SYNC-03) and resolves the item.
  Future<ReviewOutcome> requestMyBank(
    String itemId, {
    required String institutionName,
    String country = 'EG',
    String channel = 'sms',
  }) async {
    final name = institutionName.trim();
    if (!_validBankName(name) ||
        !RegExp(r'^[A-Z]{2}$').hasMatch(country) ||
        !const {'sms', 'notification'}.contains(channel)) {
      throw ReviewException(ReviewException.invalid);
    }
    return _act(itemId, (item) async {
      if (item.kind != ReviewKind.unrecognized &&
          item.kind != ReviewKind.newSender) {
        throw ReviewException(ReviewException.notApplicable);
      }
      if (!await _resolve(item, ReviewResolution.bankRequested)) {
        return const ReviewOutcome(applied: false);
      }
      await OutboxDao(_db).enqueue(
        id: _newId(),
        kind: OutboxKind.bankRequest,
        payload: {
          'institutionName': name,
          'country': country,
          'channel': channel,
        },
        createdAt: _now,
      );
      await _setRawStatus(item.rawMessageId, 'dismissed');
      return const ReviewOutcome(applied: true);
    });
  }

  // The server drops names with '@', a 6-digit run or over 64 characters
  // (BR-SYNC-04); refuse them here so the user is told at once.
  static bool _validBankName(String n) =>
      n.length >= 2 &&
      n.length <= 64 &&
      !hasPersonalDataMarks(n, minDigitRun: 6);

  Future<ReviewOutcome> _act(
    String itemId,
    Future<ReviewOutcome> Function(ReviewItemRow item) body,
  ) => guardWrite(
    () => _db.transaction(() async {
      final item = await _reviews.byId(itemId);
      if (item == null) throw ReviewException(ReviewException.notFound);
      return body(item);
    }),
  );

  Future<bool> _resolve(ReviewItemRow item, String resolution) =>
      _reviews.resolve(item.id, resolution: resolution, at: _now);

  Future<void> _setRawStatus(String? rawId, String status) async {
    if (rawId == null) return;
    await (_db.update(_db.rawMessages)..where((m) => m.id.equals(rawId))).write(
      RawMessagesCompanion(parseStatus: Value(status)),
    );
  }
}

final reviewRepositoryProvider = FutureProvider<ReviewRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return ReviewRepository(
    db,
    clock: ref.watch(clockProvider),
    newId: ref.watch(idGeneratorProvider),
  );
}, name: 'reviewRepositoryProvider');

/// Open review items, for the Home pill.
final reviewOpenCountProvider = StreamProvider<int>((ref) async* {
  final repo = await ref.watch(reviewRepositoryProvider.future);
  yield* repo.watchOpenCount();
}, name: 'reviewOpenCountProvider');
