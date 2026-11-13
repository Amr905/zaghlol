// T-084 / S-42: categories x cards for the current cycle in one currency
// (FR-CARD-03). Up to six cards (UX-A-03); tabular figures; the table scrolls
// sideways when it is wider than the screen. A cell opens S-11 filtered by
// card and category. Cards in another currency appear only when that
// currency is picked; nothing is summed across currencies.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/l10n/locale_providers.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/z_components.dart';
import '../../../transactions/presentation/list/txn_list_providers.dart';
import '../../../transactions/presentation/list/txn_row.dart';
import 'card_detail_providers.dart';

const double _labelWidth = 120;
const double _cellWidth = 104;

class CompareCardsScreen extends ConsumerWidget {
  const CompareCardsScreen({super.key, this.onOpenCell});

  /// Cell tap: card and category (null: uncategorized). The caller sets the
  /// filters and opens S-11.
  final void Function(String accountId, String? categoryId)? onOpenCell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final data = ref.watch(compareDataProvider);
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
                  constraints: const BoxConstraints(
                    minWidth: ZSpacing.minTarget,
                    minHeight: ZSpacing.minTarget,
                  ),
                  icon: const BackButtonIcon(),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      l.accountsCompareTitle,
                      style: ZType.headline.copyWith(color: c.text),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: ZSpacing.md),
            ...data.when(
              loading: () => [
                SizedBox(
                  key: const Key('compare-loading'),
                  height: 160,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      borderRadius: BorderRadius.circular(ZRadius.card),
                    ),
                  ),
                ),
              ],
              error: (_, _) => [
                ZBanner(
                  message: l.commonErrorLoadFailed,
                  tone: ZBannerTone.warning,
                ),
              ],
              data: (d) => _content(context, ref, d),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, WidgetRef ref, CompareData d) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final fmt = TxnFmt(lang, ref.watch(digitsModeProvider(lang)));
    final lookups = ref.watch(txnLookupsProvider).value;
    String catName(String? id) {
      final cat = lookups?.category(id);
      return cat == null ? '' : categoryName(cat, lang);
    }

    return [
      if (d.currencies.length > 1) ...[
        Wrap(
          spacing: ZSpacing.sm,
          children: [
            for (final x in d.currencies)
              ZChip(
                label: x.code,
                selected: x == d.currency,
                onTap: () =>
                    ref.read(compareCurrencyProvider.notifier).select(x.code),
              ),
          ],
        ),
        const SizedBox(height: ZSpacing.sm),
        Text(
          l.accountsCompareOtherCurrency,
          style: ZType.caption.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: ZSpacing.md),
      ],
      if (d.isEmpty)
        ZCard(
          key: const Key('compare-empty'),
          child: Text(
            l.accountsCompareEmpty,
            textAlign: TextAlign.center,
            style: ZType.body.copyWith(color: c.textMuted),
          ),
        )
      else ...[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            key: const Key('compare-table'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Row(
                header: true,
                label: '',
                cells: [for (final card in d.cards) _Cell(text: card.label)],
              ),
              for (final id in d.categoryIds)
                _Row(
                  label: catName(id),
                  cells: [
                    for (final card in d.cards)
                      _Cell(
                        text: card.byCategory[id] == null
                            ? '–'
                            : fmt.money(card.byCategory[id]!),
                        semantics: card.byCategory[id] == null
                            ? null
                            : l.accountsCompareCellA11y(
                                fmt.money(card.byCategory[id]!),
                                card.label,
                                catName(id),
                              ),
                        onTap: card.byCategory[id] == null || onOpenCell == null
                            ? null
                            : () => onOpenCell!(card.accountId, id),
                      ),
                  ],
                ),
              _Row(
                label: l.accountsCompareTotal,
                total: true,
                cells: [
                  for (final card in d.cards)
                    _Cell(text: fmt.money(card.spend), total: true),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: ZSpacing.lg),
        ZButton(
          key: const Key('compare-choose'),
          label: l.accountsCompareChoose,
          variant: ZButtonVariant.secondary,
          onPressed: () => _choose(context, ref, d, fmt),
        ),
      ],
    ];
  }

  Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    CompareData d,
    TxnFmt fmt,
  ) async {
    final l = AppLocalizations.of(context);
    final picked = await showZSheet<Set<String>>(
      context: context,
      title: l.accountsCompareChoose,
      builder: (_) => _ChooseBody(
        data: d,
        hint: l.accountsCompareMax(
          compareMaxCards,
          fmt.digits.render('$compareMaxCards'),
        ),
      ),
    );
    if (picked != null) ref.read(compareChosenProvider.notifier).set(picked);
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.cells,
    this.header = false,
    this.total = false,
  });

  final String label;
  final List<_Cell> cells;
  final bool header;
  final bool total;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final style = (header || total ? ZType.title : ZType.body).copyWith(
      color: c.text,
    );
    return Row(
      children: [
        SizedBox(
          width: _labelWidth,
          height: ZSpacing.minTarget,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(label, style: style, overflow: TextOverflow.ellipsis),
          ),
        ),
        for (final cell in cells)
          SizedBox(
            width: _cellWidth,
            child: cell.build(context, header: header),
          ),
      ],
    );
  }
}

class _Cell {
  const _Cell({
    required this.text,
    this.semantics,
    this.onTap,
    this.total = false,
  });

  final String text;
  final String? semantics;
  final VoidCallback? onTap;
  final bool total;

  Widget build(BuildContext context, {required bool header}) {
    final c = ZColors.of(context);
    final base = header || total ? ZType.title : ZType.body;
    final child = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
      child: Align(
        alignment: header
            ? AlignmentDirectional.center
            : AlignmentDirectional.centerEnd,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: ZSpacing.xs,
          ),
          child: Text(
            text,
            maxLines: header ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            textAlign: header ? TextAlign.center : TextAlign.end,
            style: base.copyWith(
              color: c.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
    if (onTap == null) return child;
    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: semantics != null,
      onTap: onTap,
      child: InkWell(onTap: onTap, child: child),
    );
  }
}

class _ChooseBody extends StatefulWidget {
  const _ChooseBody({required this.data, required this.hint});
  final CompareData data;
  final String hint;

  @override
  State<_ChooseBody> createState() => _ChooseBodyState();
}

class _ChooseBodyState extends State<_ChooseBody> {
  late final Set<String> _picked = {
    for (final c in widget.data.cards) c.accountId,
  };

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.hint, style: ZType.caption.copyWith(color: c.textMuted)),
        for (final card in widget.data.available)
          CheckboxListTile(
            key: Key('compare-pick-${card.accountId}'),
            contentPadding: EdgeInsetsDirectional.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(card.label),
            value: _picked.contains(card.accountId),
            onChanged: (on) {
              setState(() {
                if (on == true) {
                  if (_picked.length < compareMaxCards) {
                    _picked.add(card.accountId);
                  }
                } else if (_picked.length > 1) {
                  _picked.remove(card.accountId);
                }
              });
            },
          ),
        const SizedBox(height: ZSpacing.md),
        ZButton(
          key: const Key('compare-pick-done'),
          label: AppLocalizations.of(context).commonActionDone,
          onPressed: () => Navigator.of(context).pop(_picked),
        ),
      ],
    );
  }
}
