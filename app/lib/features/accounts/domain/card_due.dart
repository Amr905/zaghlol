// T-245 (D-83): the latest due notice of one credit card, and the pure rules
// that merge a newer notice and count payments against it. No Flutter, no
// Drift. Amounts are integer minor units of [currency]; dates are civil.

import 'dart:convert';

import 'package:zaghlol_domain/zaghlol_domain.dart';

/// The settings key of the due of one card (`card_due.cib.1234`). The
/// institution code is reduced to `[a-z0-9_]`; the last-4 is digits only.
String cardDueKey(String institutionCode, String last4) {
  final inst = institutionCode.toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9_]'),
    '_',
  );
  final cut = inst.length > 40 ? inst.substring(0, 40) : inst;
  return 'card_due.$cut.$last4';
}

/// The most txn ids kept for "counted once" (a card pays a few times a cycle).
const int cardDueMaxPaidTxns = 12;

final class CardDue {
  const CardDue({
    required this.currency,
    required this.noticeAtMs,
    this.amountDueMinor,
    this.minDueMinor,
    this.dueDate,
    this.statementDate,
    this.paidMinor = 0,
    this.paidTxnIds = const [],
    this.applied = false,
  });

  /// ISO 4217 code of every amount here.
  final String currency;

  /// When the notice was received (UTC epoch ms): the order of notices.
  final int noticeAtMs;
  final int? amountDueMinor;
  final int? minDueMinor;
  final CivilDate? dueDate;
  final CivilDate? statementDate;

  /// Payments counted since the statement.
  final int paidMinor;
  final List<String> paidTxnIds;

  /// True once the dues layer wrote it to the card's reminder.
  final bool applied;

  /// What must be paid to settle it: the minimum, else the total. Null when
  /// the notice carried neither (never paid on doubt).
  int? get threshold => minDueMinor ?? amountDueMinor;

  bool get isPaid {
    final t = threshold;
    return t != null && t > 0 && paidMinor >= t;
  }

  /// The rest of the minimum, or null when paid or unknown.
  int? get remainingMinor {
    final t = threshold;
    if (t == null || isPaid) return null;
    return t - paidMinor;
  }

  CardDue copyWith({int? paidMinor, List<String>? paidTxnIds, bool? applied}) =>
      CardDue(
        currency: currency,
        noticeAtMs: noticeAtMs,
        amountDueMinor: amountDueMinor,
        minDueMinor: minDueMinor,
        dueDate: dueDate,
        statementDate: statementDate,
        paidMinor: paidMinor ?? this.paidMinor,
        paidTxnIds: paidTxnIds ?? this.paidTxnIds,
        applied: applied ?? this.applied,
      );

  String encode() => jsonEncode({
    'v': 1,
    'cur': currency,
    'at': noticeAtMs,
    'amt': ?amountDueMinor,
    'min': ?minDueMinor,
    'due': ?dueDate?.toIso(),
    'stmt': ?statementDate?.toIso(),
    'paid': paidMinor,
    'txns': paidTxnIds,
    'applied': applied,
  });

  /// Null for anything that is not a well-formed due (never throws).
  static CardDue? decode(String? text) {
    if (text == null) return null;
    try {
      final m = jsonDecode(text);
      if (m is! Map<String, dynamic> || m['v'] != 1) return null;
      final cur = m['cur'];
      final at = m['at'];
      if (cur is! String || !RegExp(r'^[A-Z]{3}$').hasMatch(cur)) return null;
      if (at is! int) return null;
      int? nonNeg(Object? v) => v is int && v >= 0 ? v : null;
      CivilDate? date(Object? v) => v is String ? CivilDate.tryParse(v) : null;
      final txns = m['txns'];
      return CardDue(
        currency: cur,
        noticeAtMs: at,
        amountDueMinor: nonNeg(m['amt']),
        minDueMinor: nonNeg(m['min']),
        dueDate: date(m['due']),
        statementDate: date(m['stmt']),
        paidMinor: nonNeg(m['paid']) ?? 0,
        paidTxnIds: txns is List ? txns.whereType<String>().toList() : const [],
        applied: m['applied'] == true,
      );
    } on Object {
      return null;
    }
  }
}

/// Merges a notice into what is stored. Returns null when [incoming] must
/// not replace [existing]: it is not newer (an older or equal notice never
/// overwrites). A newer notice for the same due date keeps the fields it does
/// not carry (a reminder after a statement keeps the minimum) and the
/// payments already counted; a newer notice for another due date starts clean.
CardDue? mergeNotice(CardDue? existing, CardDue incoming) {
  if (existing == null) return incoming;
  if (incoming.noticeAtMs <= existing.noticeAtMs) return null;
  if (existing.currency != incoming.currency) return incoming;
  final same = incoming.dueDate != null && incoming.dueDate == existing.dueDate;
  if (!same) return incoming;
  return CardDue(
    currency: incoming.currency,
    noticeAtMs: incoming.noticeAtMs,
    amountDueMinor: incoming.amountDueMinor ?? existing.amountDueMinor,
    minDueMinor: incoming.minDueMinor ?? existing.minDueMinor,
    dueDate: incoming.dueDate,
    statementDate: incoming.statementDate ?? existing.statementDate,
    paidMinor: existing.paidMinor,
    paidTxnIds: existing.paidTxnIds,
    applied: false,
  );
}

/// Counts a payment of [amountMinor] in [currency] made on [paidOn] (the
/// transaction's local date). Returns null when it does not count: another
/// currency, before the statement date (the notice date when the statement
/// date is unknown), zero, already counted or the due is already paid. The
/// counted payment may leave the due unpaid ([CardDue.isPaid]).
CardDue? applyPayment(
  CardDue due, {
  required String txnId,
  required int amountMinor,
  required String currency,
  required CivilDate paidOn,
  required CivilDate noticeDay,
}) {
  if (amountMinor <= 0 || currency != due.currency) return null;
  if (due.isPaid || due.paidTxnIds.contains(txnId)) return null;
  final from = due.statementDate ?? noticeDay;
  if (paidOn < from) return null;
  final ids = [...due.paidTxnIds, txnId];
  return due.copyWith(
    paidMinor: due.paidMinor + amountMinor,
    paidTxnIds: ids.length > cardDueMaxPaidTxns
        ? ids.sublist(ids.length - cardDueMaxPaidTxns)
        : ids,
  );
}
