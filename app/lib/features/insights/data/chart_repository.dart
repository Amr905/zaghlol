// T-105: the chart query layer (FR-CHT-01/04/05/06). One SQL aggregate per
// chart, bounded by period, filtered by currency and account, and memoized
// per (chart, period, filter, currency) until `invalidate()` (wired to
// TransactionsChanged by the provider).
//
// Counting rules are the cycle engine's (T-051/T-089/T-090/T-091), restated
// in SQL so charts and Home agree to the minor unit:
// - spend = expense, fee and transfer_out rows; income = income,
//   transfer_in and refund rows; posted or pending only; soft-deleted rows
//   and internal transfers (`is_internal = 1`) never count (BR-XFR);
// - an expense counts net of its active links (refund or reimbursement
//   sources that are live and posted/pending); an income-side source counts
//   net of what it funded (a reimbursement that repays an expense is not
//   income);
// - a split's other shares are reimbursement links, so they leave the
//   user's spend as they are paid and the unpaid part stays spend.
// - a row's local day comes from its own stored offset (BR-FX-03), never
//   from the device zone at query time.
// Amounts are minor-unit integers; one query answers in one currency.
// Nothing here logs; no amounts, merchants or ids appear in errors.

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart' show merchantKey;

import '../../../core/db/app_database.dart';
import '../../../core/db/cash_cover_sql.dart';
import '../../../core/db/daos/write_errors.dart';
import '../domain/chart_models.dart';
import '../domain/chart_rules.dart';
import '../domain/overview_models.dart';

const int _dayMs = 86400000;
const int _maxOffsetMs = 18 * 3600000;

/// Local epoch day of row `t`, from its own offset.
const String _localMs = '(t.occurred_at + t.occurred_tz_offset_min * 60000)';
const String _localDay = '($_localMs / 86400000)';

/// The active offset links of expense `t`.
final String _linked =
    'coalesce((SELECT sum(l.amount_minor) '
    'FROM offset_links l JOIN transactions s ON s.id = l.source_txn_id '
    'WHERE l.expense_txn_id = t.id AND s.deleted_at IS NULL '
    "AND s.status IN ('posted', 'pending')), 0)";

/// The part of cash payment `t` its withdrawn-cash pool covers (CAT-cash),
/// = min(pool, gross amount); the net spend is net - cover (may dip below 0
/// by the linked amount, so an offset still reduces spend).
final String _cover = 'coalesce(${cashCoveredOf('t')}, 0)';

/// An expense's amount net of its active offset links, and (cash payments)
/// of the part already counted when the cash was withdrawn.
final String _netSpend = '(t.amount_minor - $_linked - $_cover)';

/// An income-side row's amount net of what it funded.
const String _netIncome =
    't.amount_minor - coalesce((SELECT sum(l.amount_minor) '
    'FROM offset_links l JOIN transactions e ON e.id = l.expense_txn_id '
    'WHERE l.source_txn_id = t.id AND e.deleted_at IS NULL), 0)';

const String _spendCond = "t.direction IN ('expense', 'fee', 'transfer_out')";
const String _incomeCond = "t.direction IN ('income', 'transfer_in', 'refund')";

final class _Sql {
  _Sql(this.where, this.args);
  final String where;
  final List<Variable> args;
}

/// The chart queries. [maxMemo] bounds the memo (oldest entries go first).
class ChartRepository {
  ChartRepository(this._db, {this.maxMemo = 128});

  final AppDatabase _db;
  final int maxMemo;
  final Map<String, Future<Object?>> _memo = {};

  /// Drops every memoized result (call on TransactionsChanged and when
  /// recurring items, accounts, budgets or snapshots change).
  void invalidate() => _memo.clear();

  int get memoSize => _memo.length;

  /// Drops the memo when categories or accounts are edited (names, buckets,
  /// archive state): those edits raise no TransactionsChanged. The caller
  /// cancels the subscription when the repository goes away.
  StreamSubscription<void> watchEdits() => _db
      .tableUpdates(
        TableUpdateQuery.onAllTables([_db.categories, _db.accounts]),
      )
      .listen((_) => invalidate());

  /// Results that read tables whose changes do not raise
  /// TransactionsChanged (budgets, recurring items, snapshots): cheap
  /// queries, never memoized, so they cannot go stale.
  static const _live = ['burn|', 'installments|', 'subs|', 'nw'];

  Future<T> _memoized<T>(String key, Future<T> Function() compute) {
    if (_live.any(key.startsWith)) return compute();
    final hit = _memo[key];
    if (hit != null) return hit.then((v) => v as T);
    final f = compute();
    if (_memo.length >= maxMemo) _memo.remove(_memo.keys.first);
    _memo[key] = f;
    unawaited(
      f.then<void>(
        (_) {},
        onError: (Object _) {
          if (identical(_memo[key], f)) _memo.remove(key);
        },
      ),
    );
    return f;
  }

  // ------------------------------------------------------------ SQL parts

  _Sql _base(ChartPeriod p, ChartFilter f) {
    final ids = f.accountIds.toList()..sort();
    return _Sql(
      't.deleted_at IS NULL AND t.currency = ? '
      'AND t.occurred_at >= ? AND t.occurred_at < ? '
      'AND $_localDay BETWEEN ? AND ?'
      '${ids.isEmpty ? '' : ' AND t.account_id IN (${List.filled(ids.length, '?').join(',')})'}',
      [
        Variable.withString(f.currency.code),
        Variable.withInt(p.from.epochDay * _dayMs - _maxOffsetMs),
        Variable.withInt((p.to.epochDay + 1) * _dayMs + _maxOffsetMs),
        Variable.withInt(p.from.epochDay),
        Variable.withInt(p.to.epochDay),
        for (final id in ids) Variable.withString(id),
      ],
    );
  }

  _Sql _spend(ChartPeriod p, ChartFilter f) {
    final b = _base(p, f);
    return _Sql(
      "${b.where} AND t.is_internal = 0 AND t.status IN ('posted', 'pending') "
      'AND $_spendCond',
      b.args,
    );
  }

  _Sql _income(ChartPeriod p, ChartFilter f) {
    final b = _base(p, f);
    return _Sql(
      "${b.where} AND t.is_internal = 0 AND t.status IN ('posted', 'pending') "
      'AND $_incomeCond',
      b.args,
    );
  }

