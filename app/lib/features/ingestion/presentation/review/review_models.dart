// T-081: view models for the review queue (S-14). Plain Dart: built by the
// providers from review items, rendered by the screen. Message text is never
// part of a model; only the sender name, amounts and ids.

import 'package:zaghlol_domain/zaghlol_domain.dart';

/// The filter chips (S-14).
enum ReviewFilter { all, category, messages, transfers }

/// One category choice for the chips.
final class ReviewCategory {
  const ReviewCategory({
    required this.id,
    required this.nameAr,
    required this.nameEn,
  });
  final String id;
  final String nameAr;
  final String nameEn;
}

/// A leg a transfer might belong to.
final class ReviewTransferOption {
  const ReviewTransferOption({
    required this.txnId,
    required this.amount,
    required this.accountLabel,
    required this.occurredAt,
    this.merchant,
  });
  final String txnId;
  final Money amount;
  final String accountLabel;

  /// The raw merchant of the candidate, shown as the row title.
  final String? merchant;
  final DateTime occurredAt;
}

sealed class ReviewCardModel {
  const ReviewCardModel(this.itemId);
  final String itemId;

  ReviewFilter get filter;
}

/// "What was this?": a transaction waiting for a category.
final class CategoryCardModel extends ReviewCardModel {
  const CategoryCardModel({
    required String itemId,
    required this.txnId,
    required this.amount,
    required this.isIncome,
    this.counterparty,
    this.merchant,
  }) : super(itemId);
  final String txnId;
  final Money amount;
  final bool isIncome;

  /// Set for a transfer-like row (instapay handle), else null.
  final String? counterparty;
  final String? merchant;

  @override
  ReviewFilter get filter => ReviewFilter.category;
}

/// A low-confidence / new-sender guess, or a message the parsers could not
/// read (then [amount] is null).
final class MessageCardModel extends ReviewCardModel {
  const MessageCardModel({
    required String itemId,
    required this.sender,
    required this.isNewSender,
    this.txnId,
    this.amount,
    this.isIncome = false,
    this.merchant,
  }) : super(itemId);
  final String sender;
  final bool isNewSender;
  final String? txnId;
  final Money? amount;
  final bool isIncome;
  final String? merchant;

  bool get unreadable => txnId == null;

  @override
  ReviewFilter get filter => ReviewFilter.messages;
}

/// "Which transfer was it?" (BR-XFR-02).
final class TransferCardModel extends ReviewCardModel {
  const TransferCardModel({
    required String itemId,
    required this.txnId,
    required this.amount,
    required this.accountLabel,
    required this.isIncomeLeg,
    required this.options,
  }) : super(itemId);
  final String txnId;
  final Money amount;
  final String accountLabel;

  /// True when the waiting leg is the money-in side.
  final bool isIncomeLeg;
  final List<ReviewTransferOption> options;

  @override
  ReviewFilter get filter => ReviewFilter.transfers;
}

/// Subscription suggestion (T-096): [recurringItemId] goes to
/// `RecurringRepository.confirm/dismiss`.
final class SubscriptionCardModel extends ReviewCardModel {
  const SubscriptionCardModel({
    required String itemId,
    required this.recurringItemId,
    required this.name,
    this.amount,
  }) : super(itemId);
  final String recurringItemId;
  final String name;
  final Money? amount;

  @override
  ReviewFilter get filter => ReviewFilter.all;
}

/// Any other suggestion (refund match, FX pair, payday...): confirm marks
/// the item accepted, dismiss removes it. [ambiguousRefund] cards can only
/// be dismissed here (the manual link lives on the transaction detail).
final class SuggestionCardModel extends ReviewCardModel {
  const SuggestionCardModel({
    required String itemId,
    required this.kind,
    required this.ambiguousRefund,
    this.amount,
    this.merchant,
    this.candidates = const [],
    this.isIncome = false,
  }) : super(itemId);
  final String kind;
  final bool ambiguousRefund;
  final Money? amount;
  final String? merchant;

  /// Pair suggestions (T-092): the expenses the user can link. Nothing is
  /// linked until the user picks one (or confirms the only one shown).
  final List<ReviewTransferOption> candidates;
  final bool isIncome;

  /// A reimbursement or FX-pair suggestion: accepted only via a candidate.
  bool get isPair =>
      !ambiguousRefund &&
      (kind == 'reimbursement_suggestion' || kind == 'fx_pair_suggestion');

  @override
  ReviewFilter get filter => ReviewFilter.all;
}
