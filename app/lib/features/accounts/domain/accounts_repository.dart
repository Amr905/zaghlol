// T-045: the port every screen and the ingest use case reach accounts
// through (architecture §4.1). Implemented in data/.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'account.dart';

abstract interface class AccountsRepository {
  /// Finds the account for (institution, last-4) or creates it
  /// (FR-ACC-01). A merged-away account resolves to its merge target. A
  /// hint without a last-4 resolves to the institution-only account.
  /// Concurrent callers get one account; only one sees `created = true`.
  /// Throws [AccountsException] `ACC_INVALID` for a bad institution, last-4
  /// or label.
  Future<ResolvedAccount> resolve(AccountHint hint);

  /// The default cash account (FR-ACC-03), created on first use. The first
  /// call fixes its currency and label; later calls return it unchanged.
  Future<Account> ensureDefaultCash({
    required Currency currency,
    required String label,
  });

  /// An account by id, merged or hidden ones included.
  Future<Account?> byId(String id);

  /// Live (not merged) accounts, oldest first. Hidden ones only when
  /// [includeHidden] (pickers and lists leave them out; totals do not,
  /// D-69).
  Future<List<Account>> list({bool includeHidden = false});

  /// [list] with the balance rows of each account.
  Future<List<AccountWithBalances>> listWithBalances({
    bool includeHidden = false,
  });

  /// Every balance row of an account, by currency code.
  Future<List<AccountBalance>> balancesOf(String accountId);

  /// Stores the balance and/or available amount a message stated
  /// (FR-ACC-02). The currency is the amounts' own (they must agree). An
  /// older message than the stored `as_of` changes nothing and returns
  /// false. Throws `ACC_NOT_FOUND` / `ACC_MERGED` for a missing or merged
  /// account, `ACC_INVALID` for no amount or mixed currencies.
  Future<bool> recordBalance({
    required String accountId,
    required DateTime asOf,
    Money? balance,
    Money? available,
    String? sourceTxnId,
  });

  /// The sum of stored balances per currency over live asset accounts
  /// (hidden ones included, D-69). Never summed across currencies.
  Future<Map<Currency, Money>> totalsByCurrency();

  /// Applies [edit] to a live account (rename, type, credit limit, due
  /// day) and returns it.
  Future<Account> update(String id, AccountEdit edit);

  /// Hides or unhides a live account (FR-ACC-04). Transactions still count.
  Future<Account> setHidden(String id, {required bool hidden});

  /// Merges [sourceId] into [targetId] (FR-ACC-04): re-links every
  /// transaction (soft-deleted ones too) and recurring item, moves the
  /// balances per currency, and marks the source merged. All or none.
  Future<Account> merge({required String sourceId, required String targetId});
}
