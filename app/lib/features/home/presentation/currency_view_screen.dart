// T-279 (D-86): the per-currency view of the month, `/home/currency/:iso`.
// The Home hero in one currency only: money in, spent, exchanged out, left,
// its own budget bar, its own feed. Never shows another currency's numbers.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/money_format.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_banner.dart';
import '../../../core/ui/z_card.dart';
import '../application/currency_view_providers.dart';
import 'home_format.dart';
import 'home_screen.dart';
import 'home_widgets.dart';

class CurrencyViewScreen extends ConsumerWidget {
  const CurrencyViewScreen({
    super.key,
    required this.iso,
    this.onSeeAll,
    this.onOpenTransaction,
    this.onOpenBudgetEditor,
  });

  /// The ISO 4217 code from the route; an unknown code shows the empty state.
  final String iso;

  /// "See all": the transactions list filtered to this currency.
  final ValueChanged<Currency>? onSeeAll;
  final ValueChanged<String>? onOpenTransaction;

  /// Opens the budget editor preset to this currency.
  final ValueChanged<Currency>? onOpenBudgetEditor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final known = Currency.tryOf(iso.toUpperCase());
    final model = ref.watch(currencyViewProvider(iso));
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        title: known == null
            ? null
            : Text(
                l.currencyViewTitle(
                  MoneyFormat.currencyLabel(known, languageCode: lang),
                ),
              ),
      ),
      body: model.when(
        loading: () => const Center(
          key: ValueKey('currency-view-loading'),
          child: CircularProgressIndicator(),
        ),
        error: (_, _) => Padding(
          padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
          child: ZBanner(
            key: const ValueKey('currency-view-error'),
            message: l.commonErrorLoadFailed,
            tone: ZBannerTone.error,
            actionLabel: l.commonActionTryAgain,
            onAction: () => ref.invalidate(currencyViewProvider(iso)),
          ),
        ),
        data: (m) => m.isEmpty ? const _Empty() : _Body(model: m, screen: this),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return Center(
      key: const ValueKey('currency-view-empty'),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
        child: Semantics(
          container: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l.currencyViewEmptyTitle,
                textAlign: TextAlign.center,
                style: ZType.title.copyWith(
                  color: c.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: ZSpacing.sm),
              Text(
                l.currencyViewEmptyBody,
                textAlign: TextAlign.center,
                style: ZType.body.copyWith(color: c.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.model, required this.screen});

  final CurrencyViewModel model;
  final CurrencyViewScreen screen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final format = HomeFormat.of(context, ref);
    final paydaySet = ref.watch(homePaydaySetProvider);
    final home = model.home!;
    final currency = model.currency!;
    final figures = model.figures!;
    void openEditor() => screen.onOpenBudgetEditor?.call(currency);
    return ListView(
      key: const ValueKey('currency-view-scroll'),
      padding: const EdgeInsetsDirectional.fromSTEB(
        ZSpacing.screen,
        ZSpacing.sm,
        ZSpacing.screen,
        ZSpacing.fabClearance,
      ),
      children: [
        HomeHero(
          figures: figures,
          model: home,
          format: format,
          paydaySet: paydaySet,
          onSetBudget: screen.onOpenBudgetEditor == null ? null : openEditor,
        ),
        if (model.offerVisible) ...[
          const SizedBox(height: ZSpacing.md),
          ZBanner(
            key: const ValueKey('currency-view-offer'),
            message: l.currencyViewBudgetOffer(
              MoneyFormat.currencyLabel(
                currency,
                languageCode: format.languageCode,
              ),
            ),
            actionLabel: l.commonActionYes,
            onAction: () {
              unawaited(markBudgetOfferHandled(ref, model.offerSlug!));
              openEditor();
            },
            onDismiss: () =>
                unawaited(markBudgetOfferHandled(ref, model.offerSlug!)),
            dismissSemanticsLabel: l.commonActionDismiss,
          ),
        ],
        const SizedBox(height: ZSpacing.lg),
        if (model.feed.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  l.homeFeedTitle,
                  style: ZType.title.copyWith(
                    color: c.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                key: const ValueKey('currency-view-see-all'),
                onPressed: screen.onSeeAll == null
                    ? null
                    : () => screen.onSeeAll!(currency),
                style: TextButton.styleFrom(
                  foregroundColor: c.primary,
                  minimumSize: const Size(
                    ZSpacing.minTarget,
                    ZSpacing.minTarget,
                  ),
                ),
                child: Text(l.commonActionSeeAll),
              ),
            ],
          ),
          ZCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < model.feed.length; i++)
                  HomeFeedRow(
                    key: ValueKey('currency-row-${model.feed[i].record.id}'),
                    item: model.feed[i],
                    format: format,
                    today: home.today,
                    showDivider: i < model.feed.length - 1,
                    onTap: screen.onOpenTransaction,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
