// T-081: providers and the action port for the review queue (S-14). Widgets
// read [reviewQueueProvider] and call [ReviewActions]; nothing here logs
// and no message text is loaded (only the sender name).

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/db/app_database.dart';
import '../../../../core/db/app_database_providers.dart';
import '../../../../core/db/daos/review_items_dao.dart';
import '../../../budget/application/budget_providers.dart';
import '../../../recurring/data/recurring_repository.dart';
import '../../../transactions/application/transfer_pairing.dart';
import '../../../transfers/application/suggestion_providers.dart';
import '../../../transactions/data/transactions_providers.dart';
import '../../../transactions/domain/transaction.dart';
import '../../../transactions/domain/transaction_repository.dart';
import '../../data/review_repository.dart';
import 'review_models.dart';

/// What the screen can do. A port, so widget tests use a fake.
abstract interface class ReviewActions {
  /// Files the transaction under [categoryId] and clears the item.
  Future<void> categorize(CategoryCardModel card, String categoryId);
  Future<void> dismiss(String itemId);
  Future<void> accept(String itemId);
  Future<void> confirmSubscription(SubscriptionCardModel card);
  Future<void> dismissSubscription(SubscriptionCardModel card);

  /// Links the waiting leg with [option]; null means "not my transfer".
  Future<void> resolveTransfer(
    TransferCardModel card,
    ReviewTransferOption? option,
  );
  Future<void> requestBank(
    String itemId, {
    required String name,
    required String country,
    required String channel,
  });
}

final class _LiveActions implements ReviewActions {
  _LiveActions(this._ref);
  final Ref _ref;

  Future<ReviewRepository> get _reviews =>
      _ref.read(reviewRepositoryProvider.future);

  void _refresh() => _ref.invalidate(reviewQueueProvider);

  @override
  Future<void> categorize(CategoryCardModel card, String categoryId) async {
    final txns = await _ref.read(transactionRepositoryProvider.future);
    await txns.edit(
      card.txnId,
      TransactionEdit(categoryId: Maybe<String?>(categoryId)),
    );
    await (await _reviews).acceptSuggestion(card.itemId);
    _refresh();
  }

  /// The open pair suggestion (T-092) behind [itemId], or null for any
  /// other kind of item.
  Future<ReviewItemRow?> _pairItem(String itemId) async {
    final db = await _ref.read(appDatabaseProvider.future);
    final row = await ReviewItemsDao(db).byId(itemId);
    if (row == null || row.resolvedAt != null) return null;
    return row.kind == ReviewKind.reimbursementSuggestion ||
            row.kind == ReviewKind.fxPairSuggestion
        ? row
        : null;
  }

  @override
  Future<void> dismiss(String itemId) async {
    final pair = await _pairItem(itemId);
    if (pair != null) {
      // Remembered: the candidates are not suggested again.
      await (await _ref.read(pairSuggestionsProvider.future)).dismiss(itemId);
    } else {
      await (await _reviews).dismiss(itemId);
    }
    _refresh();
  }

  @override
  Future<void> accept(String itemId) async {
    final pair = await _pairItem(itemId);
    if (pair == null) {
      await (await _reviews).acceptSuggestion(itemId);
    } else {
      // The best candidate is first; the card names no other choice.
      final c = reviewPayloadOf(pair)?['candidates'];
      final candidate = c is List && c.isNotEmpty ? c.first : null;
      if (candidate is! String) {
        await (await _ref.read(pairSuggestionsProvider.future)).dismiss(itemId);
      } else {
        final s = await _ref.read(pairSuggestionsProvider.future);
        if (pair.kind == ReviewKind.reimbursementSuggestion) {
          await s.acceptReimbursement(itemId, candidate);
        } else {
          await s.acceptFxPair(itemId, candidate);
        }
      }
    }
    _refresh();
  }

  @override
  Future<void> confirmSubscription(SubscriptionCardModel card) async {
    final repo = await _ref.read(recurringRepositoryProvider.future);
    await repo.confirm(card.recurringItemId);
    _refresh();
  }

  @override
  Future<void> dismissSubscription(SubscriptionCardModel card) async {
    final repo = await _ref.read(recurringRepositoryProvider.future);
    await repo.dismiss(card.recurringItemId);
    _refresh();
  }

  @override
  Future<void> resolveTransfer(
    TransferCardModel card,
    ReviewTransferOption? option,
  ) async {
    if (option == null) {
      await dismiss(card.itemId);
      return;
    }
    final db = await _ref.read(appDatabaseProvider.future);
    final pairing = TransferPairingUseCase(
      db,
      loadSchedule: () => _ref.read(paydayScheduleProvider.future),
      clock: _ref.read(clockProvider),
      newId: _ref.read(idGeneratorProvider),
    );
    final outId = card.isIncomeLeg ? option.txnId : card.txnId;
    final inId = card.isIncomeLeg ? card.txnId : option.txnId;
    await pairing.link(outId, inId);
    _refresh();
  }

  @override
  Future<void> requestBank(
    String itemId, {
    required String name,
    required String country,
    required String channel,
  }) async {
    await (await _reviews).requestMyBank(
      itemId,
      institutionName: name,
      country: country,
      channel: channel,
    );
    _refresh();
  }
}

