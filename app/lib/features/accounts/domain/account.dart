// T-045: the account entity and its value types (pure Dart; no Flutter, no
// Drift). Amounts are [Money]; times are UTC instants. Nothing here is ever
// logged: labels, last-4 digits and balances are financial data.

import 'package:zaghlol_domain/zaghlol_domain.dart';

/// The account type (FR-ACC-01). [code] is the stored value.
enum AccountKind {
  debit('debit'),
  credit('credit'),
  account('account'),
  wallet('wallet'),
  bnpl('bnpl'),
  cash('cash'),
  multiCurrency('multi_currency');

  const AccountKind(this.code);
  final String code;

  /// Whether the stored "balance" is money the user holds. Credit and BNPL
  /// balances are a debt or a limit, so they stay out of asset totals.
  bool get isAsset => this != credit && this != bnpl;

  static AccountKind fromCode(String code) => values.firstWhere(
    (v) => v.code == code,
    orElse: () => throw AccountsException(AccountsException.corruptRow),
  );
}

/// A stored account.
final class Account {
  const Account({
    required this.id,
    required this.kind,
    required this.label,
    required this.defaultCurrency,
    required this.isHidden,
    required this.isDefaultCash,
    required this.createdAt,
    required this.updatedAt,
    this.institutionCode,
    this.last4,
    this.creditLimit,
    this.statementDueDay,
    this.mergedIntoId,
  });

  final String id;
  final AccountKind kind;
  final String label;
  final String? institutionCode;
  final String? last4;

  /// The billing currency of the card or account.
  final Currency defaultCurrency;

  /// In [defaultCurrency] (FR-ACC-05).
  final Money? creditLimit;
  final int? statementDueDay;

  /// Hidden accounts leave lists and pickers only; their transactions still
  /// count in totals, budgets and charts (D-69).
  final bool isHidden;

  /// Set when this account was merged into another (FR-ACC-04).
  final String? mergedIntoId;
  final bool isDefaultCash;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isMerged => mergedIntoId != null;
}

/// The balance of one account in one currency (FR-ACC-02, FR-ACC-06).
/// A null amount means "unknown".
final class AccountBalance {
  const AccountBalance({
    required this.accountId,
    required this.currency,
    required this.asOf,
    this.balance,
    this.available,
    this.sourceTxnId,
  });

  final String accountId;
  final Currency currency;
  final Money? balance;
  final Money? available;

  /// UTC time of the message the figures come from.
  final DateTime asOf;
  final String? sourceTxnId;
}

/// An account with every currency it holds, by currency code.
final class AccountWithBalances {
  const AccountWithBalances(this.account, this.balances);

  final Account account;
  final List<AccountBalance> balances;
}

/// What a captured message says about its account (parsing-engine §6).
final class AccountHint {
  const AccountHint({
    required this.institutionCode,
    required this.currency,
    required this.label,
    this.last4,
    this.kind,
  });

  /// The registry's institution code.
  final String institutionCode;

  /// Digits as read; Arabic-Indic digits are accepted.
  final String? last4;

  /// The billing currency stated by the message or the institution.
  final Currency currency;

  /// A display name for a new account (the user can rename it).
  final String label;

  /// An explicit kind from the template or the user; wins over inference.
  final AccountKind? kind;
}

/// The outcome of [AccountsRepository.resolve]. [created] is true only for
/// the one caller whose call created the account.
final class ResolvedAccount {
  const ResolvedAccount(this.account, {required this.created});

  final Account account;
  final bool created;
}

/// A change to an account (FR-ACC-01 rename and type, FR-ACC-05).
final class AccountEdit {
  const AccountEdit({
    this.label,
    this.kind,
    this.creditLimit,
    this.statementDueDay,
  });

  final String? label;
  final AccountKind? kind;

  /// Must be in the account's default currency and not negative.
  final Money? creditLimit;

  /// 1 to 31.
  final int? statementDueDay;
}

const Set<String> _cardEvents = {
  'card_purchase',
  'card_purchase_fx',
  'atm_withdrawal',
  'pending_auth',
  'settled',
};

/// The kind a new account gets (FR-ACC-01). [event] is the template event's
/// wire value (parsing-engine §3); the app does not depend on the parsing
/// package, so the caller passes the string.
///
/// Order: an [explicit] kind; an available-limit balance or `cc_payment` ->
/// credit; `bnpl_installment` -> bnpl; `wallet_topup` -> wallet;
/// `fx_conversion` -> multi-currency; a card event with a last-4 -> debit;
/// anything else (including an unknown event) -> account.
AccountKind inferAccountKind({
  String? event,
  bool balanceIsAvailableLimit = false,
  bool hasLast4 = false,
  AccountKind? explicit,
}) {
  if (explicit != null) return explicit;
  if (balanceIsAvailableLimit || event == 'cc_payment') {
    return AccountKind.credit;
  }
  switch (event) {
    case 'bnpl_installment':
      return AccountKind.bnpl;
    case 'wallet_topup':
      return AccountKind.wallet;
    case 'fx_conversion':
      return AccountKind.multiCurrency;
  }
  if (hasLast4 && _cardEvents.contains(event)) return AccountKind.debit;
  return AccountKind.account;
}

/// Maps Arabic-Indic (U+0660..0669) and Extended Arabic-Indic (U+06F0..06F9)
/// digits to ASCII; other characters are kept.
String normalizeDigits(String input) {
  final out = StringBuffer();
  for (final r in input.runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      out.writeCharCode(0x30 + r - 0x0660);
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      out.writeCharCode(0x30 + r - 0x06F0);
    } else {
      out.writeCharCode(r);
    }
  }
  return out.toString();
}

/// A stored account failed validation or is missing. Codes only; never a
/// label, last-4 or amount.
///
/// `ACC_NOT_FOUND`: no such account (or no live one where one is needed).
/// `ACC_INVALID`: the input failed a pre-check. `ACC_MERGED`: the account was
/// already merged into another. `ACC_DEFAULT_CASH`: the operation would
/// remove or retype the default cash account. `ACC_CORRUPT_ROW`: a stored
/// value is not a known code.
final class AccountsException extends SafeException {
  AccountsException(super.code);

  static const String notFound = 'ACC_NOT_FOUND';
  static const String invalid = 'ACC_INVALID';
  static const String merged = 'ACC_MERGED';
  static const String defaultCash = 'ACC_DEFAULT_CASH';
  static const String corruptRow = 'ACC_CORRUPT_ROW';
}