  Future<List<QueryRow>> _select(
    String sql,
    List<Variable> args, {
    Set<ResultSetImplementation<dynamic, dynamic>>? reads,
  }) => guardRead(
    () => _db
        .customSelect(
          '$withCashCover$sql',
          variables: args,
          readsFrom: reads ?? {_db.transactions, _db.offsetLinks, _db.accounts},
        )
        .get(),
  );

  Money _m(int minor, ChartFilter f) =>
      Money.fromStorage(minor, f.currency.code);

  String _key(
    String chart,
    ChartPeriod p,
    ChartFilter f, [
    String extra = '',
  ]) => '$chart|${p.key}|${f.key}|$extra';

  // ----------------------------------------------------------- shared reads

  /// Local day of the user's first live transaction (any currency), or null.
  Future<CivilDate?> firstDataDay() => _memoized('firstDay', () async {
    final rows = await _select(
      'SELECT min($_localDay) AS d FROM transactions t '
      'WHERE t.deleted_at IS NULL',
      const [],
    );
    final d = rows.single.readNullable<int>('d');
    return d == null ? null : CivilDate.fromEpochDay(d);
  });

  /// The currencies with spend or income in [p] (sorted by code), so the UI
  /// can offer a currency switch (FR-CHT-05).
  Future<List<Currency>> currenciesWithActivity(
    ChartPeriod p, {
    Set<String> accountIds = const {},
  }) => _memoized(
    'currencies|${p.key}|${(accountIds.toList()..sort()).join(',')}',
    () async {
      final ids = accountIds.toList()..sort();
      final rows = await _select(
        'SELECT DISTINCT t.currency AS c FROM transactions t '
        'WHERE t.deleted_at IS NULL '
        // T-282: a currency only reached by an exchange still gets a chip.
        'AND (t.is_internal = 0 OR EXISTS (SELECT 1 FROM transfer_pairs tp '
        'WHERE tp.id = t.transfer_pair_id AND tp.in_txn_id IS NOT NULL '
        "AND tp.kind IN ('fx_conversion', 'cross_currency'))) "
        "AND t.status IN ('posted', 'pending') "
        'AND t.occurred_at >= ? AND t.occurred_at < ? '
        'AND $_localDay BETWEEN ? AND ?'
        '${ids.isEmpty ? '' : ' AND t.account_id IN (${List.filled(ids.length, '?').join(',')})'} '
        'ORDER BY c',
        [
          Variable.withInt(p.from.epochDay * _dayMs - _maxOffsetMs),
          Variable.withInt((p.to.epochDay + 1) * _dayMs + _maxOffsetMs),
          Variable.withInt(p.from.epochDay),
          Variable.withInt(p.to.epochDay),
          for (final id in ids) Variable.withString(id),
        ],
      );
      return [for (final r in rows) Currency.of(r.read<String>('c'))];
    },
  );

  /// Per local epoch day: (income, spend, spend row count).
  Future<Map<int, ({int income, int spend, int count})>> _daily(
    ChartPeriod p,
    ChartFilter f,
  ) => _memoized(_key('daily', p, f), () => _dailyUncached(p, f));

  Future<Map<int, ({int income, int spend, int count})>> _dailyUncached(
    ChartPeriod p,
    ChartFilter f,
  ) async {
    final s = _spend(p, f);
    final spendRows = await _select(
      'SELECT $_localDay AS d, sum($_netSpend) AS s, count(*) AS c '
      'FROM transactions t WHERE ${s.where} GROUP BY d',
      s.args,
    );
    final i = _income(p, f);
    final incomeRows = await _select(
      'SELECT $_localDay AS d, sum($_netIncome) AS s, count(*) AS c '
      'FROM transactions t WHERE ${i.where} GROUP BY d',
      i.args,
    );
    final out = <int, ({int income, int spend, int count})>{};
    for (final r in spendRows) {
      out[r.read<int>('d')] = (
        income: 0,
        spend: r.read<int>('s'),
        count: r.read<int>('c'),
      );
    }
    for (final r in incomeRows) {
      final d = r.read<int>('d');
      final prev = out[d];
      out[d] = (
        income: r.read<int>('s'),
        spend: prev?.spend ?? 0,
        count: (prev?.count ?? 0) + r.read<int>('c'),
      );
    }
    return out;
  }

  // ------------------------------------------------- Charts v2 (T-209)

  /// Net spend of each day of [p], first day first (zero for a quiet day).
  Future<List<int>> dailySpend(ChartPeriod p, ChartFilter f) async {
    final daily = await _daily(p, f);
    return [
      for (var i = 0; i < p.lengthDays; i++)
        daily[p.from.epochDay + i]?.spend ?? 0,
    ];
  }

  /// The overall cycle budget basis of [currency], or null (no budget).
  Future<Money?> overallBudget(Currency currency) => _cycleBudget(currency);

  /// The charges of active subscriptions, bills and instalments due from
  /// [today] on, up to [months] calendar months ahead, in one currency. An
  /// overdue charge is not listed. Read live (never memoized): recurring
  /// items raise no TransactionsChanged.
  Future<List<UpcomingDue>> upcomingDues(
    CivilDate today,
    ChartFilter f, {
    int months = 13,
  }) async {
    final out = <UpcomingDue>[];
    for (final kind in const ['subscription', 'installment', 'bill']) {
      for (final r in await _recurring(kind, f)) {
        final next = r.nextDueDate == null
            ? null
            : CivilDate.tryParse(r.nextDueDate!);
        if (next == null) continue;
        final dues = dueDatesInWindow(
          next: next,
          cadence: _cadence(r),
          dueDay: r.dueDay,
          days: r.cadenceDays,
          remaining: r.totalCount == null ? null : r.totalCount! - r.paidCount,
          firstYear: today.year,
          firstMonth: today.month,
          months: months,
        );
        for (final d in dues) {
          if (d.overdue || d.date < today) continue;
          out.add(
            UpcomingDue(
              itemId: r.id,
              name: r.name,
              kind: kind,
              date: d.date,
              amount: Money.fromStorage(r.amountMinor, r.currency),
            ),
          );
        }
      }
    }
    return out;
  }

