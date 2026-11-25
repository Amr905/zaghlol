// T-045: the port every screen and the ingest use case reach accounts
// through (architecture §4.1). Implemented in data/.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'account.dart';
import 'card_link.dart';

export 'card_link.dart';

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

  /// T-266: links the live debit card [cardId] to the live account
  /// [accountId] (kind account, wallet or multi-currency), in one
  /// transaction. The card's stored and typed balances move to the account
  /// per currency (the newer instant wins); its transactions stay on the card
  /// and count on the account from now on. A card linked elsewhere is
  /// unlinked first (see [unlinkCard]). Linking to the same account again
  /// changes nothing. Never called without the user's tap. Throws
  /// `ACC_NOT_LINKABLE` for a wrong kind or itself, `ACC_NOT_FOUND` /
  /// `ACC_MERGED` for a missing or merged account.
  Future<Account> linkCard({required String cardId, required String accountId});

  /// T-266: unlinks [cardId], in one transaction. Where the card's
  /// transactions counted on the account after its anchor, the account is
  /// re-anchored at its current figure (a typed balance as of now), so the
  /// account's balance doesn't move. History stays; the card's balance is
  /// unknown until a message or the user sets it. An unlinked card is
  /// returned unchanged.
  Future<Account> unlinkCard(String cardId);

  /// T-266: the live cards linked to [accountId], oldest first.
  Future<List<Account>> cardsLinkedTo(String accountId);

  /// T-266: the live accounts [cardId] could be linked to, best first (see
  /// [orderLinkTargets]); hidden ones left out. Empty for a card that can't
  /// be linked.
  Future<List<LinkTarget>> linkTargets(String cardId);
}
