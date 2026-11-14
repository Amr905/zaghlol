// WIRE-2: runs a callback after a manual add commits (duplicate-charge alert,
// T-100; reimbursement suggestion, T-092). Everything else is the wrapped
// repository. The callback is best effort: its failure never fails the add.

import '../domain/transaction.dart';
import '../domain/transaction_repository.dart';

final class AlertingTransactionRepository implements TransactionRepository {
  AlertingTransactionRepository(this._inner, {required this.afterAdd});

  final TransactionRepository _inner;
  final Future<void> Function(TransactionRecord added) afterAdd;

  @override
  Future<TransactionRecord> add(NewTransaction txn) async {
    final added = await _inner.add(txn);
    try {
      await afterAdd(added);
    } on Object {
      // The transaction is stored; alerts and suggestions can wait.
    }
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
  Future<TransactionRecord> edit(String id, TransactionEdit edit) =>
      _inner.edit(id, edit);

  @override
  Future<void> softDelete(Iterable<String> ids) => _inner.softDelete(ids);

  @override
  Future<void> restore(Iterable<String> ids) => _inner.restore(ids);

  @override
  Future<int> purgeExpired() => _inner.purgeExpired();
}
