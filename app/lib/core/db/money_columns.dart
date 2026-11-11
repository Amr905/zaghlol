// T-017: rows ↔ Money (design note §4; T-012 "Serialization"). The domain's
// toStorage/fromStorage are the only conversion; this file adds the column
// pairs of the batch-A tables (T-018: batch B; T-019: batch C). Amounts are
// integer minor units end to end: no double anywhere. A corrupt stored pair (unknown code, out of range,
// half-NULL) throws [CorruptMoney], whose message never echoes free text.

import 'package:drift/drift.dart' show Value;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'schema/app_schema.dart';

/// A non-null pair.
Money moneyOf(int minor, String currency) => Money.fromStorage(minor, currency);

/// A nullable pair: both NULL is null, one NULL is [CorruptMoney].
Money? optionalMoneyOf(int? minor, String? currency) {
  if (minor == null && currency == null) return null;
  if (currency == null) {
    throw CorruptMoney('', CorruptMoneyReason.missingCurrency);
  }
  if (minor == null) {
    throw CorruptMoney(currency, CorruptMoneyReason.outOfRange);
  }
  return Money.fromStorage(minor, currency);
}

extension AccountRowMoney on AccountRow {
  /// Credit limit, in the account's default currency (FR-ACC-05).
  Money? get creditLimit => creditLimitMinor == null
      ? null
      : moneyOf(creditLimitMinor!, defaultCurrency);
}

extension AccountBalanceRowMoney on AccountBalanceRow {
  Money? get balance =>
      balanceMinor == null ? null : moneyOf(balanceMinor!, currency);
  Money? get available =>
      availableMinor == null ? null : moneyOf(availableMinor!, currency);
}

extension TransactionRowMoney on TransactionRow {
  /// The billed amount (BR-FX-03).
  Money get amount => moneyOf(amountMinor, currency);

  /// The amount in the original currency, e.g. USD on an EGP card
  /// (FR-TXN-04).
  Money? get originalAmount =>
      optionalMoneyOf(originalAmountMinor, originalCurrency);

  /// The balance the message reported, in the transaction's currency.
  Money? get balanceAfter =>
      balanceAfterMinor == null ? null : moneyOf(balanceAfterMinor!, currency);
}

extension TransactionsCompanionMoney on TransactionsCompanion {
  /// Sets `amount_minor` and `currency` from [amount].
  TransactionsCompanion withAmount(Money amount) {
    final s = amount.toStorage();
    return copyWith(amountMinor: Value(s.minor), currency: Value(s.currency));
  }

  /// Sets (or clears, with null) the original-amount pair together.
  TransactionsCompanion withOriginalAmount(Money? original) {
    final s = original?.toStorage();
    return copyWith(
      originalAmountMinor: Value(s?.minor),
      originalCurrency: Value(s?.currency),
    );
  }
}

// T-018: batch-B money columns.

extension BudgetRowMoney on BudgetRow {
  /// The budget limit, in the budget's one currency (FR-BUD-02).
  Money get limit => moneyOf(limitMinor, currency);
}

extension CycleSummaryRowMoney on CycleSummaryRow {
  Money get income => moneyOf(incomeMinor, currency);
  Money get spend => moneyOf(spendMinor, currency);
}

extension RecurringItemRowMoney on RecurringItemRow {
  Money get amount => moneyOf(amountMinor, currency);
}

extension RecurringItemsCompanionMoney on RecurringItemsCompanion {
  /// Sets `amount_minor` and `currency` from [amount].
  RecurringItemsCompanion withAmount(Money amount) {
    final s = amount.toStorage();
    return copyWith(amountMinor: Value(s.minor), currency: Value(s.currency));
  }
}

// T-019: batch-C money columns. A `unit` that is a gold symbol (XAU21_G) is
// not money (milligrams): read those rows' integers directly.

extension AssetRowMoney on AssetRow {
  /// A certificate's principal, in the asset's currency.
  Money? get principal =>
      principalMinor == null ? null : optionalMoneyOf(principalMinor, currency);

  /// The user's valuation (real estate, car, stocks), in the asset's
  /// currency.
  Money? get manualValue => manualValueMinor == null
      ? null
      : optionalMoneyOf(manualValueMinor, currency);

  /// What the user paid, in its own currency.
  Money? get purchasePrice =>
      optionalMoneyOf(purchasePriceMinor, purchaseCurrency);
}

extension PriceQuoteRowMoney on PriceQuoteRow {
  /// The price of one [PriceQuoteRow.perUnit] of the symbol.
  Money get price => moneyOf(priceMinor, currency);
}

extension NetworthSnapshotRowMoney on NetworthSnapshotRow {
  /// True when [NetworthSnapshotRow.unit] is a currency code (else a gold
  /// unit in milligrams).
  bool get isCurrencyUnit => Currency.tryOf(unit) != null;

  /// The assets total when the unit is a currency, else null.
  Money? get assetsMoney => isCurrencyUnit ? moneyOf(assetsMinor, unit) : null;

  /// The liabilities total when the unit is a currency, else null.
  Money? get liabilitiesMoney =>
      isCurrencyUnit ? moneyOf(liabilitiesMinor, unit) : null;
}

extension ZakahLedgerRowMoney on ZakahLedgerRow {
  /// True when [ZakahLedgerRow.unit] is a currency code (else a gold unit in
  /// milligrams).
  bool get isCurrencyUnit => Currency.tryOf(unit) != null;

  Money? get amount => isCurrencyUnit ? moneyOf(amountMinor, unit) : null;
  Money? get paid => isCurrencyUnit ? moneyOf(paidMinor, unit) : null;
}