  /// T-282 (D-86): per local day, the money exchanged in and out in the
  /// filter's currency: the internal legs of complete exchange pairs
  /// (`fx_conversion` / `cross_currency`), the same rule as the Home cycle
  /// totals. Never part of income or spend.
  Future<Map<int, ({int inMinor, int outMinor, int count})>> _exchangeDaily(
    ChartPeriod p,
    ChartFilter f,
  ) async {
    final b = _base(p, f);
    final rows = await _select(
      'SELECT $_localDay AS d, '
      "sum(CASE WHEN t.direction = 'transfer_in' THEN t.amount_minor ELSE 0 END) AS i, "
      "sum(CASE WHEN t.direction = 'transfer_out' THEN t.amount_minor ELSE 0 END) AS o, "
      'count(*) AS c FROM transactions t '
      "WHERE ${b.where} AND t.is_internal = 1 AND t.status IN ('posted', 'pending') "
      "AND t.direction IN ('transfer_in', 'transfer_out') "
      'AND EXISTS (SELECT 1 FROM transfer_pairs tp '
      'WHERE tp.id = t.transfer_pair_id AND tp.in_txn_id IS NOT NULL '
      "AND tp.kind IN ('fx_conversion', 'cross_currency')) "
      'GROUP BY d',
      b.args,
      reads: {_db.transactions, _db.transferPairs},
    );
    return {
      for (final r in rows)
        r.read<int>('d'): (
          inMinor: r.read<int>('i'),
          outMinor: r.read<int>('o'),
          count: r.read<int>('c'),
        ),
    };
  }

  /// T-282 (D-86): the complete exchange pairs whose out leg falls in [p]:
  /// (given, received) per pair, live legs only. The rate is implied by the
  /// two legs (what the bank applied). [accountIds] filters on the out leg.
  Future<List<({Money given, Money received})>> exchangePairs(
    ChartPeriod p, {
    Set<String> accountIds = const {},
  }) async {
    final ids = accountIds.toList()..sort();
    final rows = await _select(
      'SELECT o.currency AS oc, o.amount_minor AS om, '
      'i.currency AS ic, i.amount_minor AS im '
      'FROM transfer_pairs tp '
      'JOIN transactions o ON o.id = tp.out_txn_id '
      'JOIN transactions i ON i.id = tp.in_txn_id '
      "WHERE tp.kind IN ('fx_conversion', 'cross_currency') "
      'AND o.deleted_at IS NULL AND i.deleted_at IS NULL '
      "AND o.status IN ('posted', 'pending') "
      "AND i.status IN ('posted', 'pending') "
      'AND o.currency <> i.currency '
      'AND o.occurred_at >= ? AND o.occurred_at < ? '
      'AND (o.occurred_at + o.occurred_tz_offset_min * 60000) / 86400000 '
      'BETWEEN ? AND ?'
      '${ids.isEmpty ? '' : ' AND o.account_id IN (${List.filled(ids.length, '?').join(',')})'} '
      'ORDER BY o.occurred_at',
      [
        Variable.withInt(p.from.epochDay * _dayMs - _maxOffsetMs),
        Variable.withInt((p.to.epochDay + 1) * _dayMs + _maxOffsetMs),
        Variable.withInt(p.from.epochDay),
        Variable.withInt(p.to.epochDay),
        for (final id in ids) Variable.withString(id),
      ],
      reads: {_db.transactions, _db.transferPairs},
    );
    return [
      for (final r in rows)
        (
          given: Money.fromStorage(r.read<int>('om'), r.read<String>('oc')),
          received: Money.fromStorage(r.read<int>('im'), r.read<String>('ic')),
        ),
    ];
  }

  // ---------------------------------------------------------- 1 cash flow

  /// Income and spend per bucket (cycles or months). The buckets may be
  /// any ranges; one pair of queries covers their span.
  Future<ChartResult<List<CashFlowPoint>>> cashFlow(
    List<ChartPeriod> buckets,
    ChartFilter f,
  ) {
    if (buckets.isEmpty) throw ArgumentError('no buckets');
    final span = ChartPeriod(
      buckets.map((b) => b.from).reduce((a, b) => a < b ? a : b),
      buckets.map((b) => b.to).reduce((a, b) => a > b ? a : b),
    );
    return _memoized(
      _key('cashFlow', span, f, buckets.map((b) => b.key).join(';')),
      () async {
        final daily = await _daily(span, f);
        final xdaily = await _exchangeDaily(span, f);
        final first = await firstDataDay();
        var rows = 0;
        final points = <CashFlowPoint>[];
        for (final b in buckets) {
          var income = 0;
          var spend = 0;
          var xIn = 0;
          var xOut = 0;
          for (var d = b.from.epochDay; d <= b.to.epochDay; d++) {
            final v = daily[d];
            if (v != null) {
              income += v.income;
              spend += v.spend;
              rows += v.count;
            }
            final x = xdaily[d];
            if (x != null) {
              xIn += x.inMinor;
              xOut += x.outMinor;
              rows += x.count;
            }
          }
          points.add(
            CashFlowPoint(
              period: b,
              income: _m(income, f),
              spend: _m(spend, f),
              exchangedIn: _m(xIn, f),
              exchangedOut: _m(xOut, f),
              isPartial: first != null && first > b.from,
            ),
          );
        }
        if (rows == 0) {
          return const ChartNotEnoughData<List<CashFlowPoint>>(
            NotEnoughReason.noData,
            have: 0,
            need: 1,
          );
        }
        return ChartReady(points);
      },
    );
  }

  // ------------------------------------------------------ category sums

  Future<List<({String? id, String? bucket, int minor, int count})>>
  _byCategory(ChartPeriod p, ChartFilter f, {bool withNegative = false}) async {
    final s = _spend(p, f);
    // Spend rows, plus the cash move of a covered payment: its covered part
    // joins its own category and leaves `cash` (the total is unchanged).
    final rows = await _select(
      'SELECT m.cid AS cid, c.bucket AS bucket, sum(m.v) AS s, '
      'sum(m.n) AS n FROM ('
      'SELECT t.category_id AS cid, $_netSpend AS v, 1 AS n '
      'FROM transactions t WHERE ${s.where} '
      'UNION ALL SELECT t.category_id, $_cover, 0 FROM transactions t '
      'WHERE ${s.where} AND ${cashCoveredOf('t')} > 0 '
      "UNION ALL SELECT 'sys:cash', -$_cover, 0 FROM transactions t "
      'WHERE ${s.where} AND ${cashCoveredOf('t')} > 0'
      ') m LEFT JOIN categories c ON c.id = m.cid '
      'GROUP BY m.cid ${withNegative ? '' : 'HAVING sum(m.v) > 0'} '
      'ORDER BY s DESC, cid',
      [...s.args, ...s.args, ...s.args],
      reads: {_db.transactions, _db.offsetLinks, _db.categories, _db.accounts},
    );
    return [
      for (final r in rows)
        (
          id: r.readNullable<String>('cid'),
          bucket: r.readNullable<String>('bucket'),
          minor: r.read<int>('s'),
          count: r.read<int>('n'),
        ),
    ];
  }

