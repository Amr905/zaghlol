// T-083: Money tab root (S-40), accounts part. Net worth per currency (never
// summed), the account list with "as of" times, a hidden-accounts entry and a
// Gold-gated assets placeholder (assets themselves are T-121).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/ui/institution_avatar.dart';
import '../../../core/ui/bank_name_text.dart';
import '../../../core/l10n/card_number.dart';
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
import 'account_type.dart';
import 'money_overview_provider.dart';
import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/ui/z_hide_amounts_button.dart';
import '../../../core/ui/amount_semantics.dart';

/// Diameter of the bank tile; the credit bar lines up under the text.
const double _kTileSize = 48;

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
    this.onOpenZakah,
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

  /// Zakah (S-46); shown only when the flag is on.
  final VoidCallback? onOpenZakah;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final overview = ref.watch(moneyOverviewProvider);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(
            ZSpacing.screen,
            ZSpacing.screen,
            ZSpacing.screen,
            ZSpacing.fabClearance,
          ),
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Semantics(
                button: true,
                label: l10n.accountsOverviewAdd,
                excludeSemantics: true,
                child: Material(
                  color: c.surface,
                  shape: const StadiumBorder(),
                  elevation: 1,
                  shadowColor: c.shadow,
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: onAdd,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: ZSpacing.minTarget,
                      ),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: ZSpacing.md,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_rounded, color: c.primary),
                            const SizedBox(width: ZSpacing.xs),
                            Text(
                              l10n.accountsOverviewAdd,
                              style: ZType.label.copyWith(color: c.text),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: ZSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      l10n.accountsOverviewTitle,
                      style: ZType.display.copyWith(color: c.text),
                    ),
                  ),
                ),
                const ZHideAmountsButton(),
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
              onOpenZakah: onOpenZakah,
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
    hidden: ref.watch(hideAmountsProvider),
    dropZeroFraction: true,
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
    final firstCur = currencies.isEmpty ? _zeroEgp.currency : currencies.first;
    final approx = ref.watch(approxViewProvider(totals)).value;
    final lang = Localizations.localeOf(context).languageCode;
    return Container(
      padding: const EdgeInsetsDirectional.all(ZSpacing.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ZRadius.hero),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topEnd,
          end: AlignmentDirectional.bottomStart,
          colors: [
            c.primaryContainer,
            Color.lerp(c.primaryContainer, c.accentLight, 0.25)!,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.accountsOverviewNetWorth,
            style: ZType.label.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: ZSpacing.sm),
          Semantics(
            label: a11yAmounts(l10n, _fmt(context, ref, totals[firstCur])),
            excludeSemantics: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: ZMoneyText(
                text: MoneyFormat.format(
                  totals[firstCur],
                  languageCode: lang,
                  digits: ref.watch(digitsModeProvider(lang)),
                  hidden: ref.watch(hideAmountsProvider),
                  withCurrency: false,
                  dropZeroFraction: true,
                ),
                unit: MoneyFormat.currencyLabel(
                  totals[firstCur].currency,
                  languageCode: lang,
                ),
                kind: ZMoneyKind.expense,
                size: ZMoneySize.hero,
              ),
            ),
          ),
          if (currencies.length > 1) ...[
            const SizedBox(height: ZSpacing.md),
            Wrap(
              spacing: ZSpacing.sm,
              runSpacing: ZSpacing.sm,
              children: [
                for (final cur in currencies.skip(1))
                  Container(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: ZSpacing.md,
                      vertical: ZSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: c.surface.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(ZRadius.pill),
                    ),
                    child: Semantics(
                      label: a11yAmounts(l10n, _fmt(context, ref, totals[cur])),
                      excludeSemantics: true,
                      child: Text(
                        '\u2068${_fmt(context, ref, totals[cur])}\u2069',
                        style: ZType.label.copyWith(color: c.text),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (approx is ApproxViewOn) ...[
            const SizedBox(height: ZSpacing.sm),
            ZApproxRow(
              figureText: approx.figure == null
                  ? null
                  : _fmt(context, ref, approx.figure!.amount),
              rateDateText: approx.rateAsOfMs == null
                  ? null
                  : ZDateFormat.date(
                      DateTime.fromMillisecondsSinceEpoch(
                        approx.rateAsOfMs!,
                        isUtc: true,
                      ),
                      Localizations.localeOf(context).languageCode,
                      ref.watch(
                        digitsModeProvider(
                          Localizations.localeOf(context).languageCode,
                        ),
                      ),
                    ),
              excludedCodes: [for (final e in approx.excluded) e.code],
              stale: approx.stale,
            ),
          ],
        ],
      ),
    );
  }
}

