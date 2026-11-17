// T-168: Zakah (S-46), behind the `zakah` flag and Zaghlol Gold. Per-lot dues
// in each lot's own unit (never one cross-currency total), hawl progress,
// nisab status, payment status, and the disclaimer always visible
// (FR-ZAK-05). Calm tone: no mascot line, no emoji. When the flag is off the
// screen renders nothing and reads no data (the data stays, EC-49).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/flags/feature_flags.dart';
import '../../../core/flags/flags_providers.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/l10n/digits_mode.dart';
import '../../../core/l10n/money_format.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_components.dart';
import '../../gold/application/gating.dart';
import '../../wealth/presentation/asset_format.dart';
import '../data/zakah_providers.dart';
import '../data/zakah_repository.dart';

class ZakahScreen extends ConsumerWidget {
  const ZakahScreen({
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
    // Entirely hidden when the flag is off: nothing else is read.
    if (!ref.watch(featureFlagProvider(FeatureFlag.zakah))) {
      return const SizedBox.shrink(key: Key('zakah-hidden'));
    }
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final gold = ref.watch(entitlementStateProvider).isGold;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        title: Semantics(
          header: true,
          child: Text(
            l10n.zakahMainTitle,
            style: ZType.titleSmall.copyWith(color: c.text),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
          children: [
            const _Disclaimer(),
            const SizedBox(height: ZSpacing.lg),
            if (!gold)
              Semantics(
                button: true,
                label: l10n.commonGoldLockedA11y,
                child: ZCard(
                  key: const Key('zakah-locked'),
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
              _Body(onAddAsset: onAddAsset, onOpenPrices: onOpenPrices),
          ],
        ),
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return Semantics(
      container: true,
      child: ZCard(
        key: const Key('zakah-disclaimer'),
        color: c.primaryContainer,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.zakahMainDisclaimerSummary,
              style: ZType.titleSmall.copyWith(color: c.onPrimaryContainer),
            ),
            const SizedBox(height: ZSpacing.xs),
            Text(
              l10n.zakahMainDisclaimer,
              style: ZType.bodySmall.copyWith(color: c.onPrimaryContainer),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({this.onAddAsset, this.onOpenPrices});
  final VoidCallback? onAddAsset;
  final VoidCallback? onOpenPrices;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(zakahViewProvider);
    return view.when(
      loading: () => const _Skeleton(key: Key('zakah-loading')),
      error: (_, _) => ZBanner(
        message: l10n.commonErrorLoadFailed,
        tone: ZBannerTone.warning,
        actionLabel: l10n.commonActionTryAgain,
        onAction: () => ref.invalidate(zakahViewProvider),
      ),
      data: (v) =>
          _Content(view: v, onAddAsset: onAddAsset, onOpenPrices: onOpenPrices),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Column(
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(ZRadius.md),
              ),
              child: const SizedBox(height: 88, width: double.infinity),
            ),
          ),
      ],
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({required this.view, this.onAddAsset, this.onOpenPrices});
  final ZakahView view;
  final VoidCallback? onAddAsset;
  final VoidCallback? onOpenPrices;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    if (view.isEmpty) {
      return ZCard(
        key: const Key('zakah-empty'),
        child: Column(
          children: [
            Text(
              l10n.zakahMainEmptyTitle,
              textAlign: TextAlign.center,
              style: ZType.bodySmall.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: ZSpacing.md),
            ZButton(label: l10n.zakahMainEmptyAdd, onPressed: onAddAsset),
          ],
        ),
      );
    }
    final r = view.result;
    final nisab = r.nisab;
    final grams = l10n.commonUnitGrams(
      formatMilli(view.rules.nisabGoldMilligrams, digits),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (view.stale) ...[
          ZBanner(message: l10n.zakahMainStaleNote, tone: ZBannerTone.warning),
          const SizedBox(height: ZSpacing.md),
        ],
        _NisabCard(view: view, grams: grams, onOpenPrices: onOpenPrices),
        const SizedBox(height: ZSpacing.md),
        if (r.state == ZakahNisabState.belowNisab)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
            child: Text(
              l10n.zakahMainNisabNotReachedBody,
              key: const Key('zakah-below'),
              style: ZType.bodySmall.copyWith(color: c.textMuted),
            ),
          ),
        if (r.dueByUnit.isNotEmpty) _Totals(view: view),
        for (final lv in view.lots)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
            child: _LotCard(view: view, lot: lv),
          ),
        const SizedBox(height: ZSpacing.md),
        _How(view: view, grams: grams, nisabKnown: nisab != null),
      ],
    );
  }
}

String nativeText(
  AppLocalizations l10n,
  String unit,
  int amount,
  String lang,
  DigitsMode digits,
) {
  if (unit == GoldSymbols.coin) {
    final n = amount ~/ 1000;
    return l10n.wealthOverviewUnitCoins(n, digits.render('$n'));
  }
  if (GoldSymbols.isGold(unit)) {
    return l10n.commonUnitGrams(formatMilli(amount, digits));
  }
  return MoneyFormat.format(
    Money.fromStorage(amount, unit),
    languageCode: lang,
    digits: digits,
  );
}

class _NisabCard extends ConsumerWidget {
  const _NisabCard({
    required this.view,
    required this.grams,
    this.onOpenPrices,
  });
  final ZakahView view;
  final String grams;
  final VoidCallback? onOpenPrices;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    final r = view.result;
    if (r.state == ZakahNisabState.needsPrices) {
      return ZCard(
        key: const Key('zakah-needs-prices'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.wealthPricesNeverTitle,
              style: ZType.titleSmall.copyWith(color: c.text),
            ),
            const SizedBox(height: ZSpacing.xs),
            Text(
              l10n.wealthPricesNeverBody,
              style: ZType.bodySmall.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: ZSpacing.md),
            ZButton(
              label: l10n.wealthPricesEnterManually,
              variant: ZButtonVariant.secondary,
              onPressed: onOpenPrices,
            ),
          ],
        ),
      );
    }
    final reached = r.state == ZakahNisabState.eligible;
    final value = MoneyFormat.format(
      r.nisab!,
      languageCode: lang,
      digits: digits,
    );
    return ZCard(
      key: const Key('zakah-nisab'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                reached
                    ? Icons.check_circle_outline
                    : Icons.remove_circle_outline,
                color: reached ? c.primary : c.textMuted,
              ),
              const SizedBox(width: ZSpacing.sm),
              Expanded(
                child: Text(
                  reached
                      ? l10n.zakahMainNisabReached
                      : l10n.zakahMainNisabNotReached,
                  style: ZType.titleSmall.copyWith(color: c.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: ZSpacing.xs),
          Text(
            l10n.zakahMainNisabInfo(grams, digits.render('24'), value),
            style: ZType.bodySmall.copyWith(color: c.textMuted),
          ),
        ],
      ),
    );
  }
}

