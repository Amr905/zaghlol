// T-089: builds the `TransactionsChanged` for a set of rows, including the
// accounts and cycles of every transaction linked to them by an offset link
// on either side (BR-XFR-07, FU-110). Same rule as the bulk-edit event.

import 'package:drift/drift.dart' show Variable;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart';

/// The event for [rows] (account id, UTC instant, offset) and their offset
/// links. Reads only; call it inside the writing transaction so it sees the
/// committed-with state.
Future<TransactionsChanged> transactionsChangedFor(
  AppDatabase db,
  PaydaySchedule schedule,
  Iterable<({String id, String accountId, int occurredAt, int offsetMin})>
  rows, {
  bool withLinks = true,
}) async {
  final accounts = <String>{};
  final keys = <String>{};
  void add(String account, int at, int off) {
    accounts.add(account);
    keys.add(schedule.cycleOnMs(at, off).key);
  }

  for (final r in rows) {
    add(r.accountId, r.occurredAt, r.offsetMin);
    if (!withLinks) continue;
    final links = await db
        .customSelect(
          'SELECT e.account_id AS ea, e.occurred_at AS eat, '
          'e.occurred_tz_offset_min AS eoff, s.account_id AS sa, '
          's.occurred_at AS sat, s.occurred_tz_offset_min AS soff '
          'FROM offset_links l '
          'JOIN transactions e ON e.id = l.expense_txn_id '
          'JOIN transactions s ON s.id = l.source_txn_id '
          'WHERE l.expense_txn_id = ?1 OR l.source_txn_id = ?1',
          variables: [Variable.withString(r.id)],
          readsFrom: {db.offsetLinks, db.transactions},
        )
        .get();
    for (final l in links) {
      add(l.read<String>('ea'), l.read<int>('eat'), l.read<int>('eoff'));
      add(l.read<String>('sa'), l.read<int>('sat'), l.read<int>('soff'));
    }
  }
  return TransactionsChanged(accountIds: accounts, cycleKeys: keys);
}