  // ---------------------------------------------------- 2 category donut

  Future<ChartResult<CategoryDonut>> categoryDonut(
    ChartPeriod p,
    ChartFilter f,
  ) => _memoized(_key('donut', p, f), () async {
    final all = await _byCategory(p, f, withNegative: true);
    final rows = [
      for (final r in all)
        if (r.minor > 0) r,
    ];
    // CAT-cash: cash paid from cash withdrawn in an earlier period leaves a
    // negative Cash row here. It is shown as one note, never as a slice, and
    // is not part of the total.
    final covered = all.fold<int>(0, (a, r) => r.minor < 0 ? a - r.minor : a);
    if (rows.isEmpty) {
      return const ChartNotEnoughData<CategoryDonut>(
        NotEnoughReason.noData,
        have: 0,
        need: 1,
      );
    }
    final shares = sharesBp([for (final r in rows) r.minor]);
    final total = rows.fold<int>(0, (a, r) => a + r.minor);
    return ChartReady(
      CategoryDonut(
        total: _m(total - covered, f),
        coveredEarlier: _m(covered, f),
        slices: [
          for (var i = 0; i < rows.length; i++)
            CategorySlice(
              categoryId: rows[i].id,
              amount: _m(rows[i].minor, f),
              shareBp: shares[i],
              count: rows[i].count,
            ),
        ],
      ),
    );
  });

  // -------------------------------------------------------- 3 burn curve

  /// The budget basis of [currency]: the overall cycle budget, else the sum
  /// of the category budgets (A-16).
  Future<Money?> _cycleBudget(Currency currency) async {
    final rows =
        await (_db.select(_db.budgets)..where(
              (b) =>
                  b.period.equals('cycle') & b.currency.equals(currency.code),
            ))
            .get();
    Money? overall;
    final cats = <Money>[];
    for (final b in rows) {
      final m = Money.fromStorage(b.limitMinor, b.currency);
      if (b.categoryId == null) {
        overall = m;
      } else {
        cats.add(m);
      }
    }
    return budgetBasis(overall, cats);
  }

  /// Cumulative net spend by cycle day up to [today], the budget's even
  /// pace line and a straight-line projection (EC-23: none before
  /// [ChartThresholds.projectionMinDays] days).
  Future<ChartResult<BurnCurve>> burnCurve(
    Cycle cycle,
    CivilDate today,
    ChartFilter f,
  ) => _memoized(
    _key('burn', ChartPeriod.cycle(cycle), f, today.toIso()),
    () async {
      final elapsed = today.difference(cycle.start) + 1;
      if (elapsed < 1) {
        return const ChartNotEnoughData<BurnCurve>(
          NotEnoughReason.noData,
          have: 0,
          need: 1,
        );
      }
      final days = elapsed > cycle.length ? cycle.length : elapsed;
      final daily = await _daily(ChartPeriod.cycle(cycle), f);
      var rows = 0;
      var run = 0;
      final cumulative = <Money>[];
      for (var n = 1; n <= days; n++) {
        final v = daily[cycle.start.epochDay + n - 1];
        if (v != null) {
          run += v.spend;
          rows += v.count;
        }
        cumulative.add(_m(run, f));
      }
      if (rows == 0) {
        return const ChartNotEnoughData<BurnCurve>(
          NotEnoughReason.noData,
          have: 0,
          need: 1,
        );
      }
      return ChartReady(
        BurnCurve(
          cycle: cycle,
          elapsedDays: days,
          cumulative: cumulative,
          budget: await _cycleBudget(f.currency),
          projectedTotal: days >= ChartThresholds.projectionMinDays
              ? projectLinear(cumulative.last, days, cycle.length)
              : null,
        ),
      );
    },
  );

  // ---------------------------------------------------------- 4 50/30/20

  Future<ChartResult<FiftyThirtyTwenty>> fiftyThirtyTwenty(
    ChartPeriod p,
    ChartFilter f,
  ) => _memoized(_key('503020', p, f), () async {
    final i = _income(p, f);
    final incomeRow = await _select(
      'SELECT coalesce(sum($_netIncome), 0) AS s FROM transactions t '
      'WHERE ${i.where}',
      i.args,
    );
    final income = incomeRow.single.read<int>('s');
    if (income <= 0) {
      return const ChartNotEnoughData<FiftyThirtyTwenty>(
        NotEnoughReason.noIncome,
        have: 0,
        need: 1,
      );
    }
    var needs = 0, wants = 0, savingsSpend = 0, other = 0;
    final all = await _byCategory(p, f, withNegative: true);
    final covered = all.fold<int>(0, (a, r) => r.minor < 0 ? a - r.minor : a);
    for (final r in all.where((r) => r.minor > 0)) {
      switch (r.bucket) {
        case 'needs' || 'obligations':
          needs += r.minor;
        case 'wants':
          wants += r.minor;
        case 'savings':
          savingsSpend += r.minor;
        default:
          other += r.minor;
      }
    }
    wants = wants > covered ? wants - covered : 0;
    final spent = needs + wants + savingsSpend + other;
    final unspent = income > spent ? income - spent : 0;
    return ChartReady(
      FiftyThirtyTwenty(
        income: _m(income, f),
        needs: _m(needs, f),
        wants: _m(wants, f),
        savings: _m(savingsSpend + unspent, f),
        other: _m(other, f),
      ),
    );
  });

  // ------------------------------------------------- 5 day / hour pattern

