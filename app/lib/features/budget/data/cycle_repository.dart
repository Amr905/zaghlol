// T-051: cycle totals from the database (design note §3, §6). Reads the
// rows of a cycle with one range query (widened by the largest stored
// offset, then filtered by local date), the offset links by join, and runs
// the pure engine. The current cycle is always computed live and written
// through; closed cycles come from `cycle_summaries` until invalidated.
// Nothing here logs; no amounts or ids leave this file.

import 'package:drift/drift.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/cycle_summaries_dao.dart';
import '../../ingestion/domain/ingest_ports.dart' show LocalZone;
import 'payday_schedule_store.dart';

const int _dayMs = 86400000;

/// Stored offsets are within +-18 h (`occurred_tz_offset_min`).
const int _maxOffsetMs = 18 * 3600000;

class CycleRepository {
  CycleRepository(this._db, {required this._nowUtcMs, required this._zone})
    : _cache = CycleSummariesDao(_db);

  final AppDatabase _db;
  final CycleSummariesDao _cache;
  final int Function() _nowUtcMs;
  final LocalZone _zone;

  CivilDate get today => localToday(_nowUtcMs(), _zone);

  /// Totals of [cycle] per currency. [accounts]: empty is all accounts
  /// (`'*'`), one id is cached under that id, several are computed live and
  /// never cached (design note §6).
  Future<Map<Currency, CycleTotals>> totals(
    Cycle cycle, {
    Set<String> accounts = const {},
  }) async {
    final cacheable = accounts.length <= 1;
    final filter = accounts.isEmpty ? '*' : accounts.first;
    final isCurrent = cycle.contains(today) || cycle.start > today;
    if (cacheable && !isCurrent) {
      final cached = await _cached(cycle, filter);
      if (cached != null) return cached;
    }
    final live = await computeLive(cycle, accounts: accounts);
    if (cacheable) {
      await _cache.replaceCycle(
        cycleStart: cycle.key,
        accountFilter: filter,
        summaries: live.values,
        computedAt: _nowUtcMs(),
      );
    }
    return live;
  }

  /// The cached totals of [cycle] (cold start: show these first), or null.
  /// `pendingSpend` is not cached (zero here); it is only live.
  Future<Map<Currency, CycleTotals>?> cachedTotals(
    Cycle cycle, {
    String accountFilter = '*',
  }) => _cached(cycle, accountFilter);

  Future<Map<Currency, CycleTotals>?> _cached(
    Cycle cycle,
    String filter,
  ) async {
    final rows = await _cache.rowsFor(
      cycleStart: cycle.key,
      accountFilter: filter,
    );
    if (rows.isEmpty) return null;
    final out = <Currency, CycleTotals>{};
    for (final r in rows) {
      final currency = Currency.of(r.currency);
      out[currency] = CycleTotals(
        currency: currency,
        income: Money.fromStorage(r.incomeMinor, r.currency),
        spend: Money.fromStorage(r.spendMinor, r.currency),
        pendingSpend: Money.zero(currency),
        byCategoryMinor: {
          for (final e in cycleSpendByCategoryOf(r).entries)
            e.key: e.value.minor,
        },
      );
    }
    return out;
  }

  /// The live totals, never cached.
  Future<Map<Currency, CycleTotals>> computeLive(
    Cycle cycle, {
    Set<String> accounts = const {},
  }) async {
    final (txns, offsets) = await loadRows(cycle, accounts: accounts);
    return aggregateCycle(cycle, txns, offsets);
  }

