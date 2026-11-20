// T-199 (D-75, FR-WLT-01): where the net worth figure comes from. Per
// currency: accounts by bank, assets, what you owe, and what is not counted
// (with a way to set the balance). Every line shows its source and date;
// the amounts of a unit add up to the figure above them. Hide-amounts masks
// every figure (MoneyFormat hidden:); amounts are never summed across
// currencies. Nothing here logs.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/l10n/card_number.dart';
import '../../../core/l10n/digits_mode.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/l10n/money_format.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/amount_semantics.dart';
import '../../../core/ui/bank_name_text.dart';
import '../../../core/ui/institution_avatar.dart';
import '../../../core/ui/z_components.dart';
import '../../../core/ui/z_hide_amounts_button.dart';
import '../../accounts/presentation/account_type.dart';
import '../../accounts/domain/account.dart' show AccountKind;
import 'asset_format.dart';
import 'balance_source_text.dart';
import 'net_worth_breakdown_providers.dart';

/// Opens the breakdown. [onOpenTransactions] receives the account ids of the
/// tapped bank or account (the shell sets the card filter and shows S-11).
Future<void> openNetWorthBreakdown(
  BuildContext context, {
  ValueChanged<List<String>>? onOpenTransactions,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) =>
        NetWorthBreakdownScreen(onOpenTransactions: onOpenTransactions),
  ),
);

class NetWorthBreakdownScreen extends ConsumerWidget {
  const NetWorthBreakdownScreen({super.key, this.onOpenTransactions});
  final ValueChanged<List<String>>? onOpenTransactions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final data = ref.watch(netWorthBreakdownProvider);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const BackButtonIcon(),
                ),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      l.networthTitle,
                      style: ZType.titleSmall.copyWith(color: c.text),
                    ),
                  ),
                ),
                const ZHideAmountsButton(),
              ],
            ),
            const SizedBox(height: ZSpacing.lg),
            ...data.when(
              loading: () => [const SizedBox(key: Key('networth-loading'))],
              error: (_, _) => [
                ZBanner(
                  message: l.commonErrorLoadFailed,
                  tone: ZBannerTone.warning,
                  actionLabel: l.commonActionTryAgain,
                  onAction: () => ref.invalidate(netWorthBreakdownProvider),
                ),
              ],
              data: (b) => b.units.isEmpty
                  ? [
                      Text(
                        l.networthEmpty,
                        style: ZType.body.copyWith(color: c.textMuted),
                      ),
                    ]
                  : [
                      for (final u in b.units)
                        _UnitSection(
                          unit: u,
                          onOpenTransactions: onOpenTransactions,
                        ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

String _fmt(WidgetRef ref, String lang, Money m, {bool withCurrency = true}) =>
    MoneyFormat.format(
      m,
      languageCode: lang,
      digits: ref.watch(digitsModeProvider(lang)),
      hidden: ref.watch(hideAmountsProvider),
      withCurrency: withCurrency,
    );

class _UnitSection extends ConsumerWidget {
  const _UnitSection({required this.unit, this.onOpenTransactions});
  final UnitBreakdown unit;
  final ValueChanged<List<String>>? onOpenTransactions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    final hidden = ref.watch(hideAmountsProvider);
    final cur = unit.isGold ? null : Currency.tryOf(unit.unit);
    final String title;
    final String net;
    if (unit.isGold) {
      title = _goldTitle(l, unit.unit, digits);
      net = unit.unit == GoldSymbols.coin
          ? digits.render('${unit.netMinor ~/ 1000}')
          : l.commonUnitGrams(
              hidden ? kAmountMask : formatMilli(unit.netMinor, digits),
            );
    } else if (cur != null) {
      title = MoneyFormat.currencyLabel(cur, languageCode: lang);
      net = _fmt(ref, lang, Money(cur, unit.netMinor));
    } else {
      return const SizedBox.shrink();
    }
    final banks = groupByBank(unit.accounts);
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            container: true,
            label: a11yAmounts(l, '$title, ${l.networthNet}, $net'),
            excludeSemantics: true,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: ZType.titleSmall.copyWith(color: c.text),
                  ),
                ),
                Text(
                  '${l.networthNet}  ',
                  style: ZType.label.copyWith(color: c.textMuted),
                ),
                ZMoneyText(
                  text: net,
                  size: ZMoneySize.body,
                  kind: ZMoneyKind.neutral,
                ),
              ],
            ),
          ),
          const SizedBox(height: ZSpacing.sm),
          if (banks.isNotEmpty)
            _Group(
              title: l.networthGroupAccounts,
              children: [
                for (final bank in banks)
                  _BankBlock(
                    bank: bank,
                    cur: cur,
                    onOpenTransactions: onOpenTransactions,
                  ),
              ],
            ),
          if (unit.assets.isNotEmpty)
            _Group(
              title: l.networthGroupAssets,
              children: [
                for (final line in unit.assets) _LineRow(line: line, cur: cur),
              ],
            ),
          if (unit.liabilities.isNotEmpty)
            _Group(
              title: l.networthGroupLiabilities,
              children: [
                for (final line in unit.liabilities)
                  _LineRow(
                    line: line,
                    cur: cur,
                    onTap: onOpenTransactions != null && line.isAccount
                        ? () => onOpenTransactions!([line.refId!])
                        : null,
                  ),
              ],
            ),
          if (unit.excluded.isNotEmpty)
            _Group(
              title: l.networthGroupExcluded,
              children: [
                for (final line in unit.excluded)
                  _LineRow(line: line, cur: cur),
              ],
            ),
        ],
      ),
    );
  }
}

