// T-170 S-51: Smart ROI tips (FR-ROI-01..04, D-38). General advice only: a
// tip names a KIND of product, never a bank, fund or brand. Every tip carries
// the "not financial advice" line and its figures in its own currency;
// currencies are never summed (a switcher picks one). The whole view is
// absent when the `smart_roi` flag is off, and locked (preview + Gold prompt)
// for Free users (A-21).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/l10n/digits_mode.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_banner.dart';
import '../../../core/ui/z_button.dart';
import '../../../core/ui/z_card.dart';
import '../../../core/ui/z_currency_switcher.dart';
import '../../gold/application/gating.dart';
import '../../insights/presentation/charts/charts_providers.dart';
import '../../mascot/presentation/zaghlol_avatar.dart';
import '../../transactions/presentation/list/txn_row.dart' show TxnFmt;
import '../data/roi_providers.dart' show roiSuggestionsProvider;
import 'roi_tips_providers.dart';

/// The `years` select value of `roiTipsProjection` (year 1 and year 2).
const String _twoYears = 'two';

/// S-51 as a full screen (title "Tips"). The Zaghlol tab embeds [RoiTipsView]
/// in its Tips segment instead.
class RoiTipsScreen extends ConsumerWidget {
  const RoiTipsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Flag off: nothing, not even an app bar.
    if (!ref.watch(roiTipsEnabledProvider)) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: ZColors.of(context).bg,
      appBar: AppBar(title: Text(l.chatMainSegTips)),
      body: const SafeArea(child: RoiTipsView()),
    );
  }
}

