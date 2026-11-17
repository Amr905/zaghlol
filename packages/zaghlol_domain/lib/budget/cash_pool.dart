// CAT-cash (PO CAT-CASH): the pool of withdrawn, still unspent cash.
//
// Spending is counted when cash is withdrawn (category `cash`). A later
// payment the user made in cash is part of that cash: while the pool of the
// payment's currency covers it, its amount moves from `cash` to its own
// category without changing total spending; any part beyond the pool is new
// spending. The pool runs across periods and never mixes currencies. Pure
// integer arithmetic; no I/O.

import '../money/currency.dart';
import '../money/money.dart';

/// System category ids (`sys:<code>`) of the two PO categories.
const String kCashCategoryId = 'sys:cash';
const String kInstapayCategoryId = 'sys:instapay';

enum CashEventKind { withdrawal, payment }

/// One counted (live, posted/pending, non-internal) cash event.
final class CashEvent {
  const CashEvent({
    required this.id,
    required this.kind,
    required this.amount,
    required this.localMs,
  });

  final String id;
  final CashEventKind kind;

  /// Positive amount in its own currency.
  final Money amount;

  /// Local wall-clock instant (`occurred_at + offset`), the pool's order.
  final int localMs;
}

/// The part of each payment covered by the pool, by payment id (only
/// payments with a non-zero cover appear). Order: local time, then
/// withdrawals before payments, then id.
Map<String, Money> allocateCashPool(Iterable<CashEvent> events) {
  final sorted = events.toList()
    ..sort((a, b) {
      final t = a.localMs.compareTo(b.localMs);
      if (t != 0) return t;
      final k = a.kind.index.compareTo(b.kind.index);
      return k != 0 ? k : a.id.compareTo(b.id);
    });
  final pool = <Currency, int>{};
  final covered = <String, Money>{};
  for (final e in sorted) {
    final c = e.amount.currency;
    final have = pool[c] ?? 0;
    if (e.amount.minor <= 0) continue;
    switch (e.kind) {
      case CashEventKind.withdrawal:
        pool[c] = have + e.amount.minor;
      case CashEventKind.payment:
        final take = e.amount.minor < have ? e.amount.minor : have;
        pool[c] = have - take;
        if (take > 0) covered[e.id] = Money(c, take);
    }
  }
  return covered;
}