String _goldTitle(AppLocalizations l, String symbol, DigitsMode digits) {
  if (symbol == GoldSymbols.coin) return l.commonKaratCoin;
  final karat = RegExp(r'^XAU(\d+)_G$').firstMatch(symbol)?.group(1);
  return karat == null
      ? symbol
      : l.wealthOverviewGoldTitle(digits.render(karat));
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.xs),
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: ZType.label.copyWith(color: c.textMuted),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(ZRadius.card),
              boxShadow: [
                BoxShadow(
                  color: c.shadow,
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(ZRadius.card),
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }
}

/// A bank: with two or more accounts a header with the bank total (sum of
/// its accounts in this currency), then the accounts; with one, just the line.
class _BankBlock extends ConsumerWidget {
  const _BankBlock({
    required this.bank,
    required this.cur,
    this.onOpenTransactions,
  });
  final BankGroup bank;
  final Currency? cur;
  final ValueChanged<List<String>>? onOpenTransactions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final ids = [for (final x in bank.lines) ?x.refId];
    void Function()? open(List<String> accountIds) => onOpenTransactions == null
        ? null
        : () => onOpenTransactions!(accountIds);
    if (bank.lines.length == 1) {
      return _LineRow(line: bank.lines.single, cur: cur, onTap: open(ids));
    }
    final first = bank.lines.first;
    final total = cur == null
        ? null
        : _fmt(ref, lang, Money(cur!, bank.totalMinor));
    final name = first.label;
    return Column(
      children: [
        Semantics(
          button: onOpenTransactions != null,
          label: a11yAmounts(
            l,
            [l.networthOpenBankA11y(name), ?total].join(', '),
          ),
          excludeSemantics: true,
          child: InkWell(
            onTap: open(ids),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: ZSpacing.lg,
                  vertical: ZSpacing.md,
                ),
                child: Row(
                  children: [
                    ZInstitutionAvatar(
                      institutionCode: first.institutionCode,
                      label: first.label,
                      size: 32,
                    ),
                    const SizedBox(width: ZSpacing.md),
                    Expanded(
                      child: BankNameText(
                        name: name,
                        institutionCode: first.institutionCode,
                        style: ZType.titleSmall.copyWith(color: c.text),
                      ),
                    ),
                    if (total != null)
                      ZMoneyText(
                        text: total,
                        size: ZMoneySize.body,
                        kind: ZMoneyKind.neutral,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        for (final line in bank.lines)
          _LineRow(
            line: line,
            cur: cur,
            indent: true,
            onTap: open([?line.refId]),
          ),
      ],
    );
  }
}

class _LineRow extends ConsumerWidget {
  const _LineRow({
    required this.line,
    required this.cur,
    this.onTap,
    this.indent = false,
  });
  final BreakdownLine line;
  final Currency? cur;
  final VoidCallback? onTap;
  final bool indent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    final hidden = ref.watch(hideAmountsProvider);
    final source = balanceSourceText(l, line, lang: lang, digits: digits);
    String? amount;
    if (line.amount != null) {
      amount = _fmt(ref, lang, line.amount!);
    } else if (line.quantityMilli != null) {
      amount = line.unit == GoldSymbols.coin
          ? digits.render('${line.quantityMilli! ~/ 1000}')
          : l.commonUnitGrams(
              hidden ? kAmountMask : formatMilli(line.quantityMilli!, digits),
            );
    }
    final kind = line.accountKind == null
        ? null
        : AccountKind.fromCode(line.accountKind!);
    final name = line.isAccount
        ? formatAccountWithCard(line.label, line.last4)
        : line.label;
    final canSet = line.isExcluded && line.isAccount && line.refId != null;
    return Semantics(
      container: true,
      button: onTap != null,
      label: a11yAmounts(
        l,
        [
          l.networthLineA11y(name, source),
          if (kind != null) accountKindLabel(l, kind),
          ?amount,
        ].join(', '),
      ),
      excludeSemantics: !canSet,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              start: indent ? ZSpacing.lg + 44 : ZSpacing.lg,
              end: ZSpacing.lg,
              top: ZSpacing.md,
              bottom: ZSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BankNameText(
                        name: line.label,
                        institutionCode: line.institutionCode,
                        last4: line.last4,
                        style: ZType.body.copyWith(color: c.text),
                      ),
                      Text(
                        source,
                        style: ZType.caption.copyWith(
                          color: line.isExcluded ? c.warningText : c.textMuted,
                        ),
                      ),
                      if (kind != null)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(
                            top: ZSpacing.xs,
                          ),
                          child: AccountTypeChip(kind: kind),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: ZSpacing.sm),
                if (amount != null)
                  ZMoneyText(
                    text: amount,
                    size: ZMoneySize.body,
                    kind: ZMoneyKind.neutral,
                  )
                else if (canSet)
                  TextButton(
                    key: Key('networth-set-${line.refId}-${line.unit}'),
                    onPressed: () => showSetBalanceSheet(
                      context,
                      ref,
                      accountId: line.refId!,
                      name: name,
                      currency: Currency.of(line.unit),
                      isLiability: line.isLiability,
                    ),
                    child: Text(l.networthSetBalance),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The "set the balance" sheet: one amount in the pair's currency, true as
/// of now. Typed digits in any script are accepted; a wrong amount is refused
/// with a message, nothing is stored.
Future<void> showSetBalanceSheet(
  BuildContext context,
  WidgetRef ref, {
  required String accountId,
  required String name,
  required Currency currency,
  required bool isLiability,
}) => showZSheet<void>(
  context: context,
  title: AppLocalizations.of(context).networthSheetTitle(name),
  builder: (ctx) => _SetBalanceForm(
    accountId: accountId,
    currency: currency,
    isLiability: isLiability,
    ref: ref,
  ),
);

class _SetBalanceForm extends StatefulWidget {
  const _SetBalanceForm({
    required this.accountId,
    required this.currency,
    required this.isLiability,
    required this.ref,
  });
  final String accountId;
  final Currency currency;
  final bool isLiability;
  final WidgetRef ref;

  @override
  State<_SetBalanceForm> createState() => _SetBalanceFormState();
}

class _SetBalanceFormState extends State<_SetBalanceForm> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save(AppLocalizations l) async {
    final text = _controller.text.trim();
    final negative = text.startsWith('-');
    final m = MoneyFormat.parseInput(
      negative ? text.substring(1) : text,
      widget.currency,
    );
    if (m == null || (negative && widget.isLiability)) {
      setState(() => _error = l.networthSheetInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await setOpeningBalance(
        widget.ref,
        accountId: widget.accountId,
        amount: negative ? -m : m,
      );
      if (mounted) Navigator.of(context).pop();
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = l.networthSheetFailed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('networth-amount'),
          controller: _controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: widget.isLiability
                ? l.networthSheetAmountOwed
                : l.networthSheetAmount,
            suffixText: widget.currency.code,
            errorText: _error,
            errorMaxLines: 2,
          ),
        ),
        const SizedBox(height: ZSpacing.sm),
        Text(
          l.networthSheetHint,
          style: ZType.caption.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: ZSpacing.lg),
        ZButton(
          key: const Key('networth-save'),
          label: l.networthSheetSave,
          onPressed: _busy ? null : () => _save(l),
        ),
      ],
    );
  }
}