  Future<ChartResult<DayHourPattern>> dayHourPattern(
    ChartPeriod p,
    ChartFilter f,
  ) => _memoized(_key('dayHour', p, f), () async {
    final s = _spend(p, f);
    final rows = await _select(
      'SELECT (($_localDay + 3) % 7) + 1 AS wd, '
      '(($_localMs % 86400000) / 3600000) AS hr, '
      'sum($_netSpend) AS s, count(*) AS n '
      'FROM transactions t WHERE ${s.where} GROUP BY wd, hr',
      s.args,
    );
    final wd = {for (var d = 1; d <= 7; d++) d: (s: 0, n: 0)};
    final hr = {for (var h = 0; h < 24; h++) h: (s: 0, n: 0)};
    var count = 0;
    for (final r in rows) {
      final d = r.read<int>('wd');
      final h = r.read<int>('hr');
      final amount = r.read<int>('s');
      final n = r.read<int>('n');
      wd[d] = (s: wd[d]!.s + amount, n: wd[d]!.n + n);
      hr[h] = (s: hr[h]!.s + amount, n: hr[h]!.n + n);
      count += n;
    }
    if (count < ChartThresholds.dayHourMinTransactions) {
      return ChartNotEnoughData<DayHourPattern>(
        count == 0
            ? NotEnoughReason.noData
            : NotEnoughReason.tooFewTransactions,
        have: count,
        need: ChartThresholds.dayHourMinTransactions,
      );
    }
    return ChartReady(
      DayHourPattern(
        byWeekday: {
          for (final e in wd.entries)
            e.key: DayHourCell(spend: _m(e.value.s, f), count: e.value.n),
        },
        byHour: {
          for (final e in hr.entries)
            e.key: DayHourCell(spend: _m(e.value.s, f), count: e.value.n),
        },
      ),
    );
  });

  // --------------------------------------- Ask Zaghlol point reads (T-110)

  /// SQL for "the merchant is one of [norms]" (T-343 fix B94-M2). Rows whose
  /// `merchant_norm` is NULL (manual entries, edited merchants) match by
  /// their `merchant_raw`, keyed at read time with [merchantKey], the same
  /// rule the masker's sources use for their ids.
  Future<({String sql, List<Variable> args})> _merchantMatch(
    List<String> norms,
  ) async {
    final rows = await _select(
      'SELECT DISTINCT merchant_raw AS r FROM transactions '
      'WHERE merchant_norm IS NULL AND merchant_raw IS NOT NULL',
      const [],
      reads: {_db.transactions},
    );
    final want = norms.toSet();
    final raws = [
      for (final r in rows)
        if (want.contains(merchantKey(r.read<String>('r'))))
          r.read<String>('r'),
    ];
    final marks = List.filled(norms.length, '?').join(',');
    return (
      sql: raws.isEmpty
          ? 't.merchant_norm IN ($marks)'
          : '(t.merchant_norm IN ($marks) OR (t.merchant_norm IS NULL AND '
                't.merchant_raw IN (${List.filled(raws.length, '?').join(',')})))',
      args: [
        for (final m in norms) Variable.withString(m),
        for (final r in raws) Variable.withString(r),
      ],
    );
  }

  /// Net spend at the merchants [merchantNorms] (at most 20 are used), or
  /// null when it is zero or less. One currency, memoized like the charts.
  Future<({Money amount, int count})?> merchantSpend(
    ChartPeriod p,
    ChartFilter f,
    Set<String> merchantNorms,
  ) {
    final norms = (merchantNorms.toList()..sort()).take(20).toList();
    if (norms.isEmpty) throw ArgumentError('no merchants');
    return _memoized(_key('merchSpend', p, f, norms.join(',')), () async {
      final s = _spend(p, f);
      final mm = await _merchantMatch(norms);
      final rows = await _select(
        'SELECT coalesce(sum($_netSpend), 0) AS s, count(*) AS n '
        'FROM transactions t WHERE ${s.where} AND ${mm.sql}',
        [...s.args, ...mm.args],
      );
      final sum = rows.single.read<int>('s');
      if (sum <= 0) return null;
      return (amount: _m(sum, f), count: rows.single.read<int>('n'));
    });
  }

  /// The expense with the largest net amount in [p], optionally inside one
  /// category or a set of merchants; null when there is none.
  Future<BiggestExpense?> biggestExpense(
    ChartPeriod p,
    ChartFilter f, {
    String? categoryId,
    Set<String> merchantNorms = const {},
  }) {
    final norms = (merchantNorms.toList()..sort()).take(20).toList();
    return _memoized(
      _key('biggest', p, f, '${categoryId ?? ''}|${norms.join(',')}'),
      () async {
        final s = _spend(p, f);
        final mm = norms.isEmpty ? null : await _merchantMatch(norms);
        final rows = await _select(
          'SELECT t.id AS id, ($_netSpend) AS s, '
          'coalesce(t.merchant_raw, t.merchant_norm) AS m, '
          't.category_id AS cid, $_localDay AS d '
          'FROM transactions t WHERE ${s.where} '
          '${categoryId == null ? '' : 'AND t.category_id = ? '}'
          '${mm == null ? '' : 'AND ${mm.sql} '}'
          'AND ($_netSpend) > 0 ORDER BY s DESC, t.id LIMIT 1',
          [
            ...s.args,
            if (categoryId != null) Variable.withString(categoryId),
            ...?mm?.args,
          ],
        );
        if (rows.isEmpty) return null;
        final r = rows.single;
        return BiggestExpense(
          id: r.read<String>('id'),
          amount: _m(r.read<int>('s'), f),
          merchant: r.readNullable<String>('m'),
          categoryId: r.readNullable<String>('cid'),
          date: CivilDate.fromEpochDay(r.read<int>('d')),
        );
      },
    );
  }

  // ------------------------------- Ask online-helper reads (T-342)

  /// Net spend per category id in [p] (positive sums only; uncategorized is
  /// the key `''`). One currency. The same counting as [categoryDonut].
  Future<Map<String, int>> categoryTotals(ChartPeriod p, ChartFilter f) =>
      _memoized(_key('catTotals', p, f), () async {
        final all = await _byCategory(p, f);
        return {
          for (final r in all)
            if (r.minor > 0) r.id ?? '': r.minor,
        };
      });

  /// The [limit] expenses with the largest net amount in [p], biggest first
  /// (ties by id). One currency.
  Future<List<BiggestExpense>> topExpenses(
    ChartPeriod p,
    ChartFilter f, {
    int limit = 5,
  }) {
    final n = limit < 1 ? 1 : (limit > 50 ? 50 : limit);
    return _memoized(_key('topExp', p, f, '$n'), () async {
      final s = _spend(p, f);
      final rows = await _select(
        'SELECT t.id AS id, ($_netSpend) AS s, '
        'coalesce(t.merchant_raw, t.merchant_norm) AS m, '
        't.category_id AS cid, $_localDay AS d '
        'FROM transactions t WHERE ${s.where} AND ($_netSpend) > 0 '
        'ORDER BY s DESC, t.id LIMIT ?',
        [...s.args, Variable.withInt(n)],
      );
      return [
        for (final r in rows)
          BiggestExpense(
            id: r.read<String>('id'),
            amount: _m(r.read<int>('s'), f),
            merchant: r.readNullable<String>('m'),
            categoryId: r.readNullable<String>('cid'),
            date: CivilDate.fromEpochDay(r.read<int>('d')),
          ),
      ];
    });
  }

