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
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(ZRadius.hero)),
    ),
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
    final tints = [
      c.surfaceAlt,
      c.surfaceAlt,
      c.dangerBg,
      c.surfaceAlt,
      c.warningBg,
    ];
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.accountsAddTypeTitle,
              textAlign: TextAlign.center,
              style: ZType.title.copyWith(color: c.text),
            ),
          ),
          const SizedBox(height: ZSpacing.md),
          Container(
            padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
            decoration: BoxDecoration(
              color: c.primaryContainer,
              borderRadius: BorderRadius.circular(ZRadius.lg),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: c.primary),
                const SizedBox(width: ZSpacing.md),
                Expanded(
                  child: Text(
                    l10n.accountsAddTypeInfo,
                    style: ZType.bodySmall.copyWith(color: c.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: ZSpacing.md),
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
              child: Material(
                color: c.surface,
                elevation: 1,
                shadowColor: c.shadow,
                borderRadius: BorderRadius.circular(ZRadius.lg),
                child: InkWell(
                  key: Key('add-type-${rows[i].$1.code}'),
                  borderRadius: BorderRadius.circular(ZRadius.lg),
                  onTap: () => Navigator.of(context).pop(rows[i].$1),
                  child: Semantics(
                    button: true,
                    label: '${rows[i].$2}, ${rows[i].$3}',
                    excludeSemantics: true,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 72),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: ZSpacing.lg,
                          vertical: ZSpacing.md,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: tints[i],
                                shape: BoxShape.circle,
                              ),
                              child: Icon(rows[i].$4, color: c.primary),
                            ),
                            const SizedBox(width: ZSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    rows[i].$2,
                                    style: ZType.titleSmall.copyWith(
                                      color: c.text,
                                    ),
                                  ),
                                  Text(
                                    rows[i].$3,
                                    style: ZType.bodySmall.copyWith(
                                      color: c.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: c.textMuted,
                              textDirection: Directionality.of(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
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

    Widget row(InstitutionOption i) => _BankCell(
      key: Key('bank-${i.code}'),
      name: i.name(lang),
      letter: i.monogram(lang),
      seed: i.code,
      onTap: () => Navigator.of(context).pop(i),
    );
    Widget grid(List<InstitutionOption> items) => Wrap(
      runSpacing: ZSpacing.md,
      children: [for (final i in items) row(i)],
    );

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Material(
                color: c.surface,
                shape: const CircleBorder(),
                elevation: 1,
                shadowColor: c.shadow,
                child: IconButton(
                  tooltip: l10n.commonActionClose,
                  constraints: const BoxConstraints(
                    minWidth: ZSpacing.minTarget,
                    minHeight: ZSpacing.minTarget,
                  ),
                  icon: const BackButtonIcon(),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            const SizedBox(height: ZSpacing.lg),
            Semantics(
              header: true,
              child: Text(
                l10n.accountsAddBankTitle,
                style: ZType.display.copyWith(color: c.text),
              ),
            ),
            const SizedBox(height: ZSpacing.lg),
            TextField(
              key: const Key('bank-search'),
              controller: _search,
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: l10n.accountsAddBankSearch,
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: c.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ZRadius.pill),
                  borderSide: BorderSide(color: c.outline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ZRadius.pill),
                  borderSide: BorderSide(color: c.outline),
                ),
              ),
            ),
            const SizedBox(height: ZSpacing.md),
            if (egypt.isNotEmpty) _Header(l10n.accountsAddBankEgypt),
            grid(egypt),
            if (abroad.isNotEmpty) _Header(l10n.accountsAddBankAbroad),
            grid(abroad),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
                child: Text(
                  l10n.accountsAddBankNoResults,
                  key: const Key('bank-no-results'),
                  style: ZType.body.copyWith(color: c.textMuted),
                ),
              ),
            const SizedBox(height: ZSpacing.lg),
            ZCard(
              key: const Key('bank-not-listed'),
              onTap: () => Navigator.of(context).pop(
                InstitutionOption(
                  code: genericInstitutionCode,
                  nameAr: l10n.accountsAddBankNotListed,
                  nameEn: l10n.accountsAddBankNotListed,
                  defaultCurrency: _egp,
                  isEgypt: true,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.add_rounded, color: c.primary),
                  ),
                  const SizedBox(width: ZSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.accountsAddBankNotListed,
                          style: ZType.titleSmall.copyWith(color: c.text),
                        ),
                        Text(
                          l10n.accountsAddBankNotListedSub,
                          style: ZType.bodySmall.copyWith(color: c.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: c.textMuted,
                    textDirection: Directionality.of(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One bank in the grid: tinted round monogram with the name below.
class _BankCell extends StatelessWidget {
  const _BankCell({
    super.key,
    required this.name,
    required this.letter,
    required this.seed,
    required this.onTap,
  });
  final String name;
  final String letter;
  final String seed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final palette = [
      c.primary,
      c.dangerText,
      c.warningText,
      c.tintBlue,
      c.tintViolet,
      c.tintTeal,
    ];
    final tone =
        palette[seed.codeUnits.fold<int>(0, (a, b) => a + b) % palette.length];
    return SizedBox(
      width: (MediaQuery.sizeOf(context).width - 2 * ZSpacing.screen) / 4,
      child: Semantics(
        button: true,
        label: name,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(ZRadius.md),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
            child: Column(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    letter,
                    style: ZType.label.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: ZSpacing.xs),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ZType.bodySmall.copyWith(color: c.text),
                ),
              ],
            ),
          ),
        ),
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
        top: ZSpacing.lg,
        bottom: ZSpacing.md,
      ),
      child: Semantics(
        header: true,
        child: Text(text, style: ZType.title.copyWith(color: c.text)),
      ),
    );
  }
}
