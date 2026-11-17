// WIRE-2: runs a callback after a manual add commits (duplicate-charge alert,
// T-100; reimbursement suggestion, T-092). Everything else is the wrapped
// repository. The callback is best effort: its failure never fails the add.
// FIX-device-flows: [onChanged] reports the rows a manual add, edit, delete
// or restore touched (before and after), so the app can publish
// `TransactionsChanged` and Home/budgets recompute. Before, a typed or voice
// expense was saved but nothing on screen refreshed.

import '../domain/transaction.dart';
import '../domain/transaction_repository.dart';

final class AlertingTransactionRepository implements TransactionRepository {
  AlertingTransactionRepository(
    this._inner, {
    required this.afterAdd,
    this.onChanged,
    this.afterRemove,
  });

  final TransactionRepository _inner;
  final Future<void> Function(TransactionRecord added) afterAdd;

  /// Best effort, after the write committed: the rows it touched.
  final Future<void> Function(List<TransactionRecord> rows)? onChanged;

  /// FU-253: runs for every soft-deleted id after the delete committed (pair
  /// and offset links of the row are freed). One failing id never skips the
  /// others and never fails the delete.
  final Future<void> Function(String id)? afterRemove;

  Future<void> _changed(List<TransactionRecord?> rows) async {
    final cb = onChanged;
    final live = [for (final r in rows) ?r];
    if (cb == null || live.isEmpty) return;
    try {
      await cb(live);
    } on Object {
      // Stored; screens refresh on the next change or resume.
    }
  }

  Future<List<TransactionRecord?>> _read(Iterable<String> ids) async {
    if (onChanged == null) return const [];
    try {
      return [
        for (final id in ids) await _inner.byId(id, includeDeleted: true),
      ];
    } on Object {
      return const [];
    }
  }

  @override
  Future<TransactionRecord> add(NewTransaction txn) async {
    final added = await _inner.add(txn);
    try {
      await afterAdd(added);
    } on Object {
      // The transaction is stored; alerts and suggestions can wait.
    }
    await _changed([added]);
    return added;
  }

  @override
  Future<List<TransactionRecord>> query({
    TransactionFilter filter = const TransactionFilter(),
    String? text,
    PageRequest page = const PageRequest(),
  }) => _inner.query(filter: filter, text: text, page: page);

  @override
  Future<int> count({
    TransactionFilter filter = const TransactionFilter(),
    String? text,
  }) => _inner.count(filter: filter, text: text);

  @override
  Future<TransactionRecord?> byId(String id, {bool includeDeleted = false}) =>
      _inner.byId(id, includeDeleted: includeDeleted);

  @override
  Future<TransactionRecord> edit(String id, TransactionEdit edit) async {
    final before = await _read([id]);
    final after = await _inner.edit(id, edit);
    await _changed([...before, after]);
    return after;
  }

  @override
  Future<void> softDelete(Iterable<String> ids) async {
    final list = ids.toList();
    final rows = await _read(list);
    await _inner.softDelete(list);
    final hook = afterRemove;
    if (hook != null) {
      for (final id in list) {
        try {
          await hook(id);
        } on Object {
          // Deleted; the start-up sweep frees what this missed.
        }
      }
    }
    await _changed(rows);
  }

  @override
  Future<void> restore(Iterable<String> ids) async {
    final list = ids.toList();
    await _inner.restore(list);
    await _changed(await _read(list));
  }

  @override
  Future<int> purgeExpired() => _inner.purgeExpired();
}
