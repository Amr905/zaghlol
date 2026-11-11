import '../money/currency.dart';
import '../money/money.dart';
import 'civil_date.dart';
import 'payday_schedule.dart';

enum CycleDirection { expense, income, transferOut, transferIn, refund, fee }

enum CycleStatus { posted, pending, declined, reversed }

/// The part of a transaction the cycle engine reads (design note §1). The
/// amount is the billed amount in its own currency (BR-FX-03); [date] is the
/// local civil date from the row's own offset.
final class CycleTxn {
  const CycleTxn({
    required this.id,
    required this.direction,
    required this.status,
    required this.amount,
    required this.date,
    this.isInternal = false,
    this.isDeleted = false,
    this.categoryId,
  });

  final String id;
  final CycleDirection direction;
  final CycleStatus status;
  final bool isInternal;
  final bool isDeleted;
  final Money amount;
  final String? categoryId;
  final CivilDate date;
}

/// A refund / reimbursement link. [sourceValid]: the source row is live and
/// `posted`/`pending` (a soft-deleted refund stops reducing spend).
final class CycleOffset {
  const CycleOffset({
    required this.expenseId,
    required this.sourceId,
    required this.amount,
    required this.sourceValid,
  });

  final String expenseId;
  final String sourceId;
  final Money amount;
  final bool sourceValid;
}

/// Per-currency totals of one cycle. Never mixes currencies.
final class CycleTotals {
  const CycleTotals({
    required this.currency,
    required this.income,
    required this.spend,
    required this.pendingSpend,
    required this.byCategoryMinor,
  });

  final Currency currency;
  final Money income;
  final Money spend;

  /// The part of [spend] that is `pending`.
  final Money pendingSpend;

  /// Net spend per category id, `'_none'` for uncategorized; sums to
  /// [spend].
  final Map<String, int> byCategoryMinor;

  static const String noCategory = '_none';
}

const Set<CycleDirection> _spendDirections = {
  CycleDirection.expense,
  CycleDirection.fee,
  CycleDirection.transferOut,
};
const Set<CycleDirection> _incomeDirections = {
  CycleDirection.income,
  CycleDirection.transferIn,
  CycleDirection.refund,
};

bool _counts(CycleTxn t) =>
    !t.isDeleted &&
    !t.isInternal &&
    (t.status == CycleStatus.posted || t.status == CycleStatus.pending);

/// A spend row with its net amount (offsets deducted).
final class _NetSpend {
  _NetSpend(this.txn, this.net);
  final CycleTxn txn;
  final Money net;
}

Map<String, Money> _linkedByExpense(Iterable<CycleOffset> offsets) {
  final m = <String, Money>{};
  for (final o in offsets) {
    if (!o.sourceValid) continue;
    final prev = m[o.expenseId];
    m[o.expenseId] = prev == null ? o.amount : prev + o.amount;
  }
  return m;
}

List<_NetSpend> _netSpend(
  Cycle cycle,
  Iterable<CycleTxn> txns,
  Iterable<CycleOffset> offsets,
) {
  final linked = _linkedByExpense(offsets);
  return [
    for (final t in txns)
      if (cycle.contains(t.date) &&
          _counts(t) &&
          _spendDirections.contains(t.direction))
        _NetSpend(
          t,
          linked[t.id] == null ? t.amount : t.amount - linked[t.id]!,
        ),
  ];
}

/// Totals of [cycle] per billed currency (design note §3). [txns] may
/// contain rows outside the cycle (ignored). [offsets] must include every link
/// whose expense or source is a row of the cycle.
Map<Currency, CycleTotals> aggregateCycle(
  Cycle cycle,
  Iterable<CycleTxn> txns,
  Iterable<CycleOffset> offsets,
) {
  final spend = <Currency, Money>{};
  final pending = <Currency, Money>{};
  final income = <Currency, Money>{};
  final byCat = <Currency, Map<String, int>>{};

  void ensure(Currency c) {
    spend.putIfAbsent(c, () => Money.zero(c));
    pending.putIfAbsent(c, () => Money.zero(c));
    income.putIfAbsent(c, () => Money.zero(c));
    byCat.putIfAbsent(c, () => <String, int>{});
  }

  for (final s in _netSpend(cycle, txns, offsets)) {
    final c = s.txn.amount.currency;
    ensure(c);
    spend[c] = spend[c]! + s.net;
    if (s.txn.status == CycleStatus.pending) {
      pending[c] = pending[c]! + s.net;
    }
    final k = s.txn.categoryId ?? CycleTotals.noCategory;
    final m = byCat[c]!;
    m[k] = (Money(c, m[k] ?? 0) + s.net).minor;
  }

  final fundedBySource = <String, Money>{};
  for (final o in offsets) {
    if (!o.sourceValid) continue;
    final prev = fundedBySource[o.sourceId];
    fundedBySource[o.sourceId] = prev == null ? o.amount : prev + o.amount;
  }
  for (final t in txns) {
    if (!cycle.contains(t.date) ||
        !_counts(t) ||
        !_incomeDirections.contains(t.direction)) {
      continue;
    }
    final c = t.amount.currency;
    ensure(c);
    final funded = fundedBySource[t.id];
    income[c] = income[c]! + (funded == null ? t.amount : t.amount - funded);
  }

  return {
    for (final c in spend.keys)
      c: CycleTotals(
        currency: c,
        income: income[c]!,
        spend: spend[c]!,
        pendingSpend: pending[c]!,
        byCategoryMinor: Map.unmodifiable(byCat[c]!),
      ),
  };
}

/// Net spend of [currency] per 1-based cycle day (offsets restated on the
/// expense's own day, BR-XFR-07).
Map<int, int> netSpendByDay(
  Cycle cycle,
  Iterable<CycleTxn> txns,
  Iterable<CycleOffset> offsets,
  Currency currency,
) {
  final out = <int, int>{};
  for (final s in _netSpend(cycle, txns, offsets)) {
    if (s.txn.amount.currency != currency) continue;
    final d = cycle.dayNumber(s.txn.date);
    out[d] = (Money(currency, out[d] ?? 0) + s.net).minor;
  }
  return out;
}
