// T-051: when `cycle_summaries` rows are dropped (design note §6). The
// cache holds no budget values, so budget changes never reach this class.
// Nothing here logs.

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/cycle_summaries_dao.dart';

class CycleCacheInvalidator {
  CycleCacheInvalidator(this._db) : _cache = CycleSummariesDao(_db);

  final AppDatabase _db;
  final CycleSummariesDao _cache;

  /// `TransactionsChanged`: the listed cycles, every account filter.
  Future<int> onTransactionsChanged(TransactionsChanged e) =>
      e.cycleKeys.isEmpty ? Future.value(0) : _cache.deleteCycles(e.cycleKeys);

  /// Subscribes to the events; a failed delete is not swallowed silently:
  /// it goes to the zone like any listener error.
  StreamSubscription<TransactionsChanged> attach(
    Stream<TransactionsChanged> events,
  ) => events.listen(onTransactionsChanged);

  /// A payday, primary-currency, restore or migration change: all rows.
  Future<int> invalidateAll() => _cache.clear();

  /// App resume: drops every cycle that holds a transaction with
  /// `updated_at` later than [lastForegroundMs] (edits, deletes and the
  /// headless engine's writes) or a link created after it, on either side of
  /// the link (BR-XFR-07). Full scan, no new index (design note §6).
  Future<int> sweepSince(int lastForegroundMs, PaydaySchedule schedule) async {
    final keys = <String>{};
    void add(Iterable<QueryRow> rows, String at, String off) {
      for (final r in rows) {
        keys.add(schedule.cycleOnMs(r.read<int>(at), r.read<int>(off)).key);
      }
    }

    final since = Variable.withInt(lastForegroundMs);
    add(
      await _db
          .customSelect(
            'SELECT occurred_at AS at, occurred_tz_offset_min AS off '
            'FROM transactions WHERE updated_at > ?',
            variables: [since],
            readsFrom: {_db.transactions},
          )
          .get(),
      'at',
      'off',
    );
    final links = await _db
        .customSelect(
          'SELECT e.occurred_at AS eat, e.occurred_tz_offset_min AS eoff, '
          's.occurred_at AS sat, s.occurred_tz_offset_min AS soff '
          'FROM offset_links l '
          'JOIN transactions e ON e.id = l.expense_txn_id '
          'JOIN transactions s ON s.id = l.source_txn_id '
          'WHERE l.created_at > ?',
          variables: [since],
          readsFrom: {_db.offsetLinks, _db.transactions},
        )
        .get();
    add(links, 'eat', 'eoff');
    add(links, 'sat', 'soff');
    return keys.isEmpty ? 0 : _cache.deleteCycles(keys);
  }
}
