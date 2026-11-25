// T-266: the balance line of every live account, moved out of
// NetWorthRepository (T-113/T-199) so the card-link use cases can read the
// same figures. One rule set, one place (design note T-199, T-266):
//
//   balance now = newest anchor (reported or user-entered)
//                 + the counted transactions dated strictly after it.
//
// T-266: a debit card linked to a live account that can hold cards has no
// line of its own; its transactions count on that account (one SQL over
// `account_id IN (account, its cards)`), so a card purchase lowers the account
// once. The card's own balance rows and typed balances are moved to the
// account at link time, so nothing of the card's is left to count twice.
//
// Nothing here logs; amounts and labels are financial data.

import 'package:drift/drift.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/accounts_dao.dart' show linkedCardsOf;
import '../../../core/db/daos/settings_dao.dart';
import '../../../core/settings/settings_keys.dart' as keys;

class AccountLedger {
  AccountLedger(this._db);

  final AppDatabase _db;

  /// Live (not merged) accounts, oldest first.
  Future<List<AccountRow>> liveAccounts() =>
      (_db.select(_db.accounts)
            ..where((a) => a.mergedIntoId.isNull())
            ..orderBy([
              (a) => OrderingTerm.asc(a.createdAt),
              (a) => OrderingTerm.asc(a.id),
            ]))
          .get();

  /// One line per (account, currency) pair of every live account (hidden
  /// ones count, merged ones are gone): reported row, user-entered balance,
  /// and any currency the account (or a card linked to it) has posted
  /// transactions in; an account with none of these is listed once, in its
  /// default currency. A linked card has no line (T-266).
  Future<List<BreakdownLine>> lines(DateTime now) async {
    final accounts = await liveAccounts();
    final cardsOf = linkedCardsOf(accounts);
    final linkedCards = {for (final v in cardsOf.values) ...v};
    final balances = <String, Map<String, AccountBalanceRow>>{};
    for (final b in await _db.select(_db.accountBalances).get()) {
      (balances[b.accountId] ??= {})[b.currency] = b;
    }
    final opening = keys.Settings.openingBalances.parse(
      await SettingsDao(_db).read(keys.Settings.openingBalances.name),
    );
    final txnCurrencies = <String, Set<String>>{};
    final rows = await _db
        .customSelect(
          'SELECT DISTINCT account_id, currency FROM transactions '
          "WHERE deleted_at IS NULL AND status = 'posted'",
          readsFrom: {_db.transactions},
        )
        .get();
    for (final r in rows) {
      (txnCurrencies[r.read<String>('account_id')] ??= {}).add(
        r.read<String>('currency'),
      );
    }

    final out = <BreakdownLine>[];
    for (final a in accounts) {
      if (linkedCards.contains(a.id)) continue;
      final ids = [a.id, ...?cardsOf[a.id]];
      final liability = a.kind == 'credit' || a.kind == 'bnpl';
      final currencies = <String>{
        ...?balances[a.id]?.keys,
        ...opening.forAccount(a.id).keys,
        for (final id in ids) ...?txnCurrencies[id],
      };
      // An account with nothing at all is listed in its own currency.
      if (currencies.isEmpty) currencies.add(a.defaultCurrency);
      for (final code in currencies.toList()..sort()) {
        final cur = Currency.tryOf(code);
        if (cur == null) continue;
        final row = balances[a.id]?[code];
        final user = opening.of(a.id, code);
        final limit = a.creditLimitMinor == null
            ? null
            : Money.tryFromStorage(a.creditLimitMinor!, a.defaultCurrency);
        final anchor = pickAnchor(
          currency: cur,
          isLiability: liability,
          reportedBalance: row?.balanceMinor == null
              ? null
              : Money.fromStorage(row!.balanceMinor!, code),
          reportedAvailable: row?.availableMinor == null
              ? null
              : Money.fromStorage(row!.availableMinor!, code),
          creditLimit: limit,
          reportedAsOf: row == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(row.asOf, isUtc: true),
          userBalance: user?.amount,
          userAsOf: user?.asOf,
          now: now,
        );
        final totals = anchor == null
            ? const TxnTotals()
            : await totalsAfter(ids, code, anchor.asOf);
        out.add(
          resolveAccountLine(
            accountId: a.id,
            label: a.label,
            accountKind: a.kind,
            currency: cur,
            isLiability: liability,
            now: now,
            anchor: anchor,
            totals: totals,
            institutionCode: a.institutionCode,
            last4: a.last4,
            isHidden: a.isHidden != 0,
          ),
        );
      }
    }
    return out;
  }

  /// The counted transactions of [accountIds] in [currency] strictly after
  /// [after]: live, posted, own currency; the cash-side effect by direction.
  /// Internal (paired) transfers count: they move real money between
  /// accounts.
  Future<TxnTotals> totalsAfter(
    List<String> accountIds,
    String currency,
    DateTime after,
  ) async {
    if (accountIds.isEmpty) return const TxnTotals();
    final marks = [for (var i = 0; i < accountIds.length; i++) '?${i + 3}']
        .join(', ');
    final r = await _db
        .customSelect(
          'SELECT COUNT(*) AS n, '
          "COALESCE(SUM(CASE WHEN direction IN ('income','refund','transfer_in') "
          'THEN amount_minor '
          "WHEN direction IN ('expense','fee','transfer_out') "
          'THEN -amount_minor ELSE 0 END), 0) AS eff '
          'FROM transactions WHERE currency = ?1 '
          "AND deleted_at IS NULL AND status = 'posted' AND occurred_at > ?2 "
          "AND direction IN ('income','refund','transfer_in','expense','fee','transfer_out') "
          'AND account_id IN ($marks)',
          variables: [
            Variable.withString(currency),
            Variable.withInt(after.millisecondsSinceEpoch),
            for (final id in accountIds) Variable.withString(id),
          ],
          readsFrom: {_db.transactions},
        )
        .getSingle();
    return TxnTotals(
      cashEffectMinor: r.read<int>('eff'),
      count: r.read<int>('n'),
    );
  }
}
