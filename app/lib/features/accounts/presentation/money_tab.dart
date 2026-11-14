// T-083: Money tab root (S-40), accounts part. Net worth per currency (never
// summed), the account list with "as of" times, a hidden-accounts entry and a
// Gold-gated assets placeholder (assets themselves are T-121).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/l10n/date_format.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/l10n/money_format.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_components.dart';
import '../../wealth/presentation/assets_section.dart';
import '../../wealth/data/approx_view_providers.dart';
import '../../wealth/domain/approx_view.dart';
import '../domain/account.dart';
import 'money_overview_provider.dart';

/// Shown when there are no balances yet.
final _zeroEgp = Money(Currency.of('EGP'), 0);

class MoneyTab extends ConsumerWidget {
  const MoneyTab({
    super.key,
    this.onAdd,
    this.onOpenAccount,
    this.onOpenHidden,
    this.onCompare,
    this.onOpenAssetsPaywall,
    this.onAddAsset,
    this.onOpenPrices,
  });

  /// Add account (S-43).
  final VoidCallback? onAdd;
  final void Function(Account account)? onOpenAccount;
  final VoidCallback? onOpenHidden;
  final VoidCallback? onCompare;
  final VoidCallback? onOpenAssetsPaywall;

  /// Add asset (S-44), Gold users.
  final VoidCallback? onAddAsset;

  /// Prices (S-45), Gold users.
  final VoidCallback? onOpenPrices;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final overview = ref.watch(moneyOverviewProvider);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      l10n.accountsOverviewTitle,
                      style: ZType.headline.copyWith(color: c.text),
                    ),
                  ),
                ),
                const SizedBox(width: ZSpacing.sm),
                Flexible(
                  child: ZButton(
                    label: l10n.accountsOverviewAdd,
                    onPressed: onAdd,
                    variant: ZButtonVariant.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: ZSpacing.lg),
            ...overview.when(
              loading: () => [_Skeleton(key: const Key('money-loading'))],
              error: (_, _) => [
                ZBanner(
                  message: l10n.commonErrorLoadFailed,
                  tone: ZBannerTone.warning,
                ),
              ],
              data: (data) => data.isEmpty
                  ? [_Empty(onAdd: onAdd)]
                  : [
                      _Hero(totals: data.totals),
                      const SizedBox(height: ZSpacing.xl),
                      _AccountsSection(
                        data: data,
                        onOpenAccount: onOpenAccount,
                        onOpenHidden: onOpenHidden,
                        onCompare: onCompare,
                      ),
                    ],
            ),
            const SizedBox(height: ZSpacing.xl),
            AssetsSection(
              onAddAsset: onAddAsset,
              onOpenPrices: onOpenPrices,
              onOpenPaywall: onOpenAssetsPaywall,
            ),
          ],
        ),
      ),
    );
  }
}

String _fmt(BuildContext context, WidgetRef ref, Money m) {
  final lang = Localizations.localeOf(context).languageCode;
  return MoneyFormat.format(
    m,
    languageCode: lang,
    digits: ref.watch(digitsModeProvider(lang)),
  );
}

class _Hero extends ConsumerWidget {
  const _Hero({required this.totals});
  final MultiCurrencyTotal totals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final currencies = totals.currencies;
    final approx = ref.watch(approxViewProvider(totals)).value;
    return ZCard(
      color: c.primaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.accountsOverviewNetWorth,
            style: ZType.label.copyWith(color: c.onPrimaryContainer),
          ),
          const SizedBox(height: ZSpacing.sm),
          if (currencies.isEmpty)
            ZMoneyText(
              text: _fmt(context, ref, _zeroEgp),
              size: ZMoneySize.display,
              kind: ZMoneyKind.expense,
            )
          else ...[
            ZMoneyText(
              text: _fmt(context, ref, totals[currencies.first]),
              size: ZMoneySize.display,
            ),
            for (final cur in currencies.skip(1))
              Padding(
                padding: const EdgeInsetsDirectional.only(top: ZSpacing.xs),
                child: ZMoneyText(
                  text: _fmt(context, ref, totals[cur]),
                  size: ZMoneySize.title,
                ),
              ),
          ],
          if (approx is ApproxViewOn) ...[
            const SizedBox(height: ZSpacing.sm),
            if (approx.figure != null)
              Semantics(
                label: l10n.commonCurrencyApproxA11y,
                child: ZMoneyText(
                  text: l10n.commonCurrencyApproxChip(
                    _fmt(context, ref, approx.figure!.amount),
                  ),
                  size: ZMoneySize.body,
                  kind: ZMoneyKind.neutral,
                ),
              ),
            // FU-134: the "not included" note shows whenever `excluded` is
            // non-empty. TODO(l10n): key missing (see T-083 task file); the
            // codes alone are shown until it lands.
            if (approx.excluded.isNotEmpty)
              Padding(
                key: const Key('approx-not-included'),
                padding: const EdgeInsetsDirectional.only(top: ZSpacing.xs),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: c.textMuted,
                    ),
                    const SizedBox(width: ZSpacing.xs),
                    Flexible(
                      child: Text(
                        approx.excluded.map((e) => e.code).join(' · '),
                        style: ZType.caption.copyWith(color: c.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _AccountsSection extends StatelessWidget {
  const _AccountsSection({
    required this.data,
    this.onOpenAccount,
    this.onOpenHidden,
    this.onCompare,
  });
  final MoneyOverview data;
  final void Function(Account)? onOpenAccount;
  final VoidCallback? onOpenHidden;
  final VoidCallback? onCompare;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.accountsOverviewAccountsTitle,
                style: ZType.titleSmall.copyWith(color: c.text),
              ),
            ),
            Flexible(
              child: TextButton(
                onPressed: onCompare,
                style: TextButton.styleFrom(
                  minimumSize: const Size(
                    ZSpacing.minTarget,
                    ZSpacing.minTarget,
                  ),
                ),
                child: Text(l10n.accountsOverviewCompare),
              ),
            ),
          ],
        ),
        const SizedBox(height: ZSpacing.sm),
        for (final a in data.visible)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
            child: _AccountRow(
              item: a,
              onTap: onOpenAccount == null
                  ? null
                  : () => onOpenAccount!(a.account),
            ),
          ),
        if (data.hiddenCount > 0)
          _HiddenRow(count: data.hiddenCount, onTap: onOpenHidden),
      ],
    );
  }
}