final reviewActionsProvider = Provider<ReviewActions>(
  _LiveActions.new,
  name: 'reviewActionsProvider',
);

/// Category chips (system categories, not archived).
final reviewCategoriesProvider = FutureProvider<List<ReviewCategory>>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final rows =
      await (db.select(db.categories)
            ..where((c) => c.isArchived.equals(0) & c.parentId.isNull())
            ..orderBy([(c) => OrderingTerm.asc(c.sort)]))
          .get();
  return [
    for (final r in rows)
      ReviewCategory(id: r.id, nameAr: r.nameAr, nameEn: r.nameEn),
  ];
}, name: 'reviewCategoriesProvider');

/// Open review items as cards, oldest first. Reloads when the open count
/// changes (so the Home pill and this list stay in step).
final reviewQueueProvider = FutureProvider<List<ReviewCardModel>>((ref) async {
  ref.watch(reviewOpenCountProvider);
  final reviews = await ref.watch(reviewRepositoryProvider.future);
  final txns = await ref.watch(transactionRepositoryProvider.future);
  final db = await ref.watch(appDatabaseProvider.future);
  final items = await reviews.open();
  final cards = <ReviewCardModel>[];
  for (final item in items) {
    final card = await _toCard(db, txns, item);
    if (card != null) cards.add(card);
  }
  return cards;
}, name: 'reviewQueueProvider');

Map<String, Object?> _payload(ReviewItemRow item) {
  final p = item.payload;
  if (p == null) return const {};
  try {
    final d = jsonDecode(p);
    return d is Map<String, Object?> ? d : const {};
  } on FormatException {
    return const {};
  }
}

Future<String> _sender(AppDatabase db, String? rawId) async {
  if (rawId == null) return '';
  final row = await (db.select(
    db.rawMessages,
  )..where((m) => m.id.equals(rawId))).getSingleOrNull();
  return row?.sender ?? '';
}

Future<ReviewCardModel?> _toCard(
  AppDatabase db,
  TransactionRepository txns,
  ReviewItemRow item,
) async {
  final payload = _payload(item);
  final TransactionRecord? txn = item.txnId == null
      ? null
      : await txns.byId(item.txnId!);
  bool income(TransactionRecord t) =>
      t.direction == TxnDirection.income ||
      t.direction == TxnDirection.transferIn ||
      t.direction == TxnDirection.refund;
  switch (item.kind) {
    case ReviewKind.needsCategory:
      if (txn == null) return null;
      return CategoryCardModel(
        itemId: item.id,
        txnId: txn.id,
        amount: txn.amount,
        isIncome: income(txn),
        merchant: txn.merchantRaw,
        counterparty:
            txn.direction == TxnDirection.transferOut ||
                txn.direction == TxnDirection.transferIn
            ? txn.merchantRaw
            : null,
      );
    case ReviewKind.lowConfidence:
    case ReviewKind.newSender:
    case ReviewKind.unrecognized:
      return MessageCardModel(
        itemId: item.id,
        sender: await _sender(db, item.rawMessageId),
        isNewSender: item.kind == ReviewKind.newSender,
        txnId: txn?.id,
        amount: txn?.amount,
        isIncome: txn != null && income(txn),
        merchant: txn?.merchantRaw,
      );
    case ReviewKind.transferAmbiguous:
      if (txn == null) return null;
      final ids = [
        for (final c in (payload['candidates'] as List<Object?>? ?? const []))
          if (c is String) c,
      ];
      final options = <ReviewTransferOption>[];
      for (final id in ids) {
        final t = await txns.byId(id);
        if (t == null) continue;
        options.add(
          ReviewTransferOption(
            txnId: t.id,
            amount: t.amount,
            accountLabel: await _accountLabel(db, t.accountId),
            occurredAt: t.occurredAt,
          ),
        );
      }
      return TransferCardModel(
        itemId: item.id,
        txnId: txn.id,
        amount: txn.amount,
        accountLabel: await _accountLabel(db, txn.accountId),
        isIncomeLeg: txn.direction == TxnDirection.transferIn,
        options: options,
      );
    case ReviewKind.subscriptionSuggestion:
      final rid = payload['itemId'];
      if (rid is! String) return null;
      final r = await (db.select(
        db.recurringItems,
      )..where((x) => x.id.equals(rid))).getSingleOrNull();
      if (r == null) return null;
      final cur = Currency.tryOf(r.currency);
      return SubscriptionCardModel(
        itemId: item.id,
        recurringItemId: rid,
        name: r.name,
        amount: cur == null ? null : Money.tryMinor(cur, r.amountMinor),
      );
    default:
      return SuggestionCardModel(
        itemId: item.id,
        kind: item.kind,
        ambiguousRefund: payload['type'] == 'refund_ambiguous',
        amount: txn?.amount,
        merchant: txn?.merchantRaw,
      );
  }
}

Future<String> _accountLabel(AppDatabase db, String accountId) async {
  final a = await (db.select(
    db.accounts,
  )..where((x) => x.id.equals(accountId))).getSingleOrNull();
  if (a == null) return '';
  return a.last4 == null ? a.label : '${a.label} •${a.last4}';
}
