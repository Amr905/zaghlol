// SMS-fuzzy (PO 2026-11-16): the fields of a generic suggestion as stored in
// its review item's payload (written by ingest, read by the review card and
// the one-tap confirm). Fields only; the message text is never in a payload.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../transactions/domain/transaction.dart';

final class GenericSuggestion {
  const GenericSuggestion({
    required this.amount,
    required this.occurredAtMs,
    required this.tzOffsetMin,
    this.direction,
    this.merchant,
    this.merchantKey,
    this.last4,
    this.institutionCode,
    this.source,
    this.prefillComplete = false,
  });

  final Money amount;
  final TxnDirection? direction;
  final String? merchant;
  final String? merchantKey;
  final String? last4;

  /// The known bank the sender resolved to (FU-243); null for an unknown
  /// sender.
  final String? institutionCode;

  /// Stored `transactions.source` code of the message's channel.
  final String? source;
  final int occurredAtMs;
  final int tzOffsetMin;

  /// The parser's [ParseGeneric.prefillComplete].
  final bool prefillComplete;

  bool get isIncome =>
      direction == TxnDirection.income ||
      direction == TxnDirection.transferIn ||
      direction == TxnDirection.refund;

  /// One tap saves it as read: a known bank, every field read, and a
  /// channel to record. Anything less opens the editor (FR-PAR-13: the user
  /// still decides; nothing is saved without the tap).
  bool get oneTap =>
      prefillComplete &&
      direction != null &&
      institutionCode != null &&
      source != null &&
      amount.isPositive;

  /// Null unless [payload] is a generic item with a readable amount.
  static GenericSuggestion? fromPayload(Map<String, Object?> payload) {
    if (payload['generic'] != true) return null;
    try {
      final rawAmount = payload['amount'];
      if (rawAmount is! Map) return null;
      final amount = Money.fromJson(rawAmount.cast<String, Object?>());
      if (!amount.isPositive) return null;
      final dir = payload['direction'];
      final when = payload['occurredAtMs'];
      final tz = payload['tzOffsetMin'];
      return GenericSuggestion(
        amount: amount,
        direction: dir is String ? TxnDirection.fromCode(dir) : null,
        merchant: _text(payload['merchant']),
        merchantKey: _text(payload['merchantKey']),
        last4: _last4(payload['last4']),
        institutionCode: _text(payload['institutionCode']),
        source: _source(payload['source']),
        occurredAtMs: when is int ? when : 0,
        tzOffsetMin: tz is int ? tz : 0,
        prefillComplete:
            payload['prefillComplete'] == true && when is int && tz is int,
      );
    } on Object {
      return null;
    }
  }

  static String? _text(Object? v) =>
      v is String && v.trim().isNotEmpty ? v : null;

  static String? _last4(Object? v) =>
      v is String && RegExp(r'^[0-9]{4}$').hasMatch(v) ? v : null;

  static String? _source(Object? v) {
    if (v is! String) return null;
    for (final s in TxnSource.values) {
      if (s.code == v) return v;
    }
    return null;
  }
}
