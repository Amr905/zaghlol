// T-161 (S-32): is a transaction about to be saved from a scanned image or
// shared text probably one the app already captured from a bank message?
// Same account, direction, currency and amount, within one day (BR-ING-02
// spirit; the cross-channel +-2 minute rule cannot apply: an image has no
// receipt time). Pure; never logs.

import '../domain/transaction.dart';
import '../domain/transaction_repository.dart';

const int _dayMs = 86400000;

/// The pure match, for tests and [findDuplicate].
bool isProbableDuplicate(TransactionRecord existing, NewTransaction leg) =>
    existing.accountId == leg.accountId &&
    existing.direction == leg.direction &&
    existing.amount.currency == leg.amount.currency &&
    existing.amount.abs() == leg.amount.abs() &&
    (existing.occurredAt.millisecondsSinceEpoch -
                leg.occurredAt.millisecondsSinceEpoch)
            .abs() <=
        _dayMs;

/// The first existing transaction that [isProbableDuplicate] says is the
/// same one, or null.
Future<TransactionRecord?> findDuplicate(
  TransactionRepository repository,
  NewTransaction leg,
) async {
  final rows = await repository.query(
    filter: TransactionFilter(
      from: leg.occurredAt.subtract(const Duration(days: 1)),
      to: leg.occurredAt.add(const Duration(days: 1)),
      accountIds: {leg.accountId},
      directions: {leg.direction},
      currencies: {leg.amount.currency},
    ),
    page: const PageRequest(limit: 200),
  );
  for (final r in rows) {
    if (isProbableDuplicate(r, leg)) return r;
  }
  return null;
}
