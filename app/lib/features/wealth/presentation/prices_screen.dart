// T-121: Prices (S-45). Gold per gram and currency rates to EGP with the
// date, a stale badge (older than 24 h, EC-34), manual override and reset.
// Nothing here sends anything about the user's money (FR-WLT-03).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/l10n/date_format.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/l10n/money_format.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_components.dart';
import '../data/prices_providers.dart';
import '../data/prices_repository.dart';
import '../domain/price_feed.dart';
import 'assets_providers.dart';

class PricesScreen extends ConsumerStatefulWidget {
  const PricesScreen({super.key});

  @override
  ConsumerState<PricesScreen> createState() => _PricesScreenState();
}

class _PricesScreenState extends ConsumerState<PricesScreen> {
  bool _refreshFailed = false;

  Future<void> _refresh() async {
    final repo = await ref.read(pricesRepositoryProvider.future);
    final r = await repo.refresh();
    ref.invalidate(pricesScreenProvider);
    if (!mounted) return;
    setState(() => _refreshFailed = r != PricesApplyResult.applied);
  }

  Future<void> _override(GoldPriceRow row) async {
    final l10n = AppLocalizations.of(context);
    await showZSheet<void>(
      context: context,
      title: l10n.wealthPricesOverrideTitle,
      builder: (_) => _OverrideForm(row: row),
    );
    ref.invalidate(pricesScreenProvider);
    ref.invalidate(assetsOverviewProvider);
  }

  Future<void> _reset(GoldPriceRow row) async {
    final repo = await ref.read(pricesRepositoryProvider.future);
    await repo.clearManualOverride(row.symbol, goldCurrency);
    ref.invalidate(pricesScreenProvider);
    ref.invalidate(assetsOverviewProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final data = ref.watch(pricesScreenProvider);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        title: Semantics(
          header: true,
          child: Text(
            l10n.wealthPricesTitle,
            style: ZType.titleSmall.copyWith(color: c.text),
          ),
        ),
      ),
      body: SafeArea(
        child: data.when(
          loading: () => const _PricesSkeleton(key: Key('prices-loading')),
          error: (_, _) => Padding(
            padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
            child: ZBanner(
              message: l10n.commonErrorLoadFailed,
              tone: ZBannerTone.warning,
              actionLabel: l10n.commonActionTryAgain,
              onAction: () => ref.invalidate(pricesScreenProvider),
            ),
          ),
          data: (d) => RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
              children: _content(context, d),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, PricesScreenData d) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    String money(Money m) =>
        MoneyFormat.format(m, languageCode: lang, digits: digits);
    final asOf = d.status.backendAsOfMs;
    final when = asOf == null
        ? null
        : () {
            final t = DateTime.fromMillisecondsSinceEpoch(
              asOf,
              isUtc: true,
            ).toLocal();
            return l10n.commonDateDateTime(
              ZDateFormat.date(t, lang, digits),
              ZDateFormat.time(t, lang, digits),
            );
          }();
    return [
      if (d.neverFetched) ...[
        ZCard(
          key: const Key('prices-never'),
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
                onPressed: () => _override(d.gold.first),
              ),
            ],
          ),
        ),
        const SizedBox(height: ZSpacing.lg),
      ] else if (when != null)
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.wealthPricesUpdated(when),
                style: ZType.caption.copyWith(color: c.textMuted),
              ),
            ),
            if (d.status.stale)
              ZPill(label: l10n.commonBadgeStale, tone: ZPillTone.warning),
          ],
        ),
      if (_refreshFailed && !d.neverFetched) ...[
        const SizedBox(height: ZSpacing.sm),
        ZBanner(
          message: l10n.wealthPricesFetchFailed,
          tone: ZBannerTone.warning,
        ),
      ],
      const SizedBox(height: ZSpacing.lg),
      Semantics(
        header: true,
        child: Text(
          l10n.wealthPricesGoldSection,
          style: ZType.titleSmall.copyWith(color: c.text),
        ),
      ),
      const SizedBox(height: ZSpacing.sm),
      for (final g in d.gold)
        _GoldRow(
          row: g,
          priceText: g.price == null ? null : money(g.price!.price),
          onOverride: () => _override(g),
          onReset: () => _reset(g),
        ),
      const SizedBox(height: ZSpacing.lg),
      Semantics(
        header: true,
        child: Text(
          l10n.wealthPricesCurrenciesSection(goldCurrency.code),
          style: ZType.titleSmall.copyWith(color: c.text),
        ),
      ),
      const SizedBox(height: ZSpacing.sm),
      Wrap(
        spacing: ZSpacing.lg,
        runSpacing: ZSpacing.sm,
        children: [
          for (final r in d.fx)
            if (r.value != null)
              Semantics(
                container: true,
                label: l10n.wealthPricesCurrencyRowA11y(
                  r.currency.code,
                  money(r.value!),
                ),
                excludeSemantics: true,
                child: Text(
                  '${r.currency.code} ${MoneyFormat.format(r.value!, languageCode: lang, digits: digits, withCurrency: false)}'
                  '${r.stale ? ' · ${l10n.commonBadgeStale}' : ''}',
                  style: ZType.body.copyWith(color: c.text),
                ),
              ),
        ],
      ),
      const SizedBox(height: ZSpacing.lg),
      Text(
        l10n.wealthPricesOverrideNote,
        style: ZType.caption.copyWith(color: c.textMuted),
      ),
      const SizedBox(height: ZSpacing.xs),
      Text(
        l10n.wealthPricesPrivacy,
        style: ZType.caption.copyWith(color: c.textMuted),
      ),
    ];
  }
}