  /// Cash withdrawn in [p] (rows in category `sys:cash`) and the part of the
  /// CAT-CASH pool no category has claimed yet. One currency.
  Future<({Money withdrawn, Money unattributed})> cashPool(
    ChartPeriod p,
    ChartFilter f,
  ) => _memoized(_key('cashPool', p, f), () async {
    final s = _spend(p, f);
    final rows = await _select(
      'SELECT coalesce(sum(t.amount_minor), 0) AS w FROM transactions t '
      "WHERE ${s.where} AND t.category_id = 'sys:cash'",
      s.args,
    );
    final withdrawn = rows.single.read<int>('w');
    final left = (await _byCategory(
      p,
      f,
    )).where((r) => r.id == 'sys:cash').fold<int>(0, (a, r) => a + r.minor);
    return (
      withdrawn: _m(withdrawn < 0 ? 0 : withdrawn, f),
      unattributed: _m(left < 0 ? 0 : (left > withdrawn ? withdrawn : left), f),
    );
  });

  /// The cycle budgets set on category [categoryId], per currency.
  Future<Map<Currency, Money>> categoryBudgets(String categoryId) async {
    final rows =
        await (_db.select(_db.budgets)..where(
              (b) => b.period.equals('cycle') & b.categoryId.equals(categoryId),
            ))
            .get();
    return {
      for (final b in rows)
        Currency.of(b.currency): Money.fromStorage(b.limitMinor, b.currency),
    };
  }

  // ------------------------------------------------------ 6 top merchants

  /// The [limit] merchants with the most net spend. Free users get
  /// [ChartThresholds.freeTopMerchants] (the caller passes it).
  Future<ChartResult<List<MerchantSpend>>> topMerchants(
    ChartPeriod p,
    ChartFilter f, {
    int limit = 10,
  }) {
    final n = limit < 1 ? 1 : (limit > 50 ? 50 : limit);
    return _memoized(_key('merchants', p, f, '$n'), () async {
      final s = _spend(p, f);
      final rows = await _select(
        'SELECT t.merchant_norm AS m, '
        'max(coalesce(t.merchant_raw, t.merchant_norm)) AS name, '
        'sum($_netSpend) AS s, count(*) AS n FROM transactions t '
        'WHERE ${s.where} AND t.merchant_norm IS NOT NULL '
        'GROUP BY t.merchant_norm HAVING sum($_netSpend) > 0 '
        'ORDER BY s DESC, m LIMIT ?',
        [...s.args, Variable.withInt(n)],
      );
      if (rows.isEmpty) {
        return const ChartNotEnoughData<List<MerchantSpend>>(
          NotEnoughReason.noData,
          have: 0,
          need: 1,
        );
      }
      return ChartReady([
        for (final r in rows)
          MerchantSpend(
            merchantNorm: r.read<String>('m'),
            name: r.read<String>('name'),
            amount: _m(r.read<int>('s'), f),
            count: r.read<int>('n'),
          ),
      ]);
    });
  }

  /// T-223: the merchants beyond the top [shown], folded into one "Other"
  /// row (same filter and currency as [topMerchants]). Null when nothing
  /// lies beyond them.
  Future<({Money amount, int count})?> otherMerchants(
    ChartPeriod p,
    ChartFilter f, {
    required int shown,
  }) {
    final n = shown < 1 ? 1 : (shown > 50 ? 50 : shown);
    return _memoized(_key('merchantsOther', p, f, '$n'), () async {
      final s = _spend(p, f);
      final rows = await _select(
        'SELECT coalesce(sum(s), 0) AS s, coalesce(sum(n), 0) AS n FROM ('
        'SELECT t.merchant_norm AS m, sum($_netSpend) AS s, count(*) AS n '
        'FROM transactions t '
        'WHERE ${s.where} AND t.merchant_norm IS NOT NULL '
        'GROUP BY t.merchant_norm HAVING sum($_netSpend) > 0 '
        'ORDER BY s DESC, m LIMIT -1 OFFSET ?)',
        [...s.args, Variable.withInt(n)],
      );
      final minor = rows.single.read<int>('s');
      if (minor <= 0) return null;
      return (amount: _m(minor, f), count: rows.single.read<int>('n'));
    });
  }

  /// T-189: net spend and expense count of [p], optionally inside one
  /// category and/or one merchant (the drill-down header). Never below zero.
  Future<({Money amount, int count})> scopedSpend(
    ChartPeriod p,
    ChartFilter f, {
    String? categoryId,
    bool includeUncategorized = false,
    String? merchantNorm,
  }) => _memoized(
    _key(
      'scoped',
      p,
      f,
      '${categoryId ?? ''}|$includeUncategorized|${merchantNorm ?? ''}',
    ),
    () async {
      final s = _spend(p, f);
      final rows = await _select(
        'SELECT coalesce(sum($_netSpend), 0) AS s, count(*) AS n '
        'FROM transactions t WHERE ${s.where} '
        '${includeUncategorized ? (categoryId == null ? 'AND t.category_id IS NULL ' : 'AND (t.category_id IS NULL OR t.category_id = ?) ') : (categoryId == null ? '' : 'AND t.category_id = ? ')}'
        '${merchantNorm == null ? '' : 'AND t.merchant_norm = ? '}',
        [
          ...s.args,
          if (categoryId != null) Variable.withString(categoryId),
          if (merchantNorm != null) Variable.withString(merchantNorm),
        ],
      );
      final sum = rows.single.read<int>('s');
      return (
        amount: _m(sum < 0 ? 0 : sum, f),
        count: rows.single.read<int>('n'),
      );
    },
  );

  // ------------------------------------------------ 7 month vs 3-cycle avg