  /// The rows the engine needs for [cycle] (also for the burn line).
  Future<(List<CycleTxn>, List<CycleOffset>)> loadRows(
    Cycle cycle, {
    Set<String> accounts = const {},
  }) async {
    final from = cycle.start.epochDay * _dayMs - _maxOffsetMs;
    final to = (cycle.end.epochDay + 1) * _dayMs + _maxOffsetMs;
    final ids = accounts.toList();
    final accountSql = ids.isEmpty
        ? ''
        : ' AND account_id IN (${List.filled(ids.length, '?').join(',')})';
    final rows = await _db
        .customSelect(
          'SELECT id, direction, status, amount_minor, currency, category_id, '
          'is_internal, occurred_at, occurred_tz_offset_min '
          'FROM transactions WHERE deleted_at IS NULL '
          'AND occurred_at >= ? AND occurred_at < ?$accountSql',
          variables: [
            Variable.withInt(from),
            Variable.withInt(to),
            for (final a in ids) Variable.withString(a),
          ],
          readsFrom: {_db.transactions},
        )
        .get();
    final txns = <CycleTxn>[
      for (final r in rows)
        CycleTxn(
          id: r.read<String>('id'),
          direction: _direction(r.read<String>('direction')),
          status: _status(r.read<String>('status')),
          amount: Money.fromStorage(
            r.read<int>('amount_minor'),
            r.read<String>('currency'),
          ),
          date: CivilDate.fromLocalMs(
            r.read<int>('occurred_at'),
            r.read<int>('occurred_tz_offset_min'),
          ),
          isInternal: r.read<int>('is_internal') != 0,
          categoryId: r.readNullable<String>('category_id'),
        ),
    ].where((t) => cycle.contains(t.date)).toList();

    final links = await _db
        .customSelect(
          'SELECT l.expense_txn_id AS exp, l.source_txn_id AS src, '
          'l.amount_minor AS amt, e.currency AS currency, '
          '(s.deleted_at IS NULL AND e.deleted_at IS NULL '
          "AND s.status IN ('posted', 'pending')) AS active "
          'FROM offset_links l '
          'JOIN transactions e ON e.id = l.expense_txn_id '
          'JOIN transactions s ON s.id = l.source_txn_id '
          'WHERE (e.occurred_at >= ?1 AND e.occurred_at < ?2) '
          'OR (s.occurred_at >= ?1 AND s.occurred_at < ?2)',
          variables: [Variable.withInt(from), Variable.withInt(to)],
          readsFrom: {_db.offsetLinks, _db.transactions},
        )
        .get();
    final offsets = [
      for (final r in links)
        CycleOffset(
          expenseId: r.read<String>('exp'),
          sourceId: r.read<String>('src'),
          amount: Money.fromStorage(
            r.read<int>('amt'),
            r.read<String>('currency'),
          ),
          isActive: r.read<int>('active') != 0,
        ),
    ];
    return (txns, offsets);
  }

  /// The cycle budget basis per currency (overall, else the category sum;
  /// A-16). Annual budgets are not part of this task.
  Future<Map<Currency, Money>> cycleBudgets() async {
    final rows = await (_db.select(
      _db.budgets,
    )..where((b) => b.period.equals('cycle'))).get();
    final overall = <Currency, Money>{};
    final perCategory = <Currency, List<Money>>{};
    for (final b in rows) {
      final money = Money.fromStorage(b.limitMinor, b.currency);
      if (b.categoryId == null) {
        overall[money.currency] = money;
      } else {
        (perCategory[money.currency] ??= []).add(money);
      }
    }
    final out = <Currency, Money>{};
    for (final c in {...overall.keys, ...perCategory.keys}) {
      final basis = budgetBasis(overall[c], perCategory[c] ?? const []);
      if (basis != null) out[c] = basis;
    }
    return out;
  }
}

CycleDirection _direction(String s) => switch (s) {
  'expense' => CycleDirection.expense,
  'income' => CycleDirection.income,
  'transfer_out' => CycleDirection.transferOut,
  'transfer_in' => CycleDirection.transferIn,
  'refund' => CycleDirection.refund,
  'fee' => CycleDirection.fee,
  _ => throw const FormatException('CYCLE_ROW_CORRUPT'),
};

CycleStatus _status(String s) => switch (s) {
  'posted' => CycleStatus.posted,
  'pending' => CycleStatus.pending,
  'declined' => CycleStatus.declined,
  'reversed' => CycleStatus.reversed,
  _ => throw const FormatException('CYCLE_ROW_CORRUPT'),
};
