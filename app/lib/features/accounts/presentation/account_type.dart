// T-197 / D-73: how an account's type shows up on every card surface. The
// type is always text plus an icon, never colour alone. Pure presentation:
// no amounts here.

import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/ui/z_chip.dart';
import '../domain/account.dart';

/// The words for an account type (the shared `commonAccountType*` strings).
String accountKindLabel(AppLocalizations l, AccountKind k) => switch (k) {
  AccountKind.debit => l.commonAccountTypeDebit,
  AccountKind.credit => l.commonAccountTypeCredit,
  AccountKind.account => l.commonAccountTypeAccount,
  AccountKind.wallet => l.commonAccountTypeWallet,
  AccountKind.bnpl => l.commonAccountTypeBnpl,
  AccountKind.cash => l.commonAccountTypeCash,
  AccountKind.multiCurrency => l.commonAccountTypeMultiCurrency,
};

/// A distinct glyph per type.
IconData accountKindIcon(AccountKind k) => switch (k) {
  AccountKind.debit => Icons.credit_card_rounded,
  AccountKind.credit => Icons.credit_score_rounded,
  AccountKind.account => Icons.account_balance_rounded,
  AccountKind.wallet => Icons.account_balance_wallet_rounded,
  AccountKind.bnpl => Icons.event_repeat_rounded,
  AccountKind.cash => Icons.payments_rounded,
  AccountKind.multiCurrency => Icons.currency_exchange_rounded,
};

/// The Money tab sections (D-73), in display order.
enum AccountGroup { bank, credit, wallets, cash }

AccountGroup accountGroupOf(AccountKind k) => switch (k) {
  AccountKind.debit ||
  AccountKind.account ||
  AccountKind.multiCurrency => AccountGroup.bank,
  AccountKind.credit || AccountKind.bnpl => AccountGroup.credit,
  AccountKind.wallet => AccountGroup.wallets,
  AccountKind.cash => AccountGroup.cash,
};

String accountGroupTitle(AppLocalizations l, AccountGroup g) => switch (g) {
  AccountGroup.bank => l.accountsGroupBank,
  AccountGroup.credit => l.accountsGroupCredit,
  AccountGroup.wallets => l.accountsGroupWallets,
  AccountGroup.cash => l.accountsGroupCash,
};

/// "CIB •1334 · Credit": the name with its type, for places that have no
/// room for a chip (pickers, detail rows).
String accountNameWithType(
  AppLocalizations l,
  String name,
  AccountKind? kind,
) => kind == null ? name : '$name · ${accountKindLabel(l, kind)}';

/// The type chip: icon + text on a neutral pill ([ZPill]).
class AccountTypeChip extends StatelessWidget {
  const AccountTypeChip({super.key, required this.kind});
  final AccountKind kind;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ZPill(
      label: accountKindLabel(l, kind),
      icon: accountKindIcon(kind),
      tone: kind == AccountKind.credit || kind == AccountKind.bnpl
          ? ZPillTone.info
          : ZPillTone.neutral,
    );
  }
}
