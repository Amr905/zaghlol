// T-046: the values the ingest use case reads from and writes to the store
// port. Pure Dart; the data layer maps them to rows. Financial data: every
// toString prints a kind or an id only.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../transactions/domain/transaction.dart';

/// A stored transaction considered for a merge (dedupe 2, pending/settled).
final class TxnCandidate {
  const TxnCandidate({
    required this.id,
    required this.accountId,
    required this.source,
    required this.status,
    required this.direction,
    required this.amount,
    required this.occurredAtMs,
    required this.tzOffsetMin,
    required this.isUserVerified,
    required this.isDeleted,
    required this.categorySource,
    this.accountLast4,
    this.accountInstitution,
    this.rawReceivedAtMs,
    this.originalAmount,
    this.merchantRaw,
    this.merchantNorm,
    this.counterpartyKind,
    this.counterpartyValue,
    this.referenceNo,
    this.balanceAfterMinor,
    this.parseConfidencePermille,
  });

  final String id;
  final String accountId;

  /// The last-4 of the transaction's account (transactions have none).
  final String? accountLast4;
  final String? accountInstitution;

  /// `transactions.source` code.
  final String source;
  final TxnStatus status;
  final TxnDirection direction;
  final Money amount;
  final Money? originalAmount;
  final int occurredAtMs;
  final int tzOffsetMin;

  /// `received_at` of the transaction's own raw message, if any.
  final int? rawReceivedAtMs;
  final bool isUserVerified;
  final bool isDeleted;
  final CategorySource categorySource;
  final String? merchantRaw;
  final String? merchantNorm;
  final String? counterpartyKind;
  final String? counterpartyValue;
  final String? referenceNo;
  final int? balanceAfterMinor;
  final int? parseConfidencePermille;

  @override
  String toString() => 'TxnCandidate($id)';
}

/// A raw_messages row to insert.
final class RawInsert {
  const RawInsert({
    required this.id,
    required this.channel,
    required this.sender,
    required this.body,
    required this.bodyHash,
    required this.receivedAtMs,
    required this.parseStatus,
    required this.registryVersion,
    required this.createdAtMs,
    this.institutionCode,
    this.simSlot,
    this.templateId,
    this.templateVersion,
  });

  final String id;
  final String channel;
  final String sender;
  final String? institutionCode;

  /// Sensitive: only ever bound as a parameter.
  final String body;
  final String bodyHash;
  final int receivedAtMs;
  final int? simSlot;

  /// `parsed`, `review` or `reparse_pending`.
  final String parseStatus;
  final String? templateId;
  final int? templateVersion;
  final int registryVersion;
  final int createdAtMs;

  @override
  String toString() => 'RawInsert($parseStatus)';
}

/// A transactions row to insert.
final class TxnInsert {
  const TxnInsert({
    required this.id,
    required this.accountId,
    required this.rawMessageId,
    required this.source,
    required this.direction,
    required this.status,
    required this.amount,
    required this.occurredAtMs,
    required this.tzOffsetMin,
    required this.categorySource,
    required this.isUserVerified,
    required this.createdAtMs,
    this.originalAmount,
    this.merchantRaw,
    this.merchantNorm,
    this.catalogMerchantId,
    this.counterpartyKind,
    this.counterpartyValue,
    this.categoryId,
    this.referenceNo,
    this.balanceAfterMinor,
    this.templateId,
    this.parseConfidencePermille,
    this.dedupeKey,
  });

  final String id;
  final String accountId;
  final String rawMessageId;
  final TxnSource source;
  final TxnDirection direction;
  final TxnStatus status;
  final Money amount;
  final Money? originalAmount;
  final int occurredAtMs;
  final int tzOffsetMin;
  final String? merchantRaw;
  final String? merchantNorm;
  final int? catalogMerchantId;
  final String? counterpartyKind;
  final String? counterpartyValue;
  final String? categoryId;
  final CategorySource categorySource;
  final bool isUserVerified;
  final String? referenceNo;
  final int? balanceAfterMinor;
  final String? templateId;
  final int? parseConfidencePermille;
  final String? dedupeKey;
  final int createdAtMs;

  @override
  String toString() => 'TxnInsert($id)';
}

/// The fields a merge writes. A null field is left unchanged: a merge only
/// fills or replaces, it never clears a value.
final class TxnPatch {
  const TxnPatch({
    this.accountId,
    this.status,
    this.amount,
    this.originalAmount,
    this.merchantRaw,
    this.merchantNorm,
    this.counterpartyKind,
    this.counterpartyValue,
    this.referenceNo,
    this.balanceAfterMinor,
    this.parseConfidencePermille,
    this.categoryId,
    this.categorySource,
    this.catalogMerchantId,
    this.dedupeKey,
  });

  final String? accountId;
  final TxnStatus? status;
  final Money? amount;
  final Money? originalAmount;
  final String? merchantRaw;
  final String? merchantNorm;
  final String? counterpartyKind;
  final String? counterpartyValue;
  final String? referenceNo;
  final int? balanceAfterMinor;
  final int? parseConfidencePermille;
  final String? categoryId;
  final CategorySource? categorySource;
  final int? catalogMerchantId;
  final String? dedupeKey;

  bool get isEmpty =>
      accountId == null &&
      status == null &&
      amount == null &&
      originalAmount == null &&
      merchantRaw == null &&
      merchantNorm == null &&
      counterpartyKind == null &&
      counterpartyValue == null &&
      referenceNo == null &&
      balanceAfterMinor == null &&
      parseConfidencePermille == null &&
      categoryId == null &&
      categorySource == null &&
      catalogMerchantId == null &&
      dedupeKey == null;

  @override
  String toString() => 'TxnPatch';
}

/// One `ignore_rules` row.
final class IgnoreRuleState {
  const IgnoreRuleState(this.institutionCode, this.last4, this.channel);
  final String institutionCode;
  final String? last4;
  final String channel;

  @override
  String toString() => 'IgnoreRuleState(<redacted>)';
}

/// One `capture_senders` row.
final class CaptureSenderState {
  const CaptureSenderState({
    required this.sender,
    required this.channel,
    required this.confirmedCount,
    required this.alwaysCapture,
  });

  final String sender;
  final String channel;
  final int confirmedCount;
  final bool alwaysCapture;

  @override
  String toString() => 'CaptureSenderState(<redacted>)';
}

/// Everything step 0 reads once per batch, inside the write transaction.
final class BatchContext {
  const BatchContext({
    required this.ignoreRules,
    required this.captureSenders,
    required this.customTemplateSenders,
    this.paydayDay,
    this.language,
  });

  final List<IgnoreRuleState> ignoreRules;
  final List<CaptureSenderState> captureSenders;

  /// `(sender, channel)` of the user's custom templates.
  final List<(String, String)> customTemplateSenders;

  /// `settings.payday_day` as stored (null: unset).
  final String? paydayDay;

  /// `settings.language` as stored (null: unset).
  final String? language;

  @override
  String toString() => 'BatchContext';
}
