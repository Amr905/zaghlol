import '../money/currency.dart';
import '../money/money.dart';
import 'cash_pool.dart';
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
    this.isExchange = false,
    this.isDeleted = false,
    this.categoryId,
    this.cashCoveredMinor = 0,
  });

  final String id;
  final CycleDirection direction;
  final CycleStatus status;
  final bool isInternal;

  /// T-272 (D-86): a leg of a complete exchange pair (`fx_conversion` or
  /// `cross_currency`). Counts as exchanged in/out only while it is also
  /// [isInternal]; never as income or spending.
  final bool isExchange;
  final bool isDeleted;
  final Money amount;
  final String? categoryId;
  final CivilDate date;

  /// CAT-cash: the part of this cash payment the pool of withdrawn cash
  /// covers (minor units of [amount]'s currency; computed by the data layer
  /// from every period). It is not new spending and moves from the `cash`
  /// category to [categoryId].
  final int cashCoveredMinor;
}

/// A refund / reimbursement link. [isActive]: the source row is live and
/// `posted`/`pending` and the expense is live (a soft-deleted refund stops
/// reducing spend; a link to a deleted expense is inactive too).
final class CycleOffset {
  const CycleOffset({
    required this.expenseId,
    required this.sourceId,
    required this.amount,
    required this.isActive,
  });

  final String expenseId;
  final String sourceId;
  final Money amount;
  final bool isActive;
}

/// Per-currency totals of one cycle. Never mixes currencies.
final class CycleTotals {
  const CycleTotals({
    required this.currency,
    required this.income,
    required this.spend,
    required this.pendingSpend,
    required this.byCategoryMinor,
    this._exchangedIn,
    this._exchangedOut,
  });

  final Currency currency;
  final Money income;
  final Money spend;

  final Money? _exchangedIn;
  final Money? _exchangedOut;

  /// T-272 (D-86): money received in this currency by exchanging another
  /// currency (the receiving legs of exchange pairs). Not income.
  Money get exchangedIn => _exchangedIn ?? Money.zero(currency);

  /// Money of this currency given away in exchanges. Not spending.
  Money get exchangedOut => _exchangedOut ?? Money.zero(currency);

  /// The month's money in: income plus exchanged in.
  Money get moneyIn => income + exchangedIn;

  /// What is left of the month's money: money in minus spending and minus
  /// what was exchanged away. Same currency throughout.
  Money get left => moneyIn - spend - exchangedOut;

  /// A copy with the exchange figures replaced (cached cycles carry no
  /// exchange figures; the repository overlays them).
  CycleTotals withExchanges({
    required Money exchangedIn,
    required Money exchangedOut,
  }) => CycleTotals(
    currency: currency,
    income: income,
    spend: spend,
    pendingSpend: pendingSpend,
    byCategoryMinor: byCategoryMinor,
    exchangedIn: exchangedIn,
    exchangedOut: exchangedOut,
  );

  /// The part of [spend] that is `pending`.
  final Money pendingSpend;

  /// Net spend per category id, `'_none'` for uncategorized; sums to
  /// [spend] plus [coveredEarlier].
  final Map<String, int> byCategoryMinor;

  static const String noCategory = '_none';

  /// CAT-cash: cash payments covered by cash withdrawn in an EARLIER cycle.
  /// Their categories show the amount, [spend] leaves them out, and the
  /// `cash` category floors at zero here (never negative). Derived, so a
  /// cached cycle carries it too.
  Money get coveredEarlier {
    final sum = byCategoryMinor.values.fold<int>(0, (a, b) => a + b);
    return Money(currency, sum > spend.minor ? sum - spend.minor : 0);
  }
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
  _NetSpend(this.txn, this.net, this.covered);
  final CycleTxn txn;

  /// Net of offsets, before the cash cover.
  final Money net;

  /// The cash cover = min(pool, gross); zero for a non-payment.
  final Money covered;

  /// What this row adds to the cycle's spend.
  Money get counted => net - covered;
}

Map<String, Money> _linkedByExpense(Iterable<CycleOffset> offsets) {
  final m = <String, Money>{};
  for (final o in offsets) {
    if (!o.isActive) continue;
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
        _netOf(t, linked[t.id]),
  ];
}

_NetSpend _netOf(CycleTxn t, Money? linked) {
  final net = linked == null ? t.amount : t.amount - linked;
  // cover = min(pool, gross) (already so); counted = net - cover.
  final cover = t.cashCoveredMinor <= 0 ? 0 : t.cashCoveredMinor;
  return _NetSpend(t, net, Money(t.amount.currency, cover));
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
  final xIn = <Currency, Money>{};
  final xOut = <Currency, Money>{};

  void ensure(Currency c) {
    spend.putIfAbsent(c, () => Money.zero(c));
    pending.putIfAbsent(c, () => Money.zero(c));
    income.putIfAbsent(c, () => Money.zero(c));
    byCat.putIfAbsent(c, () => <String, int>{});
    xIn.putIfAbsent(c, () => Money.zero(c));
    xOut.putIfAbsent(c, () => Money.zero(c));
  }

  for (final s in _netSpend(cycle, txns, offsets)) {
    final c = s.txn.amount.currency;
    ensure(c);
    spend[c] = spend[c]! + s.counted;
    if (s.txn.status == CycleStatus.pending) {
      pending[c] = pending[c]! + s.counted;
    }
    final k = s.txn.categoryId ?? CycleTotals.noCategory;
    final m = byCat[c]!;
    m[k] = (Money(c, m[k] ?? 0) + s.net).minor;
    if (s.covered.isPositive) {
      // The covered part was counted as `cash` when withdrawn.
      m[kCashCategoryId] =
          (Money(c, m[kCashCategoryId] ?? 0) - s.covered).minor;
    }
  }

  // Cash covered by an earlier cycle's withdrawal: the Cash category never
  // goes negative (the rest is `coveredEarlier`).
  for (final m in byCat.values) {
    final cash = m[kCashCategoryId];
    if (cash != null && cash < 0) m[kCashCategoryId] = 0;
  }

  final fundedBySource = <String, Money>{};
  for (final o in offsets) {
    if (!o.isActive) continue;
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

  // T-272 (D-86): exchange legs. Internal, so never income or spending
  // above; counted here once, in their own currency.
  for (final t in txns) {
    if (!cycle.contains(t.date) || !isExchangeLeg(t)) continue;
    final c = t.amount.currency;
    ensure(c);
    if (t.direction == CycleDirection.transferIn) {
      xIn[c] = xIn[c]! + t.amount;
    } else {
      xOut[c] = xOut[c]! + t.amount;
    }
  }

  return {
    for (final c in spend.keys)
      c: CycleTotals(
        currency: c,
        income: income[c]!,
        spend: spend[c]!,
        pendingSpend: pending[c]!,
        byCategoryMinor: Map.unmodifiable(byCat[c]!),
        exchangedIn: xIn[c]!,
        exchangedOut: xOut[c]!,
      ),
  };
}

/// T-272: true when [t] counts as exchanged in or out: a live posted or
/// pending transfer leg that is internal and in a complete exchange pair.
/// Such a row never counts as income or spending (it is internal).
bool isExchangeLeg(CycleTxn t) =>
    t.isExchange &&
    t.isInternal &&
    !t.isDeleted &&
    (t.status == CycleStatus.posted || t.status == CycleStatus.pending) &&
    (t.direction == CycleDirection.transferIn ||
        t.direction == CycleDirection.transferOut);

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
    out[d] = (Money(currency, out[d] ?? 0) + s.counted).minor;
  }
  return out;
}
