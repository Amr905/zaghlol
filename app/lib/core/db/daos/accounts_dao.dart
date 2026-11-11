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

  /// Every row for (institution, last-4), live rows first, then merged
  /// ones. A null [last4] matches the institution-only rows.
  Future<List<AccountRow>> byInstitutionLast4(
    String institution,
    String? last4,
  ) => guardRead(
    () =>
        (_db.select(_db.accounts)
              ..where(
                (a) =>
                    a.institutionCode.equals(institution) &
                    (last4 == null ? a.last4.isNull() : a.last4.equals(last4)),
              )
              ..orderBy([
                (a) => OrderingTerm.asc(a.mergedIntoId.isNotNull()),
                (a) => OrderingTerm.asc(a.createdAt),
                (a) => OrderingTerm.asc(a.id),
              ]))
            .get(),
  );

  /// Live (not merged) accounts, oldest first.
  Future<List<AccountRow>> listLive({required bool includeHidden}) => guardRead(
    () =>
        (_db.select(_db.accounts)
              ..where(
                (a) =>
                    a.mergedIntoId.isNull() &
                    (includeHidden
                        ? const Constant(true)
                        : a.isHidden.equals(0)),
              )
              ..orderBy([
                (a) => OrderingTerm.asc(a.createdAt),
                (a) => OrderingTerm.asc(a.id),
              ]))
            .get(),
  );

  /// The balance rows of every live account.
  Future<List<AccountBalanceRow>> balancesOfLive() => guardRead(
    () => _db
        .customSelect(
          'SELECT b.* FROM account_balances b '
          'JOIN accounts a ON a.id = b.account_id '
          'WHERE a.merged_into_id IS NULL '
          'ORDER BY b.account_id, b.currency',
          readsFrom: {_db.accounts, _db.accountBalances},
        )
        .map((r) => _db.accountBalances.map(r.data))
        .get(),
  );

  /// Writes the present fields of [row]. Returns the rows changed (0 or 1).
  Future<int> updateById(String id, AccountsCompanion row) => guardWrite(
    () => (_db.update(_db.accounts)..where((a) => a.id.equals(id))).write(row),
  );

  /// Runs [body] in one database transaction (all or none).
  Future<T> inTransaction<T>(Future<T> Function() body) =>
      guardWrite(() => _db.transaction(body));

  /// Stores the balance row unless it holds a newer `as_of`, in one
  /// statement (no read-then-write race between two writers), and only for
  /// a live (not merged) account. Returns true when a row was inserted or
  /// replaced. [balance] and [available] are in [currency]. An equal
  /// `as_of` replaces.
  Future<bool> upsertBalanceIfNotOlder({
    required String accountId,
    required Currency currency,
    required int asOf,
    Money? balance,
    Money? available,
    String? sourceTxnId,
  }) async {
    for (final m in [balance, available]) {
      if (m != null && m.currency != currency) {
        throw CurrencyMismatch(m.currency, currency);
      }
    }
    return guardWrite(() async {
      final changed = await _db.customUpdate(
        'INSERT INTO account_balances '
        '(account_id, currency, balance_minor, available_minor, as_of, '
        'source_txn_id) '
        'SELECT ?1, ?2, ?3, ?4, ?5, ?6 '
        'WHERE EXISTS (SELECT 1 FROM accounts '
        'WHERE id = ?1 AND merged_into_id IS NULL) '
        'ON CONFLICT (account_id, currency) DO UPDATE SET '
        'balance_minor = excluded.balance_minor, '
        'available_minor = excluded.available_minor, '
        'as_of = excluded.as_of, '
        'source_txn_id = excluded.source_txn_id '
        'WHERE excluded.as_of >= account_balances.as_of',
        variables: [
          Variable.withString(accountId),
          Variable.withString(currency.code),
          Variable<int>(balance?.minor),
          Variable<int>(available?.minor),
          Variable.withInt(asOf),
          Variable<String>(sourceTxnId),
        ],
        updates: {_db.accountBalances},
        updateKind: UpdateKind.insert,
      );
      return changed == 1;
    });
  }

  Future<AccountBalanceRow?> balanceOf(String accountId, String currency) =>
      (_db.select(_db.accountBalances)..where(
            (b) => b.accountId.equals(accountId) & b.currency.equals(currency),
          ))
          .getSingleOrNull();

  Future<int> deleteBalance(String accountId, String currency) => guardWrite(
    () =>
        (_db.delete(_db.accountBalances)..where(
              (b) =>
                  b.accountId.equals(accountId) & b.currency.equals(currency),
            ))
            .go(),
  );

  /// Moves a balance row to [toAccountId]; the target must have no row for
  /// that currency.
  Future<int> moveBalance(
    String fromAccountId,
    String toAccountId,
    String currency,
  ) => guardWrite(
    () =>
        (_db.update(_db.accountBalances)..where(
              (b) =>
                  b.accountId.equals(fromAccountId) &
                  b.currency.equals(currency),
            ))
            .write(AccountBalancesCompanion(accountId: Value(toAccountId))),
  );

  /// Re-links every transaction of [from] (soft-deleted ones included) to
  /// [to]. Returns the number moved.
  Future<int> relinkTransactions(String from, String to, {required int at}) =>
      guardWrite(
        () =>
            (_db.update(
              _db.transactions,
            )..where((t) => t.accountId.equals(from))).write(
              TransactionsCompanion(accountId: Value(to), updatedAt: Value(at)),
            ),
      );

  /// Re-links the recurring items of [from] to [to].
  Future<int> relinkRecurring(String from, String to) => guardWrite(
    () =>
        (_db.update(_db.recurringItems)..where((r) => r.accountId.equals(from)))
            .write(RecurringItemsCompanion(accountId: Value(to))),
  );

  /// Points accounts merged into [from] at [to] (chains stay one hop).
  Future<int> repointMerged(String from, String to, {required int at}) =>
      guardWrite(
        () =>
            (_db.update(
              _db.accounts,
            )..where((a) => a.mergedIntoId.equals(from))).write(
              AccountsCompanion(mergedIntoId: Value(to), updatedAt: Value(at)),
            ),
      );
}