class _GoldRow extends ConsumerWidget {
  const _GoldRow({
    required this.row,
    required this.priceText,
    required this.onOverride,
    required this.onReset,
  });
  final GoldPriceRow row;
  final String? priceText;
  final VoidCallback onOverride;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    final karat = digits.render('${row.karat}');
    final p = row.price;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
      child: ZCard(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: ZSpacing.lg,
          vertical: ZSpacing.sm,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: ZSpacing.sm,
            children: [
              Semantics(
                container: true,
                label: priceText == null
                    ? l10n.commonKaratLabel(karat)
                    : l10n.wealthPricesGoldRowA11y(karat, priceText!),
                excludeSemantics: true,
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: ZSpacing.sm,
                  runSpacing: ZSpacing.xs,
                  children: [
                    Text(
                      l10n.commonKaratLabel(karat),
                      style: ZType.titleSmall.copyWith(color: c.text),
                    ),
                    if (priceText != null) ...[
                      const SizedBox(width: ZSpacing.md),
                      ZMoneyText(text: priceText!),
                    ],
                    if (p != null && p.isManual) ...[
                      const SizedBox(width: ZSpacing.sm),
                      ZPill(
                        label: l10n.wealthPricesYours,
                        tone: ZPillTone.gold,
                      ),
                    ] else if (p != null && p.stale) ...[
                      const SizedBox(width: ZSpacing.sm),
                      ZPill(
                        label: l10n.commonBadgeStale,
                        tone: ZPillTone.warning,
                      ),
                    ],
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (p != null && p.isManual)
                    TextButton(
                      onPressed: onReset,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(
                          ZSpacing.minTarget,
                          ZSpacing.minTarget,
                        ),
                      ),
                      child: Text(l10n.wealthPricesReset),
                    ),
                  TextButton(
                    onPressed: onOverride,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(
                        ZSpacing.minTarget,
                        ZSpacing.minTarget,
                      ),
                    ),
                    child: Text(l10n.wealthPricesOverride),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverrideForm extends ConsumerStatefulWidget {
  const _OverrideForm({required this.row});
  final GoldPriceRow row;

  @override
  ConsumerState<_OverrideForm> createState() => _OverrideFormState();
}

class _OverrideFormState extends ConsumerState<_OverrideForm> {
  final _text = TextEditingController();
  String? _error;
  bool _failed = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _use() async {
    final l10n = AppLocalizations.of(context);
    final m = MoneyFormat.parseInput(_text.text, goldCurrency);
    if (m == null || !m.isPositive) {
      setState(() => _error = l10n.commonValidationAmountRequired);
      return;
    }
    try {
      final repo = await ref.read(pricesRepositoryProvider.future);
      await repo.setManualOverride(
        symbol: widget.row.symbol,
        price: m,
        perUnit: perUnitOfSymbol(widget.row.symbol),
      );
      if (mounted) Navigator.of(context).pop();
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_failed) ...[
          ZBanner(
            message: l10n.commonErrorSaveFailed,
            tone: ZBannerTone.warning,
          ),
          const SizedBox(height: ZSpacing.md),
        ],
        TextField(
          controller: _text,
          autofocus: true,
          textDirection: TextDirection.ltr,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: l10n.wealthPricesOverrideField(goldCurrency.code),
            errorText: _error,
          ),
        ),
        const SizedBox(height: ZSpacing.xs),
        Text(
          l10n.wealthPricesOverrideNote,
          style: ZType.caption.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: ZSpacing.lg),
        ZButton(label: l10n.wealthPricesOverrideUse, onPressed: _use),
        const SizedBox(height: ZSpacing.lg),
      ],
    );
  }
}

class _PricesSkeleton extends StatelessWidget {
  const _PricesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
        child: Column(
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                height: 56,
                margin: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: BorderRadius.circular(ZRadius.card),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