/// The tips content: disclaimer, currency switcher and the tip cards.
class RoiTipsView extends ConsumerWidget {
  const RoiTipsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(roiTipsEnabledProvider)) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    if (!ref.watch(entitlementStateProvider).isGold) {
      return _Locked(
        message: l.roiTipsLockedBody,
        action: l.commonGoldUnlock,
        onUnlock: () =>
            ref.read(paywallTriggerProvider)(GoldCapability.deepCoaching),
      );
    }
    final currencies = ref.watch(chartsCurrenciesProvider);
    return currencies.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _Message(
        title: l.chatAnswerError,
        action: l.commonActionTryAgain,
        onAction: () => ref.invalidate(chartsCurrenciesProvider),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const _Empty();
        }
        final chosen = ref.watch(roiCurrencyProvider);
        final current = list.firstWhere(
          (c) => c.code == chosen,
          orElse: () => list.first,
        );
        return _Body(currencies: list, current: current);
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.currencies, required this.current});

  final List<Currency> currencies;
  final Currency current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final tips = ref.watch(roiVisibleTipsProvider(current));
    return ListView(
      padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
      children: [
        const _Disclaimer(),
        if (currencies.length > 1) ...[
          const SizedBox(height: ZSpacing.md),
          ZCurrencySwitcher(
            codes: [for (final c in currencies) c.code],
            selected: current.code,
            onSelected: ref.read(roiCurrencyProvider.notifier).select,
          ),
        ],
        const SizedBox(height: ZSpacing.lg),
        tips.when(
          loading: () => const Padding(
            padding: EdgeInsetsDirectional.all(ZSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => _Message(
            title: l.chatAnswerError,
            action: l.commonActionTryAgain,
            onAction: () => ref.invalidate(roiSuggestionsProvider(current)),
          ),
          data: (list) => list.isEmpty
              ? const _Empty()
              : Column(
                  children: [
                    for (final tip in list) ...[
                      RoiTipCard(tip: tip),
                      const SizedBox(height: ZSpacing.md),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

/// The always-visible disclaimer (FR-ROI-02): the Egyptian summary above the
/// plain-standard-Arabic text.
class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return Semantics(
      container: true,
      child: ZCard(
        color: c.surfaceAlt,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: c.textMuted, size: 20),
            const SizedBox(width: ZSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.roiTipsDisclaimerSummary,
                    style: ZType.label.copyWith(color: c.text),
                  ),
                  const SizedBox(height: ZSpacing.xs),
                  Text(
                    l.roiTipsDisclaimer,
                    style: ZType.bodySmall.copyWith(color: c.textMuted),
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

/// One tip: title, body with its figures, the two-year projection, the
/// disclaimer line, and the two actions.
class RoiTipCard extends ConsumerWidget {
  const RoiTipCard({super.key, required this.tip});

  final RoiSuggestion tip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    final fmt = TxnFmt(lang, digits);
    final text = roiTipText(l, tip, fmt);
    final projection = l.roiTipsProjection(
      _twoYears,
      fmt.money(tip.year1Saving),
      fmt.money(tip.year2Saving),
    );
    return Semantics(
      container: true,
      child: ZCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_iconOf(tip.rule), color: c.primary),
                const SizedBox(width: ZSpacing.md),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      text.title,
                      style: ZType.titleSmall.copyWith(color: c.text),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: ZSpacing.sm),
            Text(text.body, style: ZType.body.copyWith(color: c.text)),
            const SizedBox(height: ZSpacing.sm),
            Text(projection, style: ZType.label.copyWith(color: c.primary)),
            const SizedBox(height: ZSpacing.sm),
            Text(
              l.roiTipsDisclaimerSummary,
              style: ZType.caption.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: ZSpacing.md),
            Wrap(
              spacing: ZSpacing.sm,
              runSpacing: ZSpacing.sm,
              children: [
                ZButton(
                  label: l.roiTipsShare,
                  variant: ZButtonVariant.secondary,
                  icon: Icons.ios_share,
                  onPressed: () =>
                      ref.read(roiShareOpenerProvider)(context, tip),
                ),
                ZButton(
                  label: l.roiTipsNotForMe,
                  variant: ZButtonVariant.text,
                  onPressed: () => _dismiss(context, ref),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _dismiss(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final notifier = ref.read(roiDismissedProvider.notifier)..dismiss(tip);
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l.roiTipsDismissed),
          action: SnackBarAction(
            label: l.commonActionUndo,
            onPressed: () => notifier.restore(tip),
          ),
        ),
      );
  }
}

/// The localized title and body of [tip]. Money goes through the shared
/// formatter (locale digits, currency label).
({String title, String body}) roiTipText(
  AppLocalizations l,
  RoiSuggestion tip,
  TxnFmt fmt,
) {
  String m(Money? v) => v == null ? '' : fmt.money(v);
  final monthly = m(tip.monthly);
  final alt = m(tip.altMonthly);
  return switch (tip.rule) {
    RoiRule.coffeeMachine => (
      title: l.roiRuleCoffeeTitle,
      body: l.roiRuleCoffeeBody(monthly, alt),
    ),
    RoiRule.cookingAppliance => (
      title: l.roiRuleDeliveryTitle,
      body: l.roiRuleDeliveryBody(monthly, alt),
    ),
    RoiRule.waterFilter => (
      title: l.roiRuleWaterTitle,
      body: l.roiRuleWaterBody(monthly, alt),
    ),
    RoiRule.idleCash => (
      title: l.roiRuleIdleCashTitle,
      body: l.roiRuleIdleCashBody(m(tip.idle), _rate(tip.exampleRateBp, fmt)),
    ),
    RoiRule.regularRides => (
      title: l.roiRuleCommuteTitle,
      body: l.roiRuleCommuteBody(monthly, alt),
    ),
    RoiRule.cardInterest => (
      title: l.roiRuleCardInterestTitle,
      body: l.roiRuleCardInterestBody(
        m(tip.balance),
        _rate(tip.exampleRateBp, fmt),
      ),
    ),
    RoiRule.subscriptions => (
      title: l.roiRuleSubscriptionsTitle,
      body: l.roiRuleSubscriptionsBody(monthly, alt),
    ),
    RoiRule.bulkStaples => (
      title: l.roiRuleStaplesTitle,
      body: l.roiRuleStaplesBody(monthly, alt),
    ),
  };
}

/// Basis points as a percent with locale digits: 2200 -> "22%", 350 -> "3.5%".
String _rate(int? bp, TxnFmt fmt) {
  if (bp == null) return '';
  final whole = bp ~/ 100;
  final frac = bp % 100;
  final western = fmt.digits == DigitsMode.western;
  final sep = western ? '.' : '٫';
  final pct = western ? '%' : '٪';
  final fracText = frac == 0
      ? ''
      : '$sep${fmt.digits.render(frac.toString().padLeft(2, '0').replaceFirst(RegExp(r'0$'), ''))}';
  return '${fmt.digits.render('$whole')}$fracText$pct';
}

IconData _iconOf(RoiRule rule) => switch (rule) {
  RoiRule.coffeeMachine => Icons.coffee_outlined,
  RoiRule.cookingAppliance => Icons.soup_kitchen_outlined,
  RoiRule.waterFilter => Icons.water_drop_outlined,
  RoiRule.idleCash => Icons.savings_outlined,
  RoiRule.regularRides => Icons.directions_car_outlined,
  RoiRule.cardInterest => Icons.credit_card,
  RoiRule.subscriptions => Icons.subscriptions_outlined,
  RoiRule.bulkStaples => Icons.shopping_basket_outlined,
};

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(ZSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ZaghlolAvatar(moment: ZaghlolMoment.professor, size: 96),
            const SizedBox(height: ZSpacing.lg),
            Text(
              l.roiTipsEmptyTitle,
              textAlign: TextAlign.center,
              style: ZType.title.copyWith(color: c.text),
            ),
            const SizedBox(height: ZSpacing.sm),
            Text(
              l.roiTipsEmptyBody,
              textAlign: TextAlign.center,
              style: ZType.body.copyWith(color: c.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Locked extends StatelessWidget {
  const _Locked({
    required this.message,
    required this.action,
    required this.onUnlock,
  });

  final String message;
  final String action;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.all(ZSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ZaghlolAvatar(moment: ZaghlolMoment.professor, size: 96),
            const SizedBox(height: ZSpacing.lg),
            Text(
              message,
              textAlign: TextAlign.center,
              style: ZType.title.copyWith(color: c.text),
            ),
            const SizedBox(height: ZSpacing.lg),
            ZButton(label: action, onPressed: onUnlock),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.title,
    required this.action,
    required this.onAction,
  });

  final String title;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
      child: ZBanner(
        message: title,
        tone: ZBannerTone.error,
        actionLabel: action,
        onAction: onAction,
      ),
    );
  }
}