  /// The current period's net spend so far against the mean of the earlier
  /// complete cycles over the same number of days. [priors] are the
  /// cycles before [current], newest first; a cycle counts only if the
  /// user's data starts on or before its first day (EC-23).
  Future<ChartResult<MonthVsAverage>> monthVsAverage(
    ChartPeriod current,
    List<ChartPeriod> priors,
    CivilDate today,
    ChartFilter f,
  ) => _memoized(
    _key(
      'vsAvg',
      current,
      f,
      '${today.toIso()};${priors.map((e) => e.key).join(';')}',
    ),
    () async {
      final end = today < current.to ? today : current.to;
      final elapsed = end.difference(current.from) + 1;
      if (elapsed < 1) {
        return const ChartNotEnoughData<MonthVsAverage>(
          NotEnoughReason.noData,
          have: 0,
          need: 1,
        );
      }
      final first = await firstDataDay();
      final counted = <ChartPeriod>[
        for (final c in priors)
          if (first != null && first <= c.from) c,
      ].take(ChartThresholds.averageMaxCycles).toList();
      if (counted.length < ChartThresholds.averageMinCycles) {
        return ChartNotEnoughData<MonthVsAverage>(
          NotEnoughReason.tooFewCycles,
          have: counted.length,
          need: ChartThresholds.averageMinCycles,
        );
      }
      final cur = await _byCategory(ChartPeriod(current.from, end), f);
      final sums = <String?, int>{};
      var priorTotal = 0;
      for (final c in counted) {
        final to = c.from.plusDays(elapsed - 1);
        final capped = ChartPeriod(c.from, to < c.to ? to : c.to);
        for (final r in await _byCategory(capped, f)) {
          sums[r.id] = (sums[r.id] ?? 0) + r.minor;
          priorTotal += r.minor;
        }
      }
      final n = counted.length;
      final curBy = {for (final r in cur) r.id: r.minor};
      final curTotal = cur.fold<int>(0, (a, r) => a + r.minor);
      final avgTotal = mulDivRound(priorTotal, 1, n);
      final ids = {...curBy.keys, ...sums.keys};
      final cats =
          [
            for (final id in ids)
              () {
                final c = curBy[id] ?? 0;
                final a = mulDivRound(sums[id] ?? 0, 1, n);
                return CategoryComparison(
                  categoryId: id,
                  current: _m(c, f),
                  average: _m(a, f),
                  deltaBp: deltaBp(c, a),
                );
              }(),
          ]..sort((a, b) {
            final c = b.current.minor.compareTo(a.current.minor);
            return c != 0
                ? c
                : (a.categoryId ?? '').compareTo(b.categoryId ?? '');
          });
      return ChartReady(
        MonthVsAverage(
          current: _m(curTotal, f),
          average: _m(avgTotal, f),
          deltaBp: deltaBp(curTotal, avgTotal),
          cyclesCounted: n,
          elapsedDays: elapsed,
          byCategory: cats,
        ),
      );
    },
  );

  // -------------------------------------------------- recurring items read

  Future<List<RecurringItemRow>> _recurring(String kind, ChartFilter f) async {
    final q = _db.select(_db.recurringItems)
      ..where(
        (r) =>
            r.kind.equals(kind) &
            r.status.equals('active') &
            r.currency.equals(f.currency.code),
      );
    final rows = await guardRead(q.get);
    if (f.accountIds.isEmpty) return rows;
    return [
      for (final r in rows)
        if (r.accountId != null && f.accountIds.contains(r.accountId)) r,
    ];
  }

  RecurrenceCadence _cadence(RecurringItemRow r) =>
      RecurrenceCadence.fromCode(r.cadence) ??
      (throw const FormatException('RECURRING_ROW_CORRUPT'));

  // ------------------------------------------------ 8 installment timeline

  /// What the active installments charge in each of the next [months]
  /// calendar months from [today]'s month, in one currency.
  Future<ChartResult<List<InstallmentMonth>>> installmentTimeline(
    CivilDate today,
    ChartFilter f, {
    int months = 6,
  }) => _memoized(
    _key('installments', ChartPeriod(today, today), f, '$months'),
    () async {
      final items = await _recurring('installment', f);
      final slots = [
        for (var i = 0; i < months; i++)
          (
            year: today.year + (today.month - 1 + i) ~/ 12,
            month: (today.month - 1 + i) % 12 + 1,
          ),
      ];
      final byMonth = {for (final s in slots) s: <InstallmentDue>[]};
      for (final r in items) {
        final next = r.nextDueDate == null
            ? null
            : CivilDate.tryParse(r.nextDueDate!);
        if (next == null) continue;
        final remaining = r.totalCount == null
            ? null
            : r.totalCount! - r.paidCount;
        final dues = dueDatesInWindow(
          next: next,
          cadence: _cadence(r),
          dueDay: r.dueDay,
          days: r.cadenceDays,
          remaining: remaining,
          firstYear: today.year,
          firstMonth: today.month,
          months: months,
        );
        for (final d in dues) {
          final key = d.overdue
              ? slots.first
              : (year: d.date.year, month: d.date.month);
          byMonth[key]?.add(
            InstallmentDue(
              itemId: r.id,
              name: r.name,
              date: d.date,
              amount: Money.fromStorage(r.amountMinor, r.currency),
              overdue: d.overdue,
            ),
          );
        }
      }
      final out = [
        for (final s in slots)
          InstallmentMonth(
            year: s.year,
            month: s.month,
            dues: byMonth[s]!
              ..sort((a, b) {
                final c = a.date.compareTo(b.date);
                return c != 0 ? c : a.itemId.compareTo(b.itemId);
              }),
            total: _m(
              byMonth[s]!.fold<int>(0, (a, d) => a + d.amount.minor),
              f,
            ),
          ),
      ];
      if (out.every((m) => m.dues.isEmpty)) {
        return const ChartNotEnoughData<List<InstallmentMonth>>(
          NotEnoughReason.noData,
          have: 0,
          need: 1,
        );
      }
      return ChartReady(out);
    },
  );

  // -------------------------------------------------- 9 subscriptions x12

