// T-281 (D-86, FU-365): an exchange shown as one unit in the list and the
// detail screen. Both legs keep their own amount and currency; nothing is
// converted. Pure Dart.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'transaction.dart';

/// A complete, live exchange pair (`fx_conversion` / `cross_currency`).
final class TxnExchange {
  const TxnExchange({
    required this.pairId,
    required this.kind,
    required this.sent,
    required this.received,
  });

  final String pairId;

  /// `transfer_pairs.kind`.
  final String kind;

  /// The `transfer_out` leg (the money given).
  final TransactionRecord sent;

  /// The `transfer_in` leg (the money got).
  final TransactionRecord received;

  /// Whether [txnId] is one of the two legs.
  bool has(String txnId) => sent.id == txnId || received.id == txnId;

  /// The bank's rate implied by the two amounts, quoted so it reads as 1
  /// unit of [rateBase] = rate / 1e9 units of [rateQuote], with the side
  /// that gives a rate of at least 1 (1 USD = 49.50 EGP, never
  /// 1 EGP = 0.0202 USD). Null when the amounts give no rate.
  ({int rateE9, Currency rateBase, Currency rateQuote})? get rate {
    final a = sent.amount.abs();
    final b = received.amount.abs();
    final forward = impliedRateE9(a, b);
    if (forward != null && forward >= 1000000000) {
      return (rateE9: forward, rateBase: a.currency, rateQuote: b.currency);
    }
    final back = impliedRateE9(b, a);
    if (back != null) {
      return (rateE9: back, rateBase: b.currency, rateQuote: a.currency);
    }
    if (forward != null) {
      return (rateE9: forward, rateBase: a.currency, rateQuote: b.currency);
    }
    return null;
  }
}

/// [items] with the second leg of every exchange in [exchanges] (keyed by
/// leg id) dropped, so each exchange appears once, where its first loaded
/// leg is. Order is kept.
List<TransactionRecord> collapseExchangeLegs(
  List<TransactionRecord> items,
  Map<String, TxnExchange> exchanges,
) {
  final shown = <String>{};
  final out = <TransactionRecord>[];
  for (final t in items) {
    final x = exchanges[t.id];
    if (x == null || shown.add(x.pairId)) out.add(t);
  }
  return out;
}