class _AccountRow extends ConsumerWidget {
  const _AccountRow({required this.item, this.onTap});
  final AccountWithBalances item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    final account = item.account;
    final first = item.balances.isEmpty ? null : item.balances.first;

    String? primary;
    String? sub;
    if (first != null) {
      final asOf = l10n.accountsOverviewAsOf(
        ZDateFormat.date(first.asOf.toLocal(), lang, digits),
      );
      sub = asOf;
      final isCredit = account.kind == AccountKind.credit;
      if (isCredit && first.available != null) {
        primary = account.creditLimit == null
            ? _fmt(context, ref, first.available!)
            : l10n.accountsDetailAvailableOf(
                _fmt(context, ref, first.available!),
                _fmt(context, ref, account.creditLimit!),
              );
      } else if (first.balance != null) {
        primary = _fmt(context, ref, first.balance!);
      }
    }
    final extra = item.balances.length - 1;
    final label = account.last4 == null
        ? account.label
        : '${account.label} •${account.last4}';
    final semantics = [label, ?primary, ?sub].join(', ');
    return Semantics(
      container: true,
      button: onTap != null,
      label: semantics,
      excludeSemantics: true,
      child: ZCard(
        onTap: onTap,
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: ZSpacing.lg,
          vertical: ZSpacing.md,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: ZType.titleSmall.copyWith(color: c.text),
                    ),
                    if (account.kind == AccountKind.cash)
                      Text(
                        l10n.accountsOverviewCashSub,
                        style: ZType.caption.copyWith(color: c.textMuted),
                      ),
                    if (sub != null)
                      Text(
                        sub,
                        style: ZType.caption.copyWith(color: c.textMuted),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: ZSpacing.sm),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (primary != null)
                      ZMoneyText(text: primary, size: ZMoneySize.body),
                    if (extra > 0)
                      Text(
                        l10n.accountsOverviewMoreCurrencies(
                          extra,
                          digits.render('$extra'),
                        ),
                        style: ZType.caption.copyWith(color: c.textMuted),
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
    );
  }
}

class _HiddenRow extends ConsumerWidget {
  const _HiddenRow({required this.count, this.onTap});
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final n = ref.watch(digitsModeProvider(lang)).render('$count');
    return Semantics(
      button: true,
      label: '${l10n.accountsOverviewHiddenEntry}, $n',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.accountsOverviewHiddenEntry,
                  style: ZType.body.copyWith(color: c.textMuted),
                ),
              ),
              Text(n, style: ZType.body.copyWith(color: c.textMuted)),
              Icon(Icons.chevron_right_rounded, color: c.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({this.onAdd});
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return ZCard(
      child: Column(
        children: [
          Text(
            l10n.accountsOverviewEmptyTitle,
            textAlign: TextAlign.center,
            style: ZType.titleSmall.copyWith(color: c.text),
          ),
          const SizedBox(height: ZSpacing.md),
          ZButton(label: l10n.accountsOverviewEmptyAdd, onPressed: onAdd),
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    Widget bar(double h) => Container(
      height: h,
      margin: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(ZRadius.card),
      ),
    );
    return ExcludeSemantics(
      child: Column(children: [bar(120), bar(64), bar(64), bar(64)]),
    );
  }
}
