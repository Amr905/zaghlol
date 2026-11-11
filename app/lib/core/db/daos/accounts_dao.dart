// T-017: accounts and per-currency balances (database-schema §2.1). A thin
// layer for the accounts repository (T-045): every write goes through
// guardWrite, so a refused write is a code-only DbWriteException. Nothing
// here logs.

import 'package:drift/drift.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../app_database.dart';
import 'write_errors.dart';

class AccountsDao {
  AccountsDao(this._db);

  final AppDatabase _db;

  Future<void> insert(AccountsCompanion row) =>
      guardWrite(() => _db.into(_db.accounts).insert(row));

  Future<AccountRow?> byId(String id) => (_db.select(
    _db.accounts,
  )..where((a) => a.id.equals(id))).getSingleOrNull();

  /// The default cash account (FR-ACC-03), if one exists.
  Future<AccountRow?> defaultCash() => (_db.select(
    _db.accounts,
  )..where((a) => a.isDefaultCash.equals(1))).getSingleOrNull();

  /// Writes the balance of [accountId] in [currency] (FR-ACC-06). [balance]
  /// and [available] must be in [currency] (else [CurrencyMismatch]); null
  /// stores "unknown".
  Future<void> upsertBalance({
    required String accountId,
    required Currency currency,
    required int asOf,
    Money? balance,
    Money? available,
    String? sourceTxnId,
  }) async {
    // async (T-017 review n-1): a mismatch is a failed Future, not a
    // synchronous throw.
    for (final m in [balance, available]) {
      if (m != null && m.currency != currency) {
        throw CurrencyMismatch(m.currency, currency);
      }
    }
    await guardWrite(
      () => _db
          .into(_db.accountBalances)
          .insertOnConflictUpdate(
            AccountBalancesCompanion.insert(
              accountId: accountId,
              currency: currency.code,
              balanceMinor: Value(balance?.minor),
              availableMinor: Value(available?.minor),
              asOf: asOf,
              sourceTxnId: Value(sourceTxnId),
            ),
          ),
    );
  }

  /// Every balance row of [accountId], by currency code.
  Future<List<AccountBalanceRow>> balancesOf(String accountId) =>
      (_db.select(_db.accountBalances)
            ..where((b) => b.accountId.equals(accountId))
            ..orderBy([(b) => OrderingTerm.asc(b.currency)]))
          .get();
}