  Future<ChartResult<SubscriptionsAnnual>> subscriptionsAnnual(
    ChartFilter f,
  ) => _memoized(
    _key('subs', ChartPeriod(CivilDate(2000, 1, 1), CivilDate(2000, 1, 1)), f),
    () async {
      final rows = await _recurring('subscription', f);
      if (rows.isEmpty) {
        return const ChartNotEnoughData<SubscriptionsAnnual>(
          NotEnoughReason.noData,
          have: 0,
          need: 1,
        );
      }
      final items =
          [
            for (final r in rows)
              SubscriptionCost(
                itemId: r.id,
                name: r.name,
                amount: Money.fromStorage(r.amountMinor, r.currency),
                annual: annualCost(
                  Money.fromStorage(r.amountMinor, r.currency),
                  _cadence(r),
                  days: r.cadenceDays,
                ),
              ),
          ]..sort((a, b) {
            final c = b.annual.minor.compareTo(a.annual.minor);
            return c != 0 ? c : a.itemId.compareTo(b.itemId);
          });
      return ChartReady(
        SubscriptionsAnnual(
          items: items,
          annualTotal: _m(items.fold<int>(0, (a, i) => a + i.annual.minor), f),
        ),
      );
    },
  );

  // ------------------------------------------------------- 10 cards split

  /// Net spend per card/account in one currency (FR-CHT-06). The account
  /// filter narrows the cards listed.
  Future<ChartResult<List<CardSpend>>> cardsSplit(
    ChartPeriod p,
    ChartFilter f,
  ) => _memoized(_key('cards', p, f), () async {
    final s = _spend(p, f);
    final rows = await _select(
      'SELECT t.account_id AS aid, a.label AS label, a.kind AS kind, '
      'sum($_netSpend) AS s, count(*) AS n FROM transactions t '
      'JOIN accounts a ON a.id = t.account_id '
      'WHERE ${s.where} GROUP BY t.account_id '
      'HAVING sum($_netSpend) > 0 ORDER BY s DESC, aid',
      s.args,
      reads: {_db.transactions, _db.offsetLinks, _db.accounts},
    );
    if (rows.isEmpty) {
      return const ChartNotEnoughData<List<CardSpend>>(
        NotEnoughReason.noData,
        have: 0,
        need: 1,
      );
    }
    final shares = sharesBp([for (final r in rows) r.read<int>('s')]);
    return ChartReady([
      for (var i = 0; i < rows.length; i++)
        CardSpend(
          accountId: rows[i].read<String>('aid'),
          label: rows[i].read<String>('label'),
          kind: rows[i].read<String>('kind'),
          spend: _m(rows[i].read<int>('s'), f),
          shareBp: shares[i],
          count: rows[i].read<int>('n'),
        ),
    ]);
  });

  // ------------------------------------------------------- 11 net worth

  /// The units that have snapshots (currency codes and gold units).
  Future<List<String>> netWorthUnits() => _memoized('nwUnits', () async {
    final rows = await guardRead(
      () => _db
          .customSelect(
            'SELECT DISTINCT unit FROM networth_snapshots ORDER BY unit',
            readsFrom: {_db.networthSnapshots},
          )
          .get(),
    );
    return [for (final r in rows) r.read<String>('unit')];
  });

  /// The snapshots of one [unit] in [p], oldest first (chart 11, A-20).
  /// Units are never combined; the account filter does not apply (a
  /// snapshot is the whole picture).
  Future<ChartResult<List<NetWorthPoint>>> netWorth(
    ChartPeriod p,
    String unit,
  ) => _memoized('nw|${p.key}|$unit', () async {
    final rows = await guardRead(
      () => _db
          .customSelect(
            'SELECT taken_on, assets_minor, liabilities_minor '
            'FROM networth_snapshots WHERE unit = ? '
            'AND taken_on >= ? AND taken_on <= ? ORDER BY taken_on',
            variables: [
              Variable.withString(unit),
              Variable.withString(p.from.toIso()),
              Variable.withString(p.to.toIso()),
            ],
            readsFrom: {_db.networthSnapshots},
          )
          .get(),
    );
    final points = <NetWorthPoint>[
      for (final r in rows)
        if (CivilDate.tryParse(r.read<String>('taken_on')) case final d?)
          NetWorthPoint(
            takenOn: d,
            unit: unit,
            assetsMinor: r.read<int>('assets_minor'),
            liabilitiesMinor: r.read<int>('liabilities_minor'),
          ),
    ];
    if (points.length < ChartThresholds.netWorthMinSnapshots) {
      return ChartNotEnoughData<List<NetWorthPoint>>(
        points.isEmpty
            ? NotEnoughReason.noData
            : NotEnoughReason.tooFewSnapshots,
        have: points.length,
        need: ChartThresholds.netWorthMinSnapshots,
        current: points.isEmpty
            ? null
            : Money.fromStorage(points.last.netMinor, unit),
      );
    }
    return ChartReady(points);
  });

  // ------------------------------------------------ 12 personal inflation

  /// The inflation index over the [ChartThresholds.inflationMonths] months
  /// ending in [asOf]'s month (see [personalInflation]). Merchants only
  /// (A category average would mix different goods).
  Future<ChartResult<List<InflationPoint>>> personalInflationIndex(
    CivilDate asOf,
    ChartFilter f,
  ) => _memoized(_key('inflation', ChartPeriod(asOf, asOf), f), () async {
    const n = ChartThresholds.inflationMonths;
    final startIdx = asOf.year * 12 + asOf.month - 1 - (n - 1);
    final from = CivilDate(startIdx ~/ 12, startIdx % 12 + 1, 1);
    final p = ChartPeriod(from, asOf);
    final b = _base(p, f);
    final rows = await _select(
      'SELECT t.merchant_norm AS m, $_localDay AS d, t.amount_minor AS a '
      'FROM transactions t WHERE ${b.where} AND t.is_internal = 0 '
      "AND t.status = 'posted' AND t.direction = 'expense' "
      'AND t.merchant_norm IS NOT NULL AND t.amount_minor > 0',
      b.args,
    );
    final points = <PricePoint>[];
    final merchants = <String>{};
    for (final r in rows) {
      final day = CivilDate.fromEpochDay(r.read<int>('d'));
      final m = r.read<String>('m');
      merchants.add(m);
      points.add(
        PricePoint(m, day.year * 12 + day.month - 1, r.read<int>('a')),
      );
    }
    final out = personalInflation(points);
    if (out.isEmpty) {
      return ChartNotEnoughData<List<InflationPoint>>(
        merchants.isEmpty
            ? NotEnoughReason.noData
            : NotEnoughReason.tooFewMerchants,
        have: merchants.length,
        need: ChartThresholds.inflationMinMerchants,
      );
    }
    return ChartReady(out);
  });
}