class _AccountsSection extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final grouped = ref.watch(moneyGroupByTypeProvider).value ?? true;
    final due = ref.watch(cardDueDatesProvider).value ?? const {};
    final sections = <(AccountGroup?, List<AccountWithBalances>)>[];
    if (grouped) {
      for (final g in AccountGroup.values) {
        final items = [
          for (final a in data.visible)
            if (accountGroupOf(a.account.kind) == g) a,
        ];
        if (items.isNotEmpty) sections.add((g, items));
      }
    } else {
      sections.add((null, data.visible));
    }
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
        ZChip(
          key: const Key('money-group-toggle'),
          label: l10n.accountsGroupToggle,
          icon: grouped ? Icons.check_rounded : Icons.category_outlined,
          selected: grouped,
          onTap: () async {
            final repo = await ref.read(settingsRepositoryProvider.future);
            await repo.set(Settings.moneyGroupByType, !grouped);
          },
        ),
        for (final (group, items) in sections) ...[
          const SizedBox(height: ZSpacing.sm),
          if (group != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                top: ZSpacing.sm,
                bottom: ZSpacing.xs,
              ),
              child: Semantics(
                header: true,
                child: Text(
                  accountGroupTitle(l10n, group),
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
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: c.outline,
                        indent: ZSpacing.lg,
                        endIndent: ZSpacing.lg + 56,
                      ),
                    _AccountRow(
                      item: items[i],
                      due: due[items[i].account.id],
                      onTap: onOpenAccount == null
                          ? null
                          : () => onOpenAccount!(items[i].account),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: ZSpacing.sm),
        if (data.hiddenCount > 0)
          _HiddenRow(count: data.hiddenCount, onTap: onOpenHidden),
      ],
    );
  }
}

class _AccountRow extends ConsumerWidget {
  const _AccountRow({required this.item, this.due, this.onTap});
  final AccountWithBalances item;
  final CivilDate? due;
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
    // Credit: used / limit with a bar (T-197). The bar keeps its shape while
    // amounts are hidden; the numbers are masked by _fmt.
    double? usedFraction;
    String? usedPct;
    if (first != null) {
      final asOf = l10n.accountsOverviewAsOf(
        ZDateFormat.date(first.asOf.toLocal(), lang, digits),
      );
      sub = asOf;
      final limit = account.creditLimit;
      final isCredit = account.kind == AccountKind.credit;
      if (isCredit && first.available != null) {
        final avail = first.available!;
        if (limit == null || limit.currency != avail.currency) {
          // No limit, or figures in different currencies: no used figure.
          primary = _fmt(context, ref, avail);
        } else {
          // Over the limit shows used > limit (available below zero); only a
          // negative "used" is floored.
          final usedMinor = limit.minor - avail.minor < 0
              ? 0
              : limit.minor - avail.minor;
          primary = l10n.accountsOverviewUsedOf(
            _fmt(context, ref, Money(limit.currency, usedMinor)),
            _fmt(context, ref, limit),
          );
          usedFraction = limit.minor <= 0
              ? (usedMinor > 0 ? 1 : 0)
              : usedMinor / limit.minor;
          usedPct = digits.render('${(usedFraction * 100).round()}%');
        }
      } else if (first.balance != null) {
        primary = _fmt(context, ref, first.balance!);
      }
    }
    final dueText = account.kind == AccountKind.credit && due != null
        ? l10n.accountsOverviewDueOn(
            ZDateFormat.date(
              DateTime.utc(due!.year, due!.month, due!.day),
              lang,
              digits,
            ),
          )
        : null;
    final extra = item.balances.length - 1;
    final label = formatAccountWithCard(account.label, account.last4);
    final semantics = [
      label,
      accountKindLabel(l10n, account.kind),
      ?primary,
      // The used share is a figure of the amounts: not spoken while hidden.
      ?(usedPct == null || ref.watch(hideAmountsProvider)
          ? null
          : l10n.accountsOverviewUsedBarA11y(usedPct)),
      ?dueText,
      ?sub,
    ].join(', ');
    return Semantics(
      container: true,
      button: onTap != null,
      label: a11yAmounts(l10n, semantics),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: ZSpacing.lg,
            vertical: ZSpacing.md,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Tile(account: account),
                    const SizedBox(width: ZSpacing.md),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          BankNameText(
                            name: account.label,
                            institutionCode: account.institutionCode,
                            last4: account.last4,
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
                          if (dueText != null)
                            Text(
                              dueText,
                              style: ZType.caption.copyWith(color: c.textMuted),
                            ),
                          const SizedBox(height: ZSpacing.xs),
                          AccountTypeChip(kind: account.kind),
                        ],
                      ),
                    ),
                    const SizedBox(width: ZSpacing.sm),
                    Flexible(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (primary != null)
                            ZMoneyText(
                              text: primary,
                              size: ZMoneySize.body,
                              kind: ZMoneyKind.neutral,
                            ),
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
                if (usedFraction != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      top: ZSpacing.sm,
                      start: _kTileSize + ZSpacing.md,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(ZRadius.pill),
                      child: LinearProgressIndicator(
                        key: const Key('money-credit-bar'),
                        value: usedFraction.clamp(0.0, 1.0),
                        minHeight: 8,
                        // Near or over the limit: warning tone (text stays too).
                        color: usedFraction >= 0.9 ? c.warningText : c.primary,
                        backgroundColor: c.surfaceAlt,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Round bank tile: the bank's short name in a tinted circle (cash and
/// untracked accounts get an icon).
class _Tile extends StatelessWidget {
  const _Tile({required this.account});
  final Account account;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    if (account.kind == AccountKind.cash) {
      return Container(
        width: _kTileSize,
        height: _kTileSize,
        alignment: AlignmentDirectional.center,
        decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
        child: Icon(Icons.payments_rounded, color: c.primary),
      );
    }
    // T-198: the shared avatar (logo, brand colour or neutral initials).
    return ZInstitutionAvatar(
      institutionCode: account.institutionCode,
      label: account.label,
      size: _kTileSize,
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
