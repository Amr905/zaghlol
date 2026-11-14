// T-121: the assets section of the Money tab (S-40). Free users see a locked
// preview; Gold users see their assets with gold in its native unit, stale
// badges, certificate payouts and "Estimated value" tags.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/daos/assets_dao.dart';
import '../../../core/l10n/date_format.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/l10n/money_format.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_components.dart';
import '../../gold/application/gating.dart';
import 'asset_format.dart';
import 'assets_providers.dart';

class AssetsSection extends ConsumerWidget {
  const AssetsSection({
    super.key,
    this.onAddAsset,
    this.onOpenPrices,
    this.onOpenPaywall,
  });

  final VoidCallback? onAddAsset;
  final VoidCallback? onOpenPrices;
  final VoidCallback? onOpenPaywall;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final gold = ref.watch(entitlementStateProvider).isGold;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Semantics(
                header: true,
                child: Text(
                  l10n.accountsOverviewAssetsTitle,
                  style: ZType.titleSmall.copyWith(color: c.text),
                ),
              ),
            ),
            const SizedBox(width: ZSpacing.sm),
            if (!gold) ZChip(label: l10n.commonGoldBadge, selected: true),
            if (gold) ...[
              const Spacer(),
              Flexible(
                child: TextButton(
                  onPressed: onOpenPrices,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(
                      ZSpacing.minTarget,
                      ZSpacing.minTarget,
                    ),
                  ),
                  child: Text(l10n.accountsOverviewPrices),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: ZSpacing.sm),
        if (!gold)
          Semantics(
            button: true,
            label: l10n.commonGoldLockedA11y,
            child: ZCard(
              onTap: onOpenPaywall,
              child: Row(
                children: [
                  Icon(Icons.lock_outline_rounded, color: c.accentDark),
                  const SizedBox(width: ZSpacing.md),
                  Expanded(
                    child: Text(
                      l10n.accountsOverviewAssetsLocked,
                      style: ZType.bodySmall.copyWith(color: c.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          _GoldBody(onAddAsset: onAddAsset),
      ],
    );
  }
}

class _GoldBody extends ConsumerWidget {
  const _GoldBody({this.onAddAsset});
  final VoidCallback? onAddAsset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final overview = ref.watch(assetsOverviewProvider);
    return overview.when(
      loading: () => const _AssetsSkeleton(key: Key('assets-loading')),
      error: (_, _) => ZBanner(
        message: l10n.commonErrorLoadFailed,
        tone: ZBannerTone.warning,
        actionLabel: l10n.commonActionTryAgain,
        onAction: () => ref.invalidate(assetsOverviewProvider),
      ),
      data: (data) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.rows.isEmpty)
            ZCard(
              child: Column(
                children: [
                  Text(
                    l10n.wealthOverviewAssetsEmpty,
                    textAlign: TextAlign.center,
                    style: ZType.bodySmall.copyWith(
                      color: ZColors.of(context).textMuted,
                    ),
                  ),
                  const SizedBox(height: ZSpacing.md),
                  ZButton(
                    label: l10n.wealthAssetTitleAdd,
                    onPressed: onAddAsset,
                  ),
                ],
              ),
            )
          else ...[
            _GoldUnits(units: data.goldUnits),
            for (final r in data.rows)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
                child: _AssetRow(view: r),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: onAddAsset,
                style: TextButton.styleFrom(
                  minimumSize: const Size(
                    ZSpacing.minTarget,
                    ZSpacing.minTarget,
                  ),
                ),
                child: Text(l10n.wealthAssetTitleAdd),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Net worth units for gold: one line per karat and for coins, native units.
class _GoldUnits extends ConsumerWidget {
  const _GoldUnits({required this.units});
  final List<UnitNetWorth> units;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (units.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    final lines = <String>[];
    for (final u in units) {
      if (u.unit == GoldSymbols.coin) {
        final count = u.netMinor ~/ 1000;
        lines.add(l10n.wealthOverviewUnitCoins(count, digits.render('$count')));
      } else {
        final karat = RegExp(r'^XAU(\d+)_G$').firstMatch(u.unit)?.group(1);
        if (karat == null) continue;
        lines.add(
          l10n.wealthOverviewUnitGold(
            digits.render(karat),
            l10n.commonUnitGrams(formatMilli(u.netMinor, digits)),
          ),
        );
      }
    }
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
      child: Semantics(
        container: true,
        label: l10n.wealthOverviewUnitsA11y(lines.join(', ')),
        excludeSemantics: true,
        child: Wrap(
          spacing: ZSpacing.sm,
          runSpacing: ZSpacing.xs,
          children: [
            for (final line in lines)
              Text(line, style: ZType.label.copyWith(color: c.text)),
          ],
        ),
      ),
    );
  }
}

class _AssetRow extends ConsumerWidget {
  const _AssetRow({required this.view});
  final AssetRowView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    String money(Money m) =>
        MoneyFormat.format(m, languageCode: lang, digits: digits);
    final a = view.row;
    final cur = a.currency == null ? null : Currency.tryOf(a.currency!);

    String title = a.name;
    String? sub;
    String? sub2;
    String? trailing;
    var estimated = false;
    switch (a.type) {
      case AssetType.gold:
        title = l10n.wealthOverviewGoldTitle(digits.render('${a.karat ?? 0}'));
        final grams = l10n.commonUnitGrams(
          formatMilli(a.quantityMilli ?? 0, digits),
        );
        sub = view.goldValue == null
            ? grams
            : l10n.wealthOverviewGoldSub(grams, money(view.goldValue!));
      case AssetType.goldCoin:
        title = l10n.commonKaratCoin;
        final n = (a.quantityMilli ?? 0) ~/ 1000;
        sub = l10n.wealthOverviewUnitCoins(n, digits.render('$n'));
        if (view.goldValue != null) {
          sub = l10n.wealthOverviewGoldSub(sub, money(view.goldValue!));
        }
      case AssetType.certificate:
        title = l10n.wealthOverviewCertTitle(a.name);
        final principal = a.principalMinor;
        if (cur != null && principal != null) {
          sub = l10n.wealthOverviewCertSub(
            formatBp(a.rateBp ?? 0, digits),
            money(Money.fromStorage(principal, a.currency!)),
          );
        }
        final p = view.nextPayout;
        if (p != null && p.amount != null) {
          sub2 = l10n.wealthOverviewCertPayout(
            ZDateFormat.date(
              DateTime(p.date.year, p.date.month, p.date.day),
              lang,
              digits,
            ),
            money(p.amount!),
          );
        }
      case AssetType.cash:
        title = a.currency ?? a.name;
        if (a.manualValueMinor != null && a.currency != null) {
          trailing = money(Money.fromStorage(a.manualValueMinor!, a.currency!));
        }
        if (view.noRate && cur != null) {
          sub = l10n.wealthOverviewNoRate(cur.code);
        }
      default:
        estimated = true;
        final v = a.manualValueMinor ?? a.principalMinor;
        if (v != null && a.currency != null) {
          trailing = money(Money.fromStorage(v, a.currency!));
        }
    }
    final semantics = [
      l10n.wealthOverviewAssetRowA11y(title, trailing ?? sub ?? ''),
      if (estimated) l10n.wealthOverviewManualValue,
      if (view.goldStale) l10n.commonBadgeStaleA11y,
    ].join(', ');
    return Semantics(
      container: true,
      label: semantics,
      excludeSemantics: true,
      child: ZCard(
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
                      title,
                      style: ZType.titleSmall.copyWith(color: c.text),
                    ),
                    if (sub != null)
                      Text(
                        sub,
                        style: ZType.caption.copyWith(color: c.textMuted),
                      ),
                    if (sub2 != null)
                      Text(
                        sub2,
                        style: ZType.caption.copyWith(color: c.textMuted),
                      ),
                    if (estimated || view.goldStale)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          top: ZSpacing.xs,
                        ),
                        child: ZPill(
                          label: view.goldStale
                              ? l10n.commonBadgeStale
                              : l10n.wealthOverviewManualValue,
                          tone: view.goldStale
                              ? ZPillTone.warning
                              : ZPillTone.neutral,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: ZSpacing.sm),
                Flexible(child: ZMoneyText(text: trailing)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AssetsSkeleton extends StatelessWidget {
  const _AssetsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return ExcludeSemantics(
      child: Column(
        children: [
          for (var i = 0; i < 2; i++)
            Container(
              height: 64,
              margin: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(ZRadius.card),
              ),
            ),
        ],
      ),
    );
  }
}
