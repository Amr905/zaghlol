// T-281: reads the complete, live exchange pairs (`fx_conversion` /
// `cross_currency`) that touch a set of transactions, for the one-row list
// and the exchange detail. Read-only; nothing here logs.

import 'package:drift/drift.dart' show Variable;

import '../../../core/db/app_database.dart';
import '../domain/exchange.dart';
import '../domain/transaction_repository.dart';

/// SQLite keeps at most 999 host parameters in older builds; the list asks
/// for one page (≤ 500 ids) at a time, and bigger sets are chunked.
const int _chunk = 400;

class ExchangeReader {
  ExchangeReader(this._db, this._repo);

  final AppDatabase _db;
  final TransactionRepository _repo;

  /// The exchanges with a leg in [txnIds], keyed by **both** leg ids. A pair
  /// whose other leg is deleted, or that is not complete, is not an
  /// exchange here.
  Future<Map<String, TxnExchange>> forTransactions(
    Iterable<String> txnIds,
  ) async {
    final ids = txnIds.toSet().toList();
    final out = <String, TxnExchange>{};
    final seen = <String>{};
    for (var at = 0; at < ids.length; at += _chunk) {
      final part = ids.sublist(
        at,
        at + _chunk > ids.length ? ids.length : at + _chunk,
      );
      final marks = List.filled(part.length, '?').join(',');
      final rows = await _db
          .customSelect(
            'SELECT p.id AS id, p.kind AS kind, p.out_txn_id AS o, '
            'p.in_txn_id AS i FROM transfer_pairs p '
            'JOIN transactions o ON o.id = p.out_txn_id '
            'JOIN transactions i ON i.id = p.in_txn_id '
            "WHERE p.kind IN ('fx_conversion', 'cross_currency') "
            'AND o.deleted_at IS NULL AND i.deleted_at IS NULL '
            'AND o.is_internal = 1 AND i.is_internal = 1 '
            'AND (p.out_txn_id IN ($marks) OR p.in_txn_id IN ($marks))',
            variables: [
              for (var k = 0; k < 2; k++)
                for (final id in part) Variable.withString(id),
            ],
            readsFrom: {_db.transferPairs, _db.transactions},
          )
          .get();
      for (final r in rows) {
        final pairId = r.read<String>('id');
        if (!seen.add(pairId)) continue;
        final sent = await _repo.byId(r.read<String>('o'));
        final received = await _repo.byId(r.read<String>('i'));
        if (sent == null || received == null) continue;
        final x = TxnExchange(
          pairId: pairId,
          kind: r.read<String>('kind'),
          sent: sent,
          received: received,
        );
        out[sent.id] = x;
        out[received.id] = x;
      }
    }
    return out;
  }
}