/// What is still due per unit. Units never merge (one line per unit).
class _Totals extends ConsumerWidget {
  const _Totals({required this.view});
  final ZakahView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    final units = view.result.dueByUnit.keys.toList()..sort();
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
      child: Column(
        key: const Key('zakah-totals'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final u in units)
            Text(
              l10n.zakahMainDue(
                nativeText(l10n, u, view.result.dueByUnit[u]!, lang, digits),
              ),
              style: ZType.titleSmall.copyWith(color: c.text),
            ),
        ],
      ),
    );
  }
}

class _LotCard extends ConsumerWidget {
  const _LotCard({required this.view, required this.lot});
  final ZakahView view;
  final ZakahLotView lot;

  String _title(AppLocalizations l10n, String lang, DigitsMode digits) {
    final l = lot.lot;
    final amount = nativeText(l10n, l.unit, l.amount, lang, digits);
    switch (l.kind) {
      case ZakahLotKind.gold:
        if (l.unit == GoldSymbols.coin) {
          return l10n.zakahMainLotCoin(lot.info.title, amount);
        }
        return l10n.zakahMainLotGold(
          digits.render('${lot.info.karat ?? ''}'),
          amount,
        );
      case ZakahLotKind.cash:
        return l10n.zakahMainLotCash(l.unit, amount);
      case ZakahLotKind.stock:
        return l10n.zakahMainLotInvest(l.unit, amount);
      case ZakahLotKind.certificate:
        return l10n.zakahMainLotCertificate(amount);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    final r = lot.result;
    final title = _title(l10n, lang, digits);
    final due = r.status == ZakahLotStatus.due;
    final total = view.rules.hawlDays;
    final String hawl;
    if (r.hawlDaysElapsed >= total) {
      hawl = l10n.zakahMainHawlDone;
    } else {
      hawl = l10n.zakahMainHawlProgress(
        digits.render('${r.hawlDaysElapsed}'),
        digits.render('$total'),
      );
    }
    final lines = <String>[hawl];
    if (r.status == ZakahLotStatus.notDue ||
        (r.status == ZakahLotStatus.belowNisab && r.daysRemaining > 0)) {
      final h = hijriFromCivil(r.dueOn);
      lines.add(
        l10n.zakahMainDueIn(
          r.daysRemaining,
          digits.render('${r.daysRemaining}'),
        ),
      );
      lines.add(l10n.zakahMainDueHijri(digits.render(h.toIso())));
    }
    String? dueLine;
    String? cost;
    if (due && r.dueNative > 0) {
      dueLine = l10n.zakahMainDue(
        nativeText(l10n, lot.lot.unit, r.dueNative, lang, digits),
      );
      final k = r.costOfDue;
      if (k != null && k.currency != lot.lot.unit.toCurrencyOrNull) {
        cost = l10n.zakahMainDueCost(
          MoneyFormat.format(k, languageCode: lang, digits: digits),
        );
      }
    }
    final status = switch (r.payment) {
      ZakahPayment.paid => l10n.zakahMainStatusPaid,
      ZakahPayment.partial => l10n.zakahMainStatusPartial,
      ZakahPayment.pending => l10n.zakahMainStatusPending,
      null => null,
    };
    return Semantics(
      container: true,
      label: l10n.zakahMainLotA11y(title, status ?? '', dueLine ?? ''),
      excludeSemantics: true,
      child: ZCard(
        key: Key('zakah-lot-${lot.lot.id}'),
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: ZSpacing.lg,
          vertical: ZSpacing.md,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: ZType.titleSmall.copyWith(color: c.text)),
              for (final line in lines)
                Text(line, style: ZType.caption.copyWith(color: c.textMuted)),
              if (dueLine != null) ...[
                const SizedBox(height: ZSpacing.xs),
                Text(dueLine, style: ZType.titleSmall.copyWith(color: c.text)),
                if (cost != null)
                  Text(cost, style: ZType.caption.copyWith(color: c.textMuted)),
              ],
              if (status != null) ...[
                const SizedBox(height: ZSpacing.sm),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    key: Key('zakah-status-${lot.lot.id}'),
                    onPressed: () => _setStatus(context, ref),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(
                        ZSpacing.minTarget,
                        ZSpacing.minTarget,
                      ),
                    ),
                    child: Text('${l10n.zakahMainStatusLabel}: $status'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setStatus(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showZSheet<bool>(
      context: context,
      title: l10n.zakahMainStatusLabel,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ZButton(
            key: const Key('zakah-mark-paid'),
            label: l10n.zakahMainStatusPaid,
            expand: true,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
          const SizedBox(height: ZSpacing.sm),
          ZButton(
            key: const Key('zakah-mark-pending'),
            label: l10n.zakahMainStatusPending,
            expand: true,
            variant: ZButtonVariant.secondary,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
        ],
      ),
    );
    if (choice == null) return;
    final repo = await ref.read(zakahRepositoryProvider.future);
    await repo.setPaid(lot, paid: choice);
    ref.invalidate(zakahViewProvider);
  }
}

class _How extends ConsumerWidget {
  const _How({
    required this.view,
    required this.grams,
    required this.nisabKnown,
  });
  final ZakahView view;
  final String grams;
  final bool nisabKnown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    final pct =
        '${digits.render('2')}${lang == 'ar' ? '٫' : '.'}${digits.render('5')}%';
    return Column(
      key: const Key('zakah-how'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.zakahMainHowTitle,
            style: ZType.titleSmall.copyWith(color: c.text),
          ),
        ),
        const SizedBox(height: ZSpacing.xs),
        for (final t in [
          l10n.zakahMainHowNisab(grams, digits.render('24')),
          l10n.zakahMainHowHawl(digits.render('${view.rules.hawlDays}')),
          l10n.zakahMainHowRate(pct),
          l10n.zakahMainHowDebts,
        ])
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.xs),
            child: Text(t, style: ZType.bodySmall.copyWith(color: c.textMuted)),
          ),
      ],
    );
  }
}

extension on String {
  /// Currency for a unit code, or null for a gold symbol.
  Currency? get toCurrencyOrNull => Currency.tryOf(this);
}
