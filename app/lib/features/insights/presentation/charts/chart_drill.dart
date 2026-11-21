// T-189: tapping a bar, a slice or a place opens the transactions list
// already filtered to it (category / merchant / period / currency), with the
// removable filter chips of the list, plus a header with the total, the
// count and the change against the period before. Reads providers only.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/l10n/locale_providers.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/amount_semantics.dart';
import '../../../../core/ui/z_money_text.dart';
import '../../../transactions/presentation/list/transactions_list_screen.dart';
import '../../../transactions/presentation/list/txn_list_providers.dart';
import '../../domain/chart_models.dart';
import '../../domain/chart_summary.dart';
import 'chart_format.dart';
import 'chart_overview.dart';
import 'charts_providers.dart';

/// The filter a chart tap opens the list with: expenses of [code] in
/// [period], narrowed to a category and/or merchant.
TxnListFilter drillFilter({
  required String code,
  required ChartPeriod period,
  Set<String> categoryIds = const {},
  String? merchantNorm,
  String? merchantName,
}) => TxnListFilter(
  period: TxnPeriod.custom,
  customFrom: period.from,
  customTo: period.to,
  categoryIds: categoryIds,
  type: TxnTypeFilter.expense,
  currency: Currency.of(code),
  merchantNorm: merchantNorm,
  merchantName: merchantName,
);

/// Opens the transactions list for a chart tap.
Future<void> openChartDrill(
  BuildContext context, {
  required String code,
  required ChartPeriod period,
  ChartPeriod? previous,
  Set<String> categoryIds = const {},
  String? merchantNorm,
  String? merchantName,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    builder: (_) => TransactionsListScreen(
      initialFilter: drillFilter(
        code: code,
        period: period,
        categoryIds: categoryIds,
        merchantNorm: merchantNorm,
        merchantName: merchantName,
      ),
      header: (_) => ChartDrillHeader(scopePeriod: period, previous: previous),
    ),
  ),
);

/// The total, count and change of what the list shows. It follows the list's
/// own chips: without a custom period or with several categories there is
/// nothing to total, so it hides.
class ChartDrillHeader extends ConsumerWidget {
  const ChartDrillHeader({super.key, required this.scopePeriod, this.previous});

  /// The period the list opened on, and the period it is compared with.
  final ChartPeriod scopePeriod;
  final ChartPeriod? previous;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(txnListFilterProvider);
    final from = f.customFrom;
    final to = f.customTo;
    final currency = f.currency;
    if (f.period != TxnPeriod.custom ||
        from == null ||
        to == null ||
        currency == null ||
        f.categoryIds.length > 1) {
      return const SizedBox.shrink();
    }
    final period = ChartPeriod(from, to);
    final before = period == scopePeriod && previous != null
        ? previous!
        : ChartPeriod(from.plusDays(-period.lengthDays), from.plusDays(-1));
    final categoryId = f.categoryIds.isEmpty ? null : f.categoryIds.first;
    DrillScope scope(ChartPeriod p) => (
      code: currency.code,
      period: p,
      categoryId: categoryId,
      merchantNorm: f.merchantNorm,
    );
    final now = ref.watch(drillTotalsProvider(scope(period)));
    final prev = ref.watch(drillTotalsProvider(scope(before)));
    final cur = now.value;
    final old = prev.value;
    if (cur == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final count = ref.watch(digitsModeProvider(lang)).render('${cur.count}');
    final change = old == null
        ? ChartChange.none
        : percentChange(cur.amount.minor, old.amount.minor);
    final total = chartMoney(ref, context, cur.amount);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: ZSpacing.lg,
        vertical: ZSpacing.sm,
      ),
      child: Semantics(
        container: true,
        excludeSemantics: true,
        label: a11yAmounts(
          l,
          l.insightsChartsDrillTotalA11y(
            total,
            count,
            changeA11y(ref, context, l, change),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ZMoneyText(
                    key: const Key('drill-total'),
                    text: total,
                    size: ZMoneySize.display,
                  ),
                  Text(
                    l.insightsChartsDrillTotal(count),
                    style: ZType.caption.copyWith(color: c.textMuted),
                  ),
                ],
              ),
            ),
            ChangeChip(change: change, tone: toneOf(change, moreIsGood: false)),
          ],
        ),
      ),
    );
  }
}
