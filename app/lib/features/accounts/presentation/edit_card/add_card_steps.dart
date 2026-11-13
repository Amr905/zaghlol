// T-085: steps 1 and 2 of adding a card (flows 07 §B, mockups 28 and 29):
// the type sheet and the bank picker. Both return a value through the
// navigator; neither touches the database.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/z_card.dart';
import '../../domain/account.dart';
import 'card_form_logic.dart';
import 'edit_card_providers.dart';

/// Sheet "What are you adding?". Null when dismissed.
Future<AccountKind?> showAddCardTypeSheet(BuildContext context) {
  return showModalBottomSheet<AccountKind>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _TypeSheet(),
  );
}

class _TypeSheet extends StatelessWidget {
  const _TypeSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final rows = <(AccountKind, String, String, IconData)>[
      (
        AccountKind.credit,
        l10n.accountsAddTypeCredit,
        l10n.accountsAddTypeCreditSub,
        Icons.credit_card_rounded,
      ),
      (
        AccountKind.debit,
        l10n.accountsAddTypeDebit,
        l10n.accountsAddTypeDebitSub,
        Icons.account_balance_rounded,
      ),
      (
        AccountKind.wallet,
        l10n.accountsAddTypeWallet,
        l10n.accountsAddTypeWalletSub,
        Icons.account_balance_wallet_rounded,
      ),
      (
        AccountKind.multiCurrency,
        l10n.accountsAddTypeMulti,
        l10n.accountsAddTypeMultiSub,
        Icons.currency_exchange_rounded,
      ),
      (
        AccountKind.bnpl,
        l10n.accountsAddTypeBnpl,
        l10n.accountsAddTypeBnplSub,
        Icons.schedule_rounded,
      ),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.accountsAddTypeTitle,
              style: ZType.title.copyWith(color: c.text),
            ),
          ),
          const SizedBox(height: ZSpacing.sm),
          Text(
            l10n.accountsAddTypeInfo,
            style: ZType.bodySmall.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: ZSpacing.md),
          for (final r in rows)
            ZListRow(
              key: Key('add-type-${r.$1.code}'),
              title: r.$2,
              subtitle: r.$3,
              leading: Icon(r.$4, color: c.primary),
              showChevron: true,
              onTap: () => Navigator.of(context).pop(r.$1),
            ),
        ],
      ),
    );
  }
}

/// Full-screen bank picker. Returns the chosen option; "My bank isn't
/// listed" returns the generic institution.
Future<InstitutionOption?> pushBankPicker(BuildContext context) {
  return Navigator.of(context).push<InstitutionOption>(
    MaterialPageRoute(builder: (_) => const BankPicker()),
  );
}

class BankPicker extends ConsumerStatefulWidget {
  const BankPicker({super.key});

  @override
  ConsumerState<BankPicker> createState() => _BankPickerState();
}

class _BankPickerState extends ConsumerState<BankPicker> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final all = ref.watch(institutionOptionsProvider);
    final q = _q.trim().toLowerCase();
    final shown = [
      for (final i in all)
        if (q.isEmpty ||
            i.nameAr.toLowerCase().contains(q) ||
            i.nameEn.toLowerCase().contains(q))
          i,
    ]..sort((a, b) => a.name(lang).compareTo(b.name(lang)));
    final egypt = shown.where((i) => i.isEgypt).toList();
    final abroad = shown.where((i) => !i.isEgypt).toList();

    Widget row(InstitutionOption i) => ZListRow(
      key: Key('bank-${i.code}'),
      title: i.name(lang),
      leading: _Monogram(letter: i.monogram(lang)),
      onTap: () => Navigator.of(context).pop(i),
    );

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(l10n.accountsAddBankTitle),
        leading: IconButton(
          tooltip: l10n.commonActionClose,
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
        children: [
          TextField(
            key: const Key('bank-search'),
            controller: _search,
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
              hintText: l10n.accountsAddBankSearch,
              prefixIcon: const Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: ZSpacing.md),
          if (egypt.isNotEmpty) _Header(l10n.accountsAddBankEgypt),
          for (final i in egypt) row(i),
          if (abroad.isNotEmpty) _Header(l10n.accountsAddBankAbroad),
          for (final i in abroad) row(i),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
              child: Text(
                l10n.accountsAddBankNoResults,
                key: const Key('bank-no-results'),
                style: ZType.body.copyWith(color: c.textMuted),
              ),
            ),
          const SizedBox(height: ZSpacing.md),
          ZListRow(
            key: const Key('bank-not-listed'),
            title: l10n.accountsAddBankNotListed,
            subtitle: l10n.accountsAddBankNotListedSub,
            leading: const _Monogram(letter: '+'),
            onTap: () => Navigator.of(context).pop(
              InstitutionOption(
                code: genericInstitutionCode,
                nameAr: l10n.accountsAddBankNotListed,
                nameEn: l10n.accountsAddBankNotListed,
                defaultCurrency: _egp,
                isEgypt: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final _egp = Currency.of('EGP');

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        top: ZSpacing.md,
        bottom: ZSpacing.xs,
      ),
      child: Semantics(
        header: true,
        child: Text(text, style: ZType.label.copyWith(color: c.textMuted)),
      ),
    );
  }
}

class _Monogram extends StatelessWidget {
  const _Monogram({required this.letter});
  final String letter;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return ExcludeSemantics(
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Text(
          letter,
          style: ZType.titleSmall.copyWith(color: c.onPrimaryContainer),
        ),
      ),
    );
  }
}
